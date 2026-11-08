@testable import KTVCore

/// Stamps for `gaps.count` lines of `chars` characters each, starting at 10s.
/// Gap i is the distance from line i to the next stamp; a blank end marker closes the last line.
func stamps(gaps: [Double], chars: Int) -> [LRCStamp] {
    let text = String(repeating: "字", count: chars)
    let times = gaps.indices.map { 10 + gaps[..<$0].reduce(0, +) } + [10 + gaps.reduce(0, +)]
    let lineStamps = times.dropLast().map { LRCStamp(time: $0, text: text) }
    return lineStamps + [LRCStamp(time: times.last ?? 10, text: "")]
}

/// The same stamps wrapped as a `ParsedLRC` with no credits.
func parsed(gaps: [Double], chars: Int) -> ParsedLRC {
    ParsedLRC(stamps: stamps(gaps: gaps, chars: chars), credits: [])
}

/// Shared LRC sample text for the KTVCore test targets.
enum Fixtures {
    /// Fifteen plain lines at 10s..24s, then a speaker-labelled line at 40s.
    /// The speaker label sits past the 14-row header window, so it must be kept.
    static let fifteenRowsThenSpeaker: String = {
        let rows = (0..<15).map { "[00:\(10 + $0).00]第\($0)句" }
        return (rows + ["[00:40.00]他說：你好"]).joined(separator: "\n")
    }()
}
