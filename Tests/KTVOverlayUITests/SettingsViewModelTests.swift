import Foundation
import KTVCore
@testable import KTVOverlayUI
import Testing

@Suite struct SettingsViewModelTests {
    // MARK: - Fakes

    private final class FakeResolver: LyricsResolving, @unchecked Sendable {
        let candidateList: [LyricsCandidate]
        init(candidates: [LyricsCandidate] = []) { candidateList = candidates }
        func resolve(_ query: TrackQuery) async -> LyricsOutcome { SettingsViewModelTests.found("預設") }
        func candidates(_ query: TrackQuery) async -> [LyricsCandidate] { candidateList }
    }

    private final class Calls {
        var settings: [OverlaySettings] = []
    }

    @MainActor private struct Rig {
        let coordinator: AppCoordinator
        let overrides: SongOverrideStore
        let directory: URL

        func playAndWait(_ title: String) async {
            coordinator.handle(.playing(SettingsViewModelTests.snapshot(title)))
            await coordinator.waitForLookup()
        }

        var query: TrackQuery { TitleNormalizer.query(from: SettingsViewModelTests.snapshot("歌")) }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    private static func snapshot(_ title: String) -> PlaybackSnapshot {
        PlaybackSnapshot(
            title: title, artist: "歌手", duration: 200, elapsed: 2, timestamp: 1_000,
            rate: 1, isPlaying: true, bundleID: "com.spotify.client"
        )
    }

    private static func found(_ text: String) -> LyricsOutcome {
        .found(Lyrics(source: .lrclib, lines: [line(text)], credits: []))
    }

    private static func line(_ text: String) -> LyricLine {
        LyricLine(start: 20, end: 24, holdEnd: 28, text: text)
    }

    @MainActor private static func rig(candidates: [LyricsCandidate] = []) -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ktv-settings-\(UUID().uuidString)")
        let overrides = SongOverrideStore(directory: directory.appendingPathComponent("overrides"))
        let resolver = FakeResolver(candidates: candidates)
        let coordinator = AppCoordinator(
            makeResolver: { _ in resolver },
            cache: LyricsCache(directory: directory.appendingPathComponent("cache")),
            overrides: overrides,
            settings: .defaults,
            clock: NoClock(),
            runningApps: { [] },
            now: { 1_000 }
        )
        return Rig(coordinator: coordinator, overrides: overrides, directory: directory)
    }

    private struct NoClock: PlayerClockReading {
        func read(_ player: ScriptablePlayer) -> PlayerSample? { nil }
    }

    @MainActor private static func model(
        store: any SettingsStoring,
        calls: Calls = Calls()
    ) -> SettingsViewModel {
        SettingsViewModel(store: store, onChange: { calls.settings.append($0) })
    }

    private static func isolatedStore() -> (UserDefaultsSettingsStore, () -> Void) {
        let name = "ktv-settings-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            fatalError("Could not create a UserDefaults suite")
        }
        return (UserDefaultsSettingsStore(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
    }

    // MARK: - Settings

    @Test @MainActor func presetReplacesStyle() {
        let (store, cleanUp) = Self.isolatedStore()
        defer { cleanUp() }
        let model = Self.model(store: store)
        model.selectPreset(.neon)
        #expect(model.settings.preset == .neon)
        #expect(model.settings.style == StylePreset.neon.style)
    }

    @Test @MainActor func tweakKeepsPresetName() {
        let (store, cleanUp) = Self.isolatedStore()
        defer { cleanUp() }
        let model = Self.model(store: store)
        let pink = RGBAColor(hex: 0xFF00AA)
        model.selectPreset(.gold)
        model.update { $0.with(\.style, $0.style.replacing(sungFill: pink)) }
        #expect(model.settings.preset == .gold)
        #expect(model.settings.style.sungFill == pink)
        #expect(model.settings.style.unsungFill == StylePreset.gold.style.unsungFill)
    }

    @Test @MainActor func everyChangePersistsAndNotifies() {
        let (store, cleanUp) = Self.isolatedStore()
        defer { cleanUp() }
        let calls = Calls()
        let model = Self.model(store: store, calls: calls)
        model.update { $0.with(\.size, 60) }
        #expect(store.load() == model.settings)
        #expect(store.load().size == 60)
        #expect(calls.settings == [model.settings])
    }

    // MARK: - Versions and import

    @Test @MainActor func selectedCandidateIsRemembered() async {
        let chosen = LyricsCandidate(id: "pick", label: "選的版本", lyrics: Lyrics(source: .netease, lines: [Self.line("選的")], credits: []))
        let rig = Self.rig(candidates: [chosen])
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        rig.coordinator.adjustOffset(by: 0.3)
        let offered = await rig.coordinator.availableCandidates()
        #expect(offered == [chosen])
        rig.coordinator.selectCandidate(id: "pick")
        #expect(rig.coordinator.content().lines.first?.text == "選的")
        #expect(rig.coordinator.selectedCandidateID == "pick")

        await rig.playAndWait("別首")
        await rig.playAndWait("歌")
        #expect(rig.coordinator.content().lines.first?.text == "選的")
        let saved = rig.overrides.load(rig.query)
        #expect(saved.candidateID == "pick")
        #expect(abs(saved.offset - 0.3) < 0.0001)
    }

    @Test @MainActor func importedLyricsWin() async {
        let rig = Self.rig()
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        rig.coordinator.adjustOffset(by: -0.3)
        rig.coordinator.importLRC("[00:20.00]匯入的歌詞\n[00:30.00]")
        #expect(rig.coordinator.content().lines.first?.text == "匯入的歌詞")
        #expect(rig.coordinator.statusText.contains("匯入的 .lrc"))

        await rig.playAndWait("別首")
        await rig.playAndWait("歌")
        #expect(rig.coordinator.content().lines.first?.text == "匯入的歌詞")
        let saved = rig.overrides.load(rig.query)
        #expect(saved.importedLRC != nil)
        #expect(abs(saved.offset + 0.3) < 0.0001)
    }

    @Test @MainActor func unusableImportKeepsLyricsAndShowsNotice() async {
        let rig = Self.rig()
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        rig.coordinator.importLRC("這不是 LRC，沒有任何時間標籤")
        let content = rig.coordinator.content()
        #expect(content.lines.first?.text == "預設")
        #expect(content.notice?.contains("匯入") == true)
        #expect(rig.overrides.load(rig.query).importedLRC == nil)
    }
}
