@testable import KTVCore
import Testing

@Suite struct SweepTests {
    @Test func linearIsClamped() {
        let line = LyricLine(start: 10, end: 14, holdEnd: 14, text: "一")
        #expect(line.sweep(at: 12) == .linear(0.5))
        #expect(line.sweep(at: 9) == .linear(0))
        #expect(line.sweep(at: 99) == .linear(1))
    }

    @Test func zeroLengthLineIsDone() {
        #expect(LyricLine(start: 10, end: 10, holdEnd: 10, text: "一").sweep(at: 10) == .linear(1))
    }

    @Test func wordSweep() {
        let line = YRCParser.parse("[1000,3000](1000,1000,0)一(2000,2000,0)二").lines[0]
        #expect(line.sweep(at: 0.5) == .word(index: 0, progress: 0))
        #expect(line.sweep(at: 3) == .word(index: 1, progress: 0.5))
        #expect(line.sweep(at: 5) == .word(index: 1, progress: 1))
    }
}
