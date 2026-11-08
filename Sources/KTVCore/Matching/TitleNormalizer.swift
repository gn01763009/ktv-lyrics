import Foundation

/// What to search lyrics for: the song title, its first-listed artist (if known), and its length in seconds.
public struct TrackQuery: Equatable, Codable, Sendable {
    public let title: String
    public let artist: String?
    public let duration: Double

    public init(title: String, artist: String?, duration: Double) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// Players whose now-playing title comes from a browser tab, so it needs YouTube-style parsing.
public enum BrowserApps {
    private static let bundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox",
    ]

    public static func contains(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }
}

/// Turns raw titles and artist names into keys that compare equal across subtitles, scripts and punctuation.
public enum TitleNormalizer {
    /// Text from the first of these markers onward is dropped when cleaning a title.
    private static let cutMarkers = [" - ", "（", "(", "【", "[", " feat"]
    /// Separators that split several artists; only the first artist is kept.
    private static let artistSeparators = [",", "、", "&", "/", " feat"]
    /// Characters ignored when comparing text.
    private static let ignoredCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    /// Removes subtitles and version tags such as ` - 片尾曲`, `(Remastered)` or ` feat. X`.
    /// If nothing is left, the trimmed input is returned so the title still has a usable value.
    public static func clean(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = cutMarkers.reduce(trimmed) { current, marker in
            current.components(separatedBy: marker).first ?? current
        }
        let cleaned = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? trimmed : cleaned
    }

    /// A comparison key: Traditional Chinese, lowercased, with spaces and punctuation removed.
    /// Falls back to the lowercased input when stripping removes everything.
    public static func matchKey(_ text: String) -> String {
        let converted = TextConversion.toTraditional(text).lowercased()
        let stripped = String(converted.unicodeScalars.filter { !ignoredCharacters.contains($0) })
        return stripped.isEmpty ? text.lowercased() : stripped
    }

    /// The comparison key of the first-listed artist, e.g. `周杰伦、五月天` gives the key for `周杰伦`.
    public static func artistKey(_ artist: String) -> String {
        let first = artistSeparators.reduce(artist) { current, separator in
            current.components(separatedBy: separator).first ?? current
        }
        return matchKey(first)
    }

    /// The lyrics query for what the system reports as playing.
    /// Browser tabs are parsed as YouTube titles, using the page's channel name as the artist.
    public static func query(from snapshot: PlaybackSnapshot) -> TrackQuery {
        if BrowserApps.contains(snapshot.bundleID) {
            let parsed = YouTubeTitleParser.parse(title: snapshot.title, channel: snapshot.artist)
            return TrackQuery(title: parsed.title, artist: parsed.artist, duration: snapshot.duration)
        }
        return TrackQuery(title: clean(snapshot.title), artist: snapshot.artist, duration: snapshot.duration)
    }
}
