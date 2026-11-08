@testable import KTVCore
import Testing

@Suite struct LyricsBuilderTests {
    @Test func rateIsLowerQuartile() {
        #expect(LyricsBuilder.songRate(stamps: stamps(gaps: [1.6, 1.6, 2, 2, 2.4, 2.4, 2.8, 2.8], chars: 4)) == 0.5)
    }

    @Test func rateIsCapped() {
        #expect(LyricsBuilder.songRate(stamps: stamps(gaps: [20, 20, 20, 20], chars: 4)) == 0.7)
    }

    @Test func rateFallsBackWithoutGaps() {
        #expect(LyricsBuilder.songRate(stamps: []) == 0.45)
    }

    @Test func countsOnlySungCharacters() {
        #expect(LyricsBuilder.sungCount("你好, world!") == 7)
    }

    @Test func endUsesRateNotGap() {
        let line = LyricsBuilder.lines(from: parsed(gaps: [8, 4, 4, 4], chars: 10))[0]
        // 唱速 0.4 × 10 字，不是行距 8 秒
        #expect(abs((line.end - line.start) - 4.0) < 0.001)
    }

    @Test func endNeverPassesNextLine() {
        let lines = LyricsBuilder.lines(from: parsed(gaps: [2, 9, 9, 9], chars: 10))
        #expect(lines[0].end <= lines[1].start - 0.12 + 0.0001)
    }

    @Test func blankTagEndsLine() {
        let lines = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]一二三四\n[00:11.00]\n[00:30.00]五六七八"))
        #expect(abs(lines[0].holdEnd - 10.88) < 0.001)
    }

    @Test func slotsAlternateAndRestartAfterInterlude() {
        let lines = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]一\n[00:13.00]二\n[00:16.00]三\n[00:40.00]四\n[00:43.00]五"))
        #expect(lines.map(\.slot) == [1, 0, 1, 1, 0])
    }

    @Test func stripsPartLabel() {
        let line = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]男：第一句\n[00:13.00]下一句"))[0]
        #expect(line.text == "第一句" && line.part == "男：")
    }

    @Test func normalizesParenthesizedPartLabel() {
        let line = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00](女)：第一句\n[00:13.00]下一句"))[0]
        #expect(line.text == "第一句" && line.part == "女：")
    }

    @Test func keepsGenderedWordAsLyricText() {
        let line = LyricsBuilder.lines(from: LRCParser.parse("[00:10.00]男生：我愛你\n[00:13.00]下一句"))[0]
        #expect(line.text == "男生：我愛你" && line.part == nil)
    }
}
