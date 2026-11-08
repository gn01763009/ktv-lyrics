import AppKit
import KTVCore
import os
import QuartzCore

/// Starts the menu-bar app.
public enum AppLauncher {
    @MainActor public static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let controller = AppController()
        application.delegate = controller
        withExtendedLifetime(controller) { application.run() }
    }
}

/// Owns the window, menu, adapter and timers, and connects them to the coordinator.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "AppController")

    private static let panelWidthFraction: CGFloat = 0.92
    private static let panelMaxWidth: CGFloat = 1500
    private static let panelHeight: CGFloat = 320
    private static let clockPollSeconds: TimeInterval = 1
    private static let offsetStep = 0.3
    private static let adapterOptions = ["stream", "--no-diff", "--no-artwork", "--micros", "--debounce=100"]
    private static let perl = "/usr/bin/perl"

    private let settingsStore = UserDefaultsSettingsStore()
    private var settings: OverlaySettings
    private let coordinator: AppCoordinator
    private let paths = AppPaths.current()
    private let view = OverlayView(frame: .zero)
    private var panel: OverlayPanel?
    private var adapter: AdapterProcess?
    private var menu: StatusMenuController?
    private var hotKey: HotKeyCenter?
    private var displayLink: CADisplayLink?
    private var clockTimer: Timer?
    private var terminationSignal: DispatchSourceSignal?

    override init() {
        let settings = settingsStore.load()
        self.settings = settings
        coordinator = AppCoordinator(
            makeResolver: Self.makeResolver,
            cache: LyricsCache(directory: paths.cacheDirectory),
            overrides: SongOverrideStore(directory: paths.overridesDirectory),
            settings: settings,
            clock: PlayerClockReader(),
            runningApps: { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) },
            now: { Date().timeIntervalSince1970 }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        buildMenu()
        hotKey = HotKeyCenter { [weak self] in MainActor.assumeIsolated { self?.toggleMoveMode() } }
        if hotKey == nil { Self.logger.error("The move-mode hot key could not be registered") }
        startAdapter()
        startTimers()
        listenForTermination()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        adapter?.stop()
        displayLink?.invalidate()
        clockTimer?.invalidate()
        menu?.removeFromMenuBar()
    }

    // MARK: - Setup

    private static func makeResolver(useNetEase: Bool) -> any LyricsResolving {
        let http = URLSessionFetcher()
        return LyricsResolver(lrclib: LRCLIBClient(http: http), netease: useNetEase ? NetEaseClient(http: http) : nil)
    }

    private func buildPanel() {
        view.settings = settings
        let panel = OverlayPanel(contentRect: panelFrame(), view: view)
        panel.onMoved = { [weak self] frame in self?.saveMovedPanel(frame) }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func buildMenu() {
        menu = StatusMenuController(
            actions: StatusMenuController.Actions(
                statusText: { [coordinator] in coordinator.statusText },
                showEarlier: { [coordinator] in coordinator.adjustOffset(by: Self.offsetStep) },
                showLater: { [coordinator] in coordinator.adjustOffset(by: -Self.offsetStep) },
                toggleMoveMode: { [weak self] in self?.toggleMoveMode() },
                toggleVisibility: { [weak self] in self?.toggleVisibility() },
                quit: { NSApp.terminate(nil) }
            ),
            offsetStep: Self.offsetStep
        )
    }

    private func startAdapter() {
        guard let script = paths.adapterScript, let framework = paths.adapterFramework,
              FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else {
            Self.logger.error("The now-playing helper is missing from the app bundle")
            coordinator.setAdapterStatus(.failed)
            return
        }
        let process = AdapterProcess(
            executable: Self.perl,
            arguments: [script.path, framework.path] + Self.adapterOptions,
            onEvent: { [weak self] event in MainActor.assumeIsolated { self?.coordinator.handle(event) } },
            onStatus: { [weak self] status in MainActor.assumeIsolated { self?.coordinator.setAdapterStatus(status) } }
        )
        adapter = process
        process.start()
    }

    private func startTimers() {
        let link = view.displayLink(target: self, selector: #selector(redraw(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        let timer = Timer(timeInterval: Self.clockPollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.pollClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    /// A plain SIGTERM would skip `applicationWillTerminate` and leave the helper running.
    private func listenForTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    // MARK: - Actions

    @objc private func redraw(_ link: CADisplayLink) {
        let next = coordinator.content()
        if next != view.content { view.content = next }
    }

    @objc private func screensChanged() {
        panel?.setFrame(panelFrame(), display: true)
    }

    private func toggleMoveMode() {
        guard let panel else { return }
        if !panel.isVisible { panel.orderFrontRegardless() }
        panel.isMoveMode.toggle()
    }

    private func toggleVisibility() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    // MARK: - Placement

    private func panelFrame() -> CGRect {
        let screens = ScreenInfo.connected
        let target = screens.first { $0.id == settings.displayID } ?? screens.first
        let width = min((target?.frame.width ?? Self.panelMaxWidth) * Self.panelWidthFraction, Self.panelMaxWidth)
        return PanelPlacement.frame(
            settings: settings,
            contentSize: CGSize(width: width, height: Self.panelHeight),
            screens: screens
        )
    }

    /// Saves where the user dropped the panel, on the screen it overlaps most.
    private func saveMovedPanel(_ frame: CGRect) {
        let best = ScreenInfo.connected.max { overlapArea($0.frame, frame) < overlapArea($1.frame, frame) }
        guard let screen = best else {
            Self.logger.error("The panel was moved but no screen is connected; position not saved")
            return
        }
        settings = settings
            .with(\.anchor, PanelPlacement.anchor(for: frame, on: screen))
            .with(\.displayID, screen.id)
        settingsStore.save(settings)
        coordinator.apply(settings: settings)
    }

    private func overlapArea(_ screen: CGRect, _ frame: CGRect) -> CGFloat {
        let overlap = screen.intersection(frame)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
