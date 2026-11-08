@testable import KTVCore
import Testing

@Suite struct LRCParserTests {
    @Test func multipleTagsOnOneLine() {
        #expect(LRCParser.parse("[00:20.00][00:10.50]副歌").stamps == [
            LRCStamp(time: 10.5, text: "副歌"),
            LRCStamp(time: 20, text: "副歌"),
        ])
    }

    @Test func keepsBlankTagAsLineEnd() {
        #expect(LRCParser.parse("[00:10.00]一句\n[00:15.00]").stamps.last == LRCStamp(time: 15, text: ""))
    }

    @Test func movesCreditsOutOfBody() {
        let parsed = LRCParser.parse("[00:00.00]作词 : 方文山\n[00:01.00]作曲 : 周杰倫\n[00:02.00]製作人 : 某人\n[00:10.00]第一句")
        #expect(parsed.credits == ["作詞：方文山", "作曲：周杰倫"])
        #expect(parsed.stamps.map(\.text) == ["第一句"])
    }

    @Test func headerRuleStopsAfterFourteenRows() {
        #expect(LRCParser.parse(Fixtures.fifteenRowsThenSpeaker).stamps.last?.text == "他說：你好")
    }

    @Test func keepsPartLabels() {
        #expect(LRCParser.parse("[00:10.00]男：第一句").stamps.first?.text == "男：第一句")
    }

    @Test func keepsGenderedLabelLinesAsBody() {
        #expect(LRCParser.parse("[00:10.00]男生：我愛你").stamps == [LRCStamp(time: 10, text: "男生：我愛你")])
        #expect(LRCParser.parse("[00:10.00]女生：我愛你").stamps == [LRCStamp(time: 10, text: "女生：我愛你")])
    }

    @Test func keepsChorusLabelLineAsBody() {
        #expect(LRCParser.parse("[00:12.00]合唱：一起唱").stamps == [LRCStamp(time: 12, text: "合唱：一起唱")])
    }

    @Test func skipsMalformedRows() {
        #expect(LRCParser.parse("[aa:bb]x\n[99:99.99]y\n沒有時間\n{\"t\":0}\n[00:05.00]好").stamps == [
            LRCStamp(time: 5, text: "好"),
        ])
    }
}
