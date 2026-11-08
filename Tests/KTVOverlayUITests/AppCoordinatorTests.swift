import Foundation
import KTVCore
@testable import KTVOverlayUI
import Testing

@Suite struct AppCoordinatorTests {
    // MARK: - Fakes

    /// A gate a fake resolver can wait on until the test opens it.
    private actor Latch {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private final class FakeResolver: LyricsResolving, @unchecked Sendable {
        private let lock = NSLock()
        private var resolved: [String] = []
        private var finished = 0
        private let outcomes: [String: LyricsOutcome]
        private let stalls: [String: Latch]
        private let candidateList: [LyricsCandidate]

        init(
            outcomes: [String: LyricsOutcome] = [:],
            stalls: [String: Latch] = [:],
            candidates: [LyricsCandidate] = []
        ) {
            self.outcomes = outcomes
            self.stalls = stalls
            self.candidateList = candidates
        }

        var resolveCalls: [String] { lock.withLock { resolved } }
        var finishedCount: Int { lock.withLock { finished } }

        func resolve(_ query: TrackQuery) async -> LyricsOutcome {
            lock.withLock { resolved.append(query.title) }
            await stalls[query.title]?.wait()
            lock.withLock { finished += 1 }
            return outcomes[query.title] ?? .notFound
        }

        func candidates(_ query: TrackQuery) async -> [LyricsCandidate] { candidateList }
    }

    private final class FakeClock: PlayerClockReading {
        var sample: PlayerSample?
        private(set) var reads = 0

        func read(_ player: ScriptablePlayer) -> PlayerSample? {
            reads += 1
            return sample
        }
    }

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    // MARK: - Rig

    private static let spotify = "com.spotify.client"

    @MainActor private struct Rig {
        let coordinator: AppCoordinator
        let time: Box<Double>
        let clock: FakeClock
        let running: Box<Set<String>>
        let built: Box<[Bool]>
        let cache: LyricsCache
        let overrides: SongOverrideStore
        let directory: URL

        func play(_ title: String, elapsed: Double = 2, artist: String = "歌手", duration: Double = 200) {
            coordinator.handle(.playing(AppCoordinatorTests.snapshot(
                title, elapsed: elapsed, artist: artist, duration: duration, now: time.value
            )))
        }

        func playAndWait(_ title: String, elapsed: Double = 2) async {
            play(title, elapsed: elapsed)
            await coordinator.waitForLookup()
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor private static func rig(
        on: FakeResolver = FakeResolver(),
        off: FakeResolver = FakeResolver(),
        settings: OverlaySettings = .defaults
    ) -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ktv-coordinator-\(UUID().uuidString)")
        let cache = LyricsCache(directory: directory.appendingPathComponent("cache"))
        let overrides = SongOverrideStore(directory: directory.appendingPathComponent("overrides"))
        let time = Box(1_000.0)
        let clock = FakeClock()
        let running = Box<Set<String>>([spotify])
        let built = Box<[Bool]>([])
        let coordinator = AppCoordinator(
            makeResolver: { useNetEase in
                built.value.append(useNetEase)
                return useNetEase ? on : off
            },
            cache: cache,
            overrides: overrides,
            settings: settings,
            clock: clock,
            runningApps: { running.value },
            now: { time.value }
        )
        return Rig(
            coordinator: coordinator, time: time, clock: clock, running: running,
            built: built, cache: cache, overrides: overrides, directory: directory
        )
    }

    private static func snapshot(
        _ title: String,
        elapsed: Double,
        artist: String = "歌手",
        playing: Bool = true,
        duration: Double = 200,
        now: Double
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            title: title, artist: artist, duration: duration, elapsed: elapsed, timestamp: now,
            rate: 1, isPlaying: playing, bundleID: spotify
        )
    }

    private static func line(_ text: String, start: Double, words: Bool = false) -> LyricLine {
        LyricLine(
            start: start, end: start + 4, holdEnd: start + 8, text: text,
            words: words ? [WordTiming(text: text, start: start, duration: 4)] : nil
        )
    }

    private static func found(_ text: String = "歌詞", start: Double = 20, source: LyricsSource = .lrclib, words: Bool = false) -> LyricsOutcome {
        .found(Lyrics(source: source, lines: [line(text, start: start, words: words)], credits: ["作詞：某人"]))
    }

    private static func singingIndex(_ scene: KaraokeScene) -> Int? {
        if case .singing(let index, _) = scene { return index }
        return nil
    }

    private static func isCountdown(_ scene: KaraokeScene) -> Bool {
        if case .countdown = scene { return true }
        return false
    }

    // MARK: - Tests

    @Test @MainActor func trackChangeLooksUpThenShowsTitle() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["簡單愛": Self.found()]))
        defer { rig.cleanUp() }
        rig.play("簡單愛 (Live)")
        #expect(rig.coordinator.content().notice?.contains("正在找《簡單愛》") == true)
        await rig.coordinator.waitForLookup()
        let content = rig.coordinator.content()
        #expect(content.scene == .title)
        #expect(content.title == "簡單愛")
        #expect(content.artist == "歌手")
        #expect(content.credits == ["作詞：某人"])
        #expect(content.notice == nil)
        #expect(rig.coordinator.statusText == "簡單愛（LRCLIB，1 行）")
    }

    @Test @MainActor func seekSnapsOnNextPoll() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found(start: 32)]))
        defer { rig.cleanUp() }
        rig.clock.sample = PlayerSample(position: 2, isPlaying: true, at: rig.time.value)
        await rig.playAndWait("歌")
        #expect(rig.coordinator.content().scene == .title)
        rig.clock.sample = PlayerSample(position: 32, isPlaying: true, at: rig.time.value)
        rig.coordinator.pollClock()
        #expect(Self.singingIndex(rig.coordinator.content().scene) == 0)
    }

    @Test @MainActor func nothingPlayingClearsOverlay() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found()]))
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        let readsBefore = rig.clock.reads
        rig.coordinator.handle(.nothing)
        rig.coordinator.pollClock()
        let content = rig.coordinator.content()
        #expect(content.scene == .idle)
        #expect(content.lines.isEmpty)
        #expect(content.notice == nil)
        #expect(rig.clock.reads == readsBefore)
        #expect(rig.coordinator.statusText == "等待播放…")
    }

    @Test @MainActor func ignoredEventChangesNothing() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found()]))
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        let before = rig.coordinator.content()
        rig.coordinator.handle(.ignored)
        #expect(rig.coordinator.content() == before)
    }

    @Test @MainActor func closedPlayerIsNotPolled() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found()]))
        defer { rig.cleanUp() }
        rig.running.value = []
        await rig.playAndWait("歌")
        rig.coordinator.pollClock()
        #expect(rig.clock.reads == 0)
    }

    @Test @MainActor func rapidSkipKeepsNewestLyrics() async throws {
        let latch = Latch()
        let resolver = FakeResolver(
            outcomes: ["A": Self.found("A 的歌詞"), "B": Self.found("B 的歌詞")],
            stalls: ["A": latch]
        )
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        rig.play("A")
        rig.play("B")
        await rig.coordinator.waitForLookup()
        await latch.open()
        try await Self.waitUntil { resolver.finishedCount == 2 }
        await Task.yield()
        #expect(rig.coordinator.content().lines.first?.text == "B 的歌詞")
        #expect(rig.coordinator.statusText.hasPrefix("B（"))
    }

    @Test @MainActor func cacheHitSkipsResolver() async throws {
        let resolver = FakeResolver()
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, now: rig.time.value))
        try rig.cache.save(Self.found("快取歌詞"), for: query)
        await rig.playAndWait("歌")
        #expect(resolver.resolveCalls.isEmpty)
        #expect(rig.coordinator.content().lines.first?.text == "快取歌詞")
    }

    @Test @MainActor func resolvedOutcomeIsCached() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found("網路歌詞")]))
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, now: rig.time.value))
        #expect(rig.cache.load(query)?.lyrics?.lines.first?.text == "網路歌詞")
    }

    @Test @MainActor func notFoundShowsNotice() async {
        let rig = Self.rig()
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        let content = rig.coordinator.content()
        #expect(content.notice == "♪ 找不到《歌》的字幕")
        #expect(content.scene == .idle)
        #expect(rig.coordinator.statusText == "找不到字幕：歌")
        rig.time.value += 7
        #expect(rig.coordinator.content().notice == nil)
    }

    @Test @MainActor func unavailableShowsRetryNoticeAndIsNotCached() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": .unavailable]))
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        let content = rig.coordinator.content()
        #expect(content.notice == "♪ 暫時查不到字幕，下次播放會再試一次")
        #expect(content.scene == .idle)
        #expect(rig.coordinator.statusText == "暫時查不到：歌")
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, now: rig.time.value))
        #expect(rig.cache.load(query) == nil)
        rig.time.value += 7
        #expect(rig.coordinator.content().notice == nil)
    }

    @Test @MainActor func partialOutcomeShowsLyricsButIsNotCached() async {
        let lyrics = Lyrics(source: .lrclib, lines: [Self.line("部分", start: 20)], credits: [])
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": .foundPartial(lyrics)]))
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        #expect(rig.coordinator.content().lines.first?.text == "部分")
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, now: rig.time.value))
        #expect(rig.cache.load(query) == nil)
    }

    @Test @MainActor func unknownDurationHoldsTheLookupThenSearchesWithoutCaching() async {
        let resolver = FakeResolver(outcomes: ["歌": Self.found("暫時")])
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        rig.play("歌", duration: 0)
        rig.time.value += 1.0
        rig.coordinator.advance()
        #expect(resolver.resolveCalls.isEmpty)
        rig.time.value += 0.6
        rig.coordinator.advance()
        await rig.coordinator.waitForLookup()
        #expect(resolver.resolveCalls == ["歌"])
        #expect(rig.coordinator.content().lines.first?.text == "暫時")
        let unknown = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, duration: 0, now: rig.time.value))
        #expect(rig.cache.load(unknown) == nil)
    }

    @Test @MainActor func durationArrivingInTheGraceWindowStartsTheRealLookup() async {
        let resolver = FakeResolver(outcomes: ["歌": Self.found("完整")])
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        rig.play("歌", duration: 0)
        rig.time.value += 0.5
        rig.play("歌", duration: 200)
        await rig.coordinator.waitForLookup()
        #expect(resolver.resolveCalls == ["歌"])
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, duration: 200, now: rig.time.value))
        #expect(rig.cache.load(query)?.lyrics?.lines.first?.text == "完整")
        rig.time.value += 5
        rig.coordinator.advance()
        await rig.coordinator.waitForLookup()
        #expect(resolver.resolveCalls == ["歌"])
    }

    @Test @MainActor func aLaterDurationChangeOverOneSecondLooksUpAgain() async {
        let resolver = FakeResolver(outcomes: ["歌": Self.found()])
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        await rig.playAndWait("歌")
        rig.play("歌", duration: 200.8)
        await rig.coordinator.waitForLookup()
        #expect(resolver.resolveCalls.count == 1)
        rig.play("歌", duration: 215)
        await rig.coordinator.waitForLookup()
        #expect(resolver.resolveCalls.count == 2)
    }

    @Test @MainActor func lookupNoticeExpiresAfterEightSeconds() async {
        let latch = Latch()
        let rig = Self.rig(on: FakeResolver(stalls: ["歌": latch]))
        defer { rig.cleanUp() }
        rig.play("歌")
        #expect(rig.coordinator.statusText == "查詢中：歌")
        rig.time.value += 7
        #expect(rig.coordinator.content().notice != nil)
        rig.time.value += 2
        #expect(rig.coordinator.content().notice == nil)
        await latch.open()
        await rig.coordinator.waitForLookup()
    }

    @Test @MainActor func leadOnlyForLineTimedLyrics() async {
        let lineTimed = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found()]))
        defer { lineTimed.cleanUp() }
        await lineTimed.playAndWait("歌", elapsed: 19.8)
        #expect(Self.singingIndex(lineTimed.coordinator.content().scene) == 0)

        let wordTimed = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found(source: .netease, words: true)]))
        defer { wordTimed.cleanUp() }
        await wordTimed.playAndWait("歌", elapsed: 19.8)
        let scene = wordTimed.coordinator.content().scene
        #expect(Self.singingIndex(scene) == nil)
        #expect(Self.isCountdown(scene))
        #expect(wordTimed.coordinator.statusText == "歌（網易雲 · 逐字，1 行）")
    }

    @Test @MainActor func offsetIsRememberedPerSong() async {
        let outcomes = ["A": Self.found(), "B": Self.found()]
        let rig = Self.rig(on: FakeResolver(outcomes: outcomes))
        defer { rig.cleanUp() }
        await rig.playAndWait("A", elapsed: 19.6)
        #expect(Self.isCountdown(rig.coordinator.content().scene))
        rig.coordinator.adjustOffset(by: 0.3)
        #expect(Self.singingIndex(rig.coordinator.content().scene) == 0)
        await rig.playAndWait("B", elapsed: 19.6)
        #expect(Self.isCountdown(rig.coordinator.content().scene))
        await rig.playAndWait("A", elapsed: 19.6)
        #expect(Self.singingIndex(rig.coordinator.content().scene) == 0)
        let query = TitleNormalizer.query(from: Self.snapshot("A", elapsed: 0, now: 0))
        #expect(abs(rig.overrides.load(query).offset - 0.3) < 0.0001)
    }

    @Test @MainActor func settingsHideCards() async throws {
        let lines = [Self.line("第一句", start: 20), Self.line("第二句", start: 40)]
        let title = try #require((0..<200).map { "歌\($0)" }.first { name in
            let key = Self.snapshot(name, elapsed: 0, now: 0).trackKey
            return BannerPlanner.plan(lines: lines, seed: StableHash.fnv1a(key)).contains(0)
        })
        let outcome = LyricsOutcome.found(Lyrics(source: .lrclib, lines: lines, credits: []))
        let rig = Self.rig(on: FakeResolver(outcomes: [title: outcome]))
        defer { rig.cleanUp() }
        await rig.playAndWait(title, elapsed: 2)
        #expect(rig.coordinator.content().scene == .title)
        rig.coordinator.apply(settings: .defaults.with(\.showTitleCard, false))
        #expect(rig.coordinator.content().scene == .idle)

        rig.time.value += 28
        #expect(rig.coordinator.content().scene == .interlude(showBanner: true))
        rig.coordinator.apply(settings: .defaults.with(\.showBanner, false))
        #expect(rig.coordinator.content().scene == .interlude(showBanner: false))

        rig.time.value += 7
        #expect(Self.isCountdown(rig.coordinator.content().scene))
        rig.coordinator.apply(settings: .defaults.with(\.showCountdown, false))
        #expect(rig.coordinator.content().scene == .idle)
    }

    @Test @MainActor func netEaseSettingIsPassedThrough() async {
        let on = FakeResolver(outcomes: ["歌": Self.found("開")])
        let off = FakeResolver(outcomes: ["歌": Self.found("關")])
        let rig = Self.rig(on: on, off: off)
        defer { rig.cleanUp() }
        rig.coordinator.apply(settings: .defaults.with(\.useNetEase, false))
        await rig.playAndWait("歌")
        #expect(rig.built.value == [true, false])
        #expect(on.resolveCalls.isEmpty)
        #expect(off.resolveCalls == ["歌"])
        #expect(rig.coordinator.content().lines.first?.text == "關")
    }

    @Test @MainActor func unchangedNetEaseSettingKeepsResolver() {
        let rig = Self.rig()
        defer { rig.cleanUp() }
        rig.coordinator.apply(settings: .defaults.with(\.showBanner, false))
        #expect(rig.built.value == [true])
    }

    @Test @MainActor func importedLRCBeatsCacheAndResolver() async throws {
        let resolver = FakeResolver(outcomes: ["歌": Self.found("網路")])
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, now: rig.time.value))
        try rig.cache.save(Self.found("快取"), for: query)
        try rig.overrides.save(SongOverride(offset: 0, importedLRC: "[00:20.00]匯入的歌詞\n[00:30.00]", candidateID: nil), for: query)
        await rig.playAndWait("歌")
        #expect(resolver.resolveCalls.isEmpty)
        #expect(rig.coordinator.content().lines.first?.text == "匯入的歌詞")
    }

    @Test @MainActor func storedCandidateIsHonouredOrFallsBack() async throws {
        let chosen = LyricsCandidate(id: "pick", label: "選的版本", lyrics: Lyrics(source: .netease, lines: [Self.line("選的", start: 20)], credits: []))
        let resolver = FakeResolver(outcomes: ["歌": Self.found("預設")], candidates: [chosen])
        let rig = Self.rig(on: resolver)
        defer { rig.cleanUp() }
        let query = TitleNormalizer.query(from: Self.snapshot("歌", elapsed: 2, now: rig.time.value))
        try rig.overrides.save(SongOverride(offset: 0, importedLRC: nil, candidateID: "pick"), for: query)
        await rig.playAndWait("歌")
        #expect(rig.coordinator.content().lines.first?.text == "選的")

        try rig.overrides.save(SongOverride(offset: 0, importedLRC: nil, candidateID: "gone"), for: query)
        await rig.playAndWait("別首")
        await rig.playAndWait("歌")
        #expect(rig.coordinator.content().lines.first?.text == "預設")
    }

    @Test @MainActor func adapterStatusShowsInStatusText() async {
        let rig = Self.rig()
        defer { rig.cleanUp() }
        #expect(rig.coordinator.statusText == "等待播放…")
        rig.coordinator.setAdapterStatus(.restarting(attempt: 1))
        #expect(rig.coordinator.statusText == "抓歌工具重新啟動中…")
        rig.coordinator.setAdapterStatus(.failed)
        #expect(rig.coordinator.statusText == "偵測不到播放器")
        rig.coordinator.setAdapterStatus(.running)
        #expect(rig.coordinator.statusText == "等待播放…")
    }

    @Test @MainActor func pausePositionIsFrozen() async {
        let rig = Self.rig(on: FakeResolver(outcomes: ["歌": Self.found()]))
        defer { rig.cleanUp() }
        rig.coordinator.handle(.playing(Self.snapshot("歌", elapsed: 19.6, playing: false, now: rig.time.value)))
        await rig.coordinator.waitForLookup()
        rig.time.value += 30
        #expect(Self.isCountdown(rig.coordinator.content().scene))
    }

    // MARK: - Helpers

    private static func waitUntil(timeout: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            try #require(Date() < deadline, "timed out waiting for the condition")
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
