import Foundation

/// Reads a song title and artist out of a YouTube-style browser tab title and its channel name.
public enum YouTubeTitleParser {
    private static let topicSuffix = " - Topic"
    private static let dashSeparator = " - "
    /// Bracket pairs whose inner text names the song, checked in this order.
    private static let bracketPairs: [(open: String, close: String)] = [("【", "】"), ("《", "》")]
    /// Bracket text containing any of these (lowercased) is a version tag such as `Official MV`, not a song name.
    private static let genericBracketTags = ["official", "mv", "live", "lyric", "hd", "4k", "官方", "ktv", "完整版"]

    /// Splits a tab title into `(title, artist)`. Each rule is tried in order and the first that applies wins:
    /// 1. A `Channel - Topic` channel is an auto-generated artist channel: the title is the song.
    /// 2. A title with `【…】` or `《…》` naming a song inside the brackets (not a generic tag, and not after ` - `).
    /// 3. A title with ` - ` is `artist - song`, unless its right side is the channel, then the sides swap.
    /// 4. Otherwise the cleaned title is the song and the channel is the artist.
    public static func parse(title: String, channel: String?) -> (title: String, artist: String?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let channelName = nonEmpty(channel)

        if let channelName, channelName.hasSuffix(topicSuffix) {
            let artist = String(channelName.dropLast(topicSuffix.count))
            return (TitleNormalizer.clean(trimmedTitle), nonEmpty(artist))
        }
        if let bracketed = bracketedTitle(in: trimmedTitle) {
            return (bracketed.title, nonEmpty(bracketed.artist) ?? channelName)
        }
        if let dash = trimmedTitle.range(of: dashSeparator) {
            let left = String(trimmedTitle[..<dash.lowerBound])
            let right = String(trimmedTitle[dash.upperBound...])
            if let channelName, TitleNormalizer.clean(right) == channelName {
                return (TitleNormalizer.clean(left), channelName)
            }
            return (TitleNormalizer.clean(right), nonEmpty(left))
        }
        return (TitleNormalizer.clean(trimmedTitle), channelName)
    }

    /// The first bracket pair that names a song: its first word is the title, and the cleaned text before it is the artist.
    /// A pair is skipped when the text before it contains ` - ` (the dash rule handles that) or when its text is a generic tag.
    private static func bracketedTitle(in text: String) -> (artist: String, title: String)? {
        for pair in bracketPairs {
            guard let open = text.range(of: pair.open),
                  let close = text.range(of: pair.close, range: open.upperBound..<text.endIndex) else {
                continue
            }
            let before = String(text[..<open.lowerBound])
            let inner = String(text[open.upperBound..<close.lowerBound])
            guard let firstWord = inner.split(whereSeparator: \.isWhitespace).first,
                  !before.contains(dashSeparator),
                  !isGenericTag(inner) else {
                continue
            }
            return (TitleNormalizer.clean(before), String(firstWord))
        }
        return nil
    }

    private static func isGenericTag(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return genericBracketTags.contains { lowered.contains($0) }
    }

    /// The text trimmed of surrounding whitespace, or nil when nothing is left.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
