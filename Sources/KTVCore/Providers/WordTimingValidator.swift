/// Checks that word-timed lyrics are the same version as LRC lines, by comparing where their lines start.
public enum WordTimingValidator {
    /// Below this many lines on either side the comparison is meaningless, so the check passes.
    private static let minimumLineCount = 3

    /// Pairs each word line with the LRC line nearest in start time, and compares the median gap with the tolerance.
    public static func isSameVersion(words: [LyricLine], lines: [LyricLine]) -> Bool {
        guard words.count >= minimumLineCount, lines.count >= minimumLineCount else { return true }
        let gaps = words.map { word in
            lines.map { abs($0.start - word.start) }.min() ?? .infinity
        }
        return median(gaps) <= LyricsTiming.versionMismatchSeconds
    }

    /// The middle value, or the mean of the two middle values for an even count. `values` is never empty here.
    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
