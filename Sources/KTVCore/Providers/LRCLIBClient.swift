import Foundation

/// A LRCLIB search hit that has synced lyrics.
public struct LRCLIBHit: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let duration: Double
    public let syncedLyrics: String

    public init(title: String, artist: String?, duration: Double, syncedLyrics: String) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.syncedLyrics = syncedLyrics
    }
}

extension LRCLIBHit {
    var matchCandidate: MatchCandidate {
        MatchCandidate(title: title, artist: artist, duration: duration)
    }
}

/// Searches LRCLIB (https://lrclib.net) for synced lyrics. The API is free and needs no key.
public struct LRCLIBClient: Sendable {
    private static let searchURL = "https://lrclib.net/api/search"

    private let http: any HTTPFetching

    public init(http: any HTTPFetching) {
        self.http = http
    }

    /// Runs the queries in order and returns the accepted hits of the first query that has one.
    /// Hits without synced lyrics are ignored. Without an artist, only the title query runs.
    public func search(_ query: TrackQuery) async throws -> [LRCLIBHit] {
        for pairs in Self.queries(for: query) {
            let accepted = try await hits(pairs).filter { TrackMatcher.accepts($0.matchCandidate, for: query) }
            if !accepted.isEmpty { return accepted }
        }
        return []
    }

    /// The three queries in order. The first two need an artist, so they are skipped when there is none.
    private static func queries(for query: TrackQuery) -> [KeyValuePairs<String, String>] {
        guard let artist = query.artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty else {
            return [["q": query.title]]
        }
        return [
            ["track_name": query.title, "artist_name": artist],
            ["q": "\(query.title) \(artist)"],
            ["q": query.title],
        ]
    }

    private func hits(_ pairs: KeyValuePairs<String, String>) async throws -> [LRCLIBHit] {
        let url = try URL.endpoint(Self.searchURL, query: pairs)
        let data = try await http.data(from: url)
        return try JSONDecoder().decode([Row].self, from: data).compactMap(\.hit)
    }

    /// One row of the search array. Fields are optional because the API sends null for missing values.
    private struct Row: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let syncedLyrics: String?

        var hit: LRCLIBHit? {
            guard let title = trackName, let duration, let lyrics = syncedLyrics, !lyrics.isEmpty else { return nil }
            return LRCLIBHit(title: title, artist: artistName, duration: duration, syncedLyrics: lyrics)
        }
    }
}
