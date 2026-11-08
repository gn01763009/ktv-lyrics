import Foundation

/// Lyrics parsed from word-timed (YRC) text, plus credits found in its JSON header rows.
public struct ParsedYRC: Equatable, Sendable {
    public let lines: [LyricLine]
    public let credits: [String]

    public init(lines: [LyricLine], credits: [String]) {
        self.lines = lines
        self.credits = credits
    }
}

/// Parses word-timed (YRC) lyrics such as `[行ms,長ms](字ms,長ms,0)字`.
/// Parsing is pure and tolerant: malformed rows are skipped, never fatal.
public enum YRCParser {
    private static let millisecondsPerSecond: Double = 1000

    /// A line header `[行ms,長ms]`. Only the start of the line is used, from its first word.
    private static let linePattern = #/\[\d+,\d+\]/#
    /// A word tag `(字ms,長ms,0)`. Group 1 is the word start, group 2 its duration.
    private static let wordPattern = #/\((\d+),(\d+),\d+\)/#
    private static let creditPattern = #/^(作词|作詞|作曲)\s*[:：]\s*(.+)$/#

    /// Parses word-timed lines and credits. `convert` is applied to each word token and to each credit.
    public static func parse(_ raw: String, convert: (String) -> String = { $0 }) -> ParsedYRC {
        let lines = raw.split(whereSeparator: \.isNewline).compactMap { line(from: $0, convert: convert) }
        let ordered = lines.sorted { $0.start < $1.start }
        let credits = headerCredits(raw).map(convert)
        return ParsedYRC(lines: LyricsBuilder.assigningSlots(ordered), credits: credits)
    }

    /// Reads `作词` / `作詞` / `作曲` credits from the JSON rows of a header.
    /// Each row is `{"t":ms,"c":[{"tx":"..."}, ...]}`; the `tx` values are concatenated before matching.
    public static func headerCredits(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isNewline).compactMap { creditLine(from: $0) }
    }

    private static func line(from row: Substring, convert: (String) -> String) -> LyricLine? {
        guard let header = row.prefixMatch(of: linePattern) else { return nil }
        let words = words(in: row[header.range.upperBound...], convert: convert)
        guard let first = words.first, let last = words.last else { return nil }
        let end = last.start + last.duration
        return LyricLine(
            start: first.start,
            end: end,
            holdEnd: end,
            text: words.map(\.text).joined(),
            words: words
        )
    }

    /// Each word runs from its tag to the next tag (or the end of the line). Empty tokens are dropped.
    private static func words(in body: Substring, convert: (String) -> String) -> [WordTiming] {
        let tags = body.matches(of: wordPattern)
        let tokenEnds = tags.dropFirst().map(\.range.lowerBound) + [body.endIndex]
        return zip(tags, tokenEnds).compactMap { tag, tokenEnd -> WordTiming? in
            let token = String(body[tag.range.upperBound..<tokenEnd])
            guard !token.isEmpty,
                  let start = seconds(fromMilliseconds: tag.output.1),
                  let duration = seconds(fromMilliseconds: tag.output.2) else { return nil }
            return WordTiming(text: convert(token), start: start, duration: duration)
        }
    }

    private static func seconds(fromMilliseconds digits: Substring) -> Double? {
        Double(digits).map { $0 / millisecondsPerSecond }
    }

    private static func creditLine(from row: Substring) -> String? {
        guard row.hasPrefix("{"),
              let data = String(row).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = object["c"] as? [[String: Any]] else { return nil }
        let text = segments.compactMap { $0["tx"] as? String }.joined()
        guard let match = text.firstMatch(of: creditPattern) else { return nil }
        let name = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let label = match.1.contains("曲") ? "作曲" : "作詞"
        return "\(label)：\(name)"
    }
}
