/// Shared LRC sample text for the KTVCore test targets.
enum Fixtures {
    /// Fifteen plain lines at 10s..24s, then a speaker-labelled line at 40s.
    /// The speaker label sits past the 14-row header window, so it must be kept.
    static let fifteenRowsThenSpeaker: String = {
        let rows = (0..<15).map { "[00:\(10 + $0).00]第\($0)句" }
        return (rows + ["[00:40.00]他說：你好"]).joined(separator: "\n")
    }()
}
