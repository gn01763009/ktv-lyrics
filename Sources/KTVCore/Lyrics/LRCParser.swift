import Foundation

/// Parses LRC text into timed stamps and credit lines.
/// Parsing is pure and tolerant: malformed rows are skipped, never fatal.
public enum LRCParser {
    private static let secondsPerMinute: Double = 60
    /// Only the first rows of a file can hold credits or a song header.
    private static let headerRowLimit = 14

    private static let tagPattern = #/\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]/#
    private static let headerPattern = #/^[^:：]{1,10}\s*[:：]/#
    private static let partPattern = #/^[(（]?(男|女|合)[)）]?\s*[:：]\s*/#
    private static let creditPattern = #/^(作词|作詞|作曲)\s*[:：]\s*(.+)$/#

    private enum HeaderRole: Equatable {
        case body
        case credit(String)
        case dropped
    }

    public static func parse(_ raw: String) -> ParsedLRC {
        let stamps = parseStamps(raw)
        let roles = stamps.enumerated().map { classify($0.element, index: $0.offset) }
        let body = zip(stamps, roles).compactMap { stamp, role in role == .body ? stamp : nil }
        let credits = roles.compactMap { role -> String? in
            if case .credit(let line) = role { return line }
            return nil
        }
        return ParsedLRC(stamps: body, credits: credits)
    }

    private static func parseStamps(_ raw: String) -> [LRCStamp] {
        raw.split(whereSeparator: \.isNewline)
            .flatMap { stamps(inLine: $0) }
            .sorted { $0.time < $1.time }
    }

    /// A row may carry several time tags; all of them share the text after the last tag.
    private static func stamps(inLine line: Substring) -> [LRCStamp] {
        let tags = line.matches(of: tagPattern)
        guard let last = tags.last else { return [] }
        let text = String(line[last.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return tags.compactMap { tag -> LRCStamp? in
            guard let time = timeInSeconds(minutes: tag.output.1, seconds: tag.output.2) else { return nil }
            return LRCStamp(time: time, text: text)
        }
    }

    private static func timeInSeconds(minutes: Substring, seconds: Substring) -> Double? {
        guard let minuteValue = Double(minutes),
              let secondValue = Double(seconds.replacing(":", with: ".")),
              secondValue < secondsPerMinute else { return nil }
        return minuteValue * secondsPerMinute + secondValue
    }

    /// Credits and speaker-less headers appear only in the first rows. Part labels (男/女/合) are lyrics.
    private static func classify(_ stamp: LRCStamp, index: Int) -> HeaderRole {
        guard index < headerRowLimit, !stamp.text.isEmpty,
              stamp.text.firstMatch(of: partPattern) == nil,
              stamp.text.firstMatch(of: headerPattern) != nil else { return .body }
        guard let match = stamp.text.firstMatch(of: creditPattern) else { return .dropped }
        let label = match.1.contains("曲") ? "作曲" : "作詞"
        return .credit("\(label)：\(match.2)")
    }
}
