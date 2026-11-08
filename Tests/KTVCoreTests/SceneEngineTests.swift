@testable import KTVCore
import Testing

@Suite struct SceneEngineTests {
    /// 第一句 20 秒開始，兩句相連，之後 15 秒空檔再接第三句。
    private let song = [
        LyricLine(start: 20, end: 23, holdEnd: 23, text: "一"),
        LyricLine(start: 24, end: 27, holdEnd: 27, text: "二"),
        LyricLine(start: 42, end: 45, holdEnd: 45, text: "三"),
    ]

    private var engine: SceneEngine { SceneEngine(lines: song, bannerAfter: [1]) }

    @Test func titleOnlyInFirstTenSeconds() {
        #expect(engine.scene(at: 5) == .title)
        #expect(engine.scene(at: 12) == .idle)
    }

    @Test func starsCountDown() {
        #expect(engine.scene(at: 16.8) == .countdown(upcoming: 0, stars: 4))
        #expect(engine.scene(at: 19.5) == .countdown(upcoming: 0, stars: 1))
    }

    @Test func singingThenHeld() {
        #expect(engine.scene(at: 21.5) == .singing(index: 0, sweep: .linear(0.5)))
        #expect(engine.scene(at: 23.5) == .held(index: 0))
    }

    @Test func interludeWithBannerThenStars() {
        #expect(engine.scene(at: 30) == .interlude(showBanner: true))
        #expect(engine.scene(at: 39) == .countdown(upcoming: 2, stars: 4))
    }

    @Test func lineBeforeAnInterludeStaysHeldUntilItsHoldEnds() {
        let lines = [
            LyricLine(start: 20, end: 23, holdEnd: 31, text: "一"),
            LyricLine(start: 50, end: 53, holdEnd: 53, text: "二"),
        ]
        let engine = SceneEngine(lines: lines, bannerAfter: [0])
        #expect(engine.scene(at: 23.5) == .held(index: 0))
        #expect(engine.scene(at: 30.9) == .held(index: 0))
        #expect(engine.scene(at: 31) == .interlude(showBanner: true))
        #expect(engine.scene(at: 47) == .countdown(upcoming: 1, stars: 4))
    }

    @Test func interludeWithoutBanner() {
        #expect(SceneEngine(lines: song, bannerAfter: []).scene(at: 30) == .interlude(showBanner: false))
    }

    @Test func endsThreeSecondsAfterLastLine() {
        #expect(engine.scene(at: 47) == .held(index: 2))
        #expect(engine.scene(at: 48.1) == .idle)
    }

    @Test func noLinesIsIdle() {
        #expect(SceneEngine(lines: [], bannerAfter: []).scene(at: 5) == .idle)
    }

    @Test func firstLineAtStartSkipsTitle() {
        let line = LyricLine(start: 0.33, end: 2, holdEnd: 2, text: "一")
        let scene = SceneEngine(lines: [line], bannerAfter: []).scene(at: 0.1)
        #expect(scene == .countdown(upcoming: 0, stars: 1))
    }
}
