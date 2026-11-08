import Foundation

/// One lyrics search result, reduced to the fields used for matching.
public struct MatchCandidate: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let duration: Double

    public init(title: String, artist: String?, duration: Double) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// Decides whether a lyrics candidate is the song being played.
public enum TrackMatcher {
    /// Accepts a candidate when its cleaned title matches and its duration is within the window.
    /// The window is wider when both artists are known and agree, and narrower otherwise.
    public static func accepts(_ candidate: MatchCandidate, for query: TrackQuery) -> Bool {
        guard titlesMatch(candidate.title, query.title) else { return false }
        return durationGap(candidate, query) <= window(candidate, query)
    }

    /// The accepted candidate whose duration is closest to the query, or nil when none is accepted.
    public static func best<T>(_ items: [T], for query: TrackQuery, candidate: (T) -> MatchCandidate) -> T? {
        items
            .map { (item: $0, match: candidate($0)) }
            .filter { accepts($0.match, for: query) }
            .min { durationGap($0.match, query) < durationGap($1.match, query) }?
            .item
    }

    private static func titlesMatch(_ candidate: String, _ query: String) -> Bool {
        TitleNormalizer.matchKey(TitleNormalizer.clean(candidate)) == TitleNormalizer.matchKey(TitleNormalizer.clean(query))
    }

    private static func window(_ candidate: MatchCandidate, _ query: TrackQuery) -> Double {
        sameArtist(candidate.artist, query.artist) ? LyricsTiming.matchSameArtistSeconds : LyricsTiming.matchOtherArtistSeconds
    }

    private static func durationGap(_ candidate: MatchCandidate, _ query: TrackQuery) -> Double {
        abs(candidate.duration - query.duration)
    }

    /// True when both artists are known and one first-artist key contains the other.
    private static func sameArtist(_ candidate: String?, _ query: String?) -> Bool {
        guard let candidate, let query else { return false }
        let candidateKey = TitleNormalizer.artistKey(candidate)
        let queryKey = TitleNormalizer.artistKey(query)
        guard !candidateKey.isEmpty, !queryKey.isEmpty else { return false }
        return candidateKey.contains(queryKey) || queryKey.contains(candidateKey)
    }
}
