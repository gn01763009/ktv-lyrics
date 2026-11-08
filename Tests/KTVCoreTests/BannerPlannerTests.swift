@testable import KTVCore
import Testing

@Suite struct BannerPlannerTests {
    @Test func shortGapIsNotEligible() {
        let lines = [
            LyricLine(start: 0, end: 1, holdEnd: 1, text: "一"),
            LyricLine(start: 10.9, end: 12, holdEnd: 12, text: "二"),
        ]
        #expect(BannerPlanner.plan(lines: lines, seed: 1).isEmpty)
    }

    @Test func atMostTwoPerSong() {
        for seed in 0..<200 {
            #expect(BannerPlanner.plan(lines: gapped(10), seed: UInt64(seed)).count <= 2)
        }
    }

    @Test func sameSeedSamePlan() {
        #expect(BannerPlanner.plan(lines: gapped(6), seed: 7) == BannerPlanner.plan(lines: gapped(6), seed: 7))
    }

    @Test func aboutHalfOfEligibleGaps() {
        let hits = (0..<1000).filter { !BannerPlanner.plan(lines: gapped(1), seed: StableHash.fnv1a("s\($0)")).isEmpty }.count
        #expect((400...600).contains(hits))
    }
}
