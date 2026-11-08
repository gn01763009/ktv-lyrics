@testable import KTVCore
import Testing

@Suite struct YRCParserTests {
    let sample = "[16210,3460](16210,670,0)还(16880,410,0)没"

    @Test func parsesWordTimes() {
        let line = YRCParser.parse(sample).lines[0]
        #expect(line.start == 16.21)
        #expect(line.text == "还没")
        #expect(line.words?[1] == WordTiming(text: "没", start: 16.88, duration: 0.41))
        #expect(abs(line.end - 17.29) < 0.001)
        #expect(line.holdEnd == line.end)
    }

    @Test func convertsPerTokenKeepingTimes() {
        let parsed = YRCParser.parse(sample, convert: TextConversion.toTraditional)
        #expect(parsed.lines[0].words?[0] == WordTiming(text: "還", start: 16.21, duration: 0.67))
    }

    @Test func readsCreditsFromJSONRows() {
        let raw = "{\"t\":0,\"c\":[{\"tx\":\"作词: \"},{\"tx\":\"五月天 阿信\"}]}\n"
            + "{\"t\":5598,\"c\":[{\"tx\":\"管弦乐团: \"},{\"tx\":\"某人\"}]}\n"
            + sample
        #expect(YRCParser.parse(raw).credits == ["作詞：五月天 阿信"])
    }

    @Test func skipsMalformedRows() {
        #expect(YRCParser.parse("[bad](1,2,0)x\n{not json\n" + sample).lines.count == 1)
    }
}
