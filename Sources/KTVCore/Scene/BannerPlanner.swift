/// Standard 64-bit FNV-1a hash. Unlike `Hashable`, the value is the same in every process, so it is safe to store or seed with.
public enum StableHash {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01B3

    public static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(offsetBasis) { ($0 ^ UInt64($1)) &* prime }
    }
}

/// Chooses which interludes show the banner card. The same lines and seed always give the same plan.
public enum BannerPlanner {
    /// Chance that an eligible gap is picked for a banner.
    static let chancePerGap: Double = 0.5
    /// Most banners a single song gets.
    static let maxBannersPerSong = 2

    /// Returns the index of the line before each chosen gap.
    public static func plan(lines: [LyricLine], seed: UInt64) -> Set<Int> {
        let eligible = eligibleGaps(in: lines)
        let picked = zip(eligible, eligible.indices).lazy
            .filter { _, draw in SplitMix64.unitInterval(seed: seed, draw: draw) < chancePerGap }
            .map { gap, _ in gap }
            .prefix(maxBannersPerSong)
        return Set(picked)
    }

    /// Indexes of lines followed by a gap long enough for an interlude.
    private static func eligibleGaps(in lines: [LyricLine]) -> [Int] {
        lines.indices.dropLast().filter { index in
            lines[index + 1].start - lines[index].holdEnd >= LyricsTiming.interludeMinGap
        }
    }
}

/// Stateless SplitMix64: the n-th draw for a seed is computed directly, so no generator state is mutated.
enum SplitMix64 {
    private static let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15
    private static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9
    private static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB
    /// Keeps the top 53 bits so the result converts to Double exactly.
    private static let mantissaBits: UInt64 = 11
    private static let unitDivisor = Double(UInt64(1) << 53)

    /// The `draw`-th output (counting from 0) of SplitMix64 seeded with `seed`, mapped to 0..<1.
    static func unitInterval(seed: UInt64, draw: Int) -> Double {
        var mixed = seed &+ gamma &* UInt64(draw + 1)
        mixed = (mixed ^ (mixed >> 30)) &* firstMultiplier
        mixed = (mixed ^ (mixed >> 27)) &* secondMultiplier
        mixed ^= mixed >> 31
        return Double(mixed >> mantissaBits) / unitDivisor
    }
}
