import AppKit
import SwiftUI

/// Owns the one settings window. It is an ordinary window, unlike the click-through subtitle panel.
@MainActor
final class SettingsWindowController {
    private static let title = "KTV Lyrics 設定"

    private let model: SettingsViewModel
    private var window: NSWindow?

    init(model: SettingsViewModel) {
        self.model = model
    }

    /// Brings the window forward, creating it the first time. An accessory app must activate itself first.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = Self.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
