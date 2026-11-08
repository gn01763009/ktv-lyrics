import Foundation

/// A NetEase search result. `duration` is in seconds.
public struct NetEaseSong: Equatable, Sendable {
    public let id: Int
    public let title: String
    public let artist: String?
    public let duration: Double

    public init(id: Int, title: String, artist: String?, duration: Double) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

extension NetEaseSong {
    var matchCandidate: MatchCandidate {
        MatchCandidate(title: title, artist: artist, duration: duration)
    }
}

/// The lyric fields of a NetEase lyric response. Empty fields are stored as nil.
public struct NetEaseLyrics: Equatable, Sendable {
    public let lrc: String?
    public let yrc: String?

    public init(lrc: String?, yrc: String?) {
        self.lrc = lrc
        self.yrc = yrc
    }
}

/// Searches NetEase Cloud Music (music.163.com). This is an unofficial interface and may stop working at any time.
public struct NetEaseClient: Sendable {
    private static let searchURL = "https://music.163.com/api/search/get"
    private static let lyricURL = "https://music.163.com/api/song/lyric/v1"
    private static let searchLimit = "8"
    private static let millisecondsPerSecond: Double = 1000

    private let http: any HTTPFetching

    public init(http: any HTTPFetching) {
        self.http = http
    }

    /// Songs matching the title and artist, in the order NetEase returns them.
    public func search(_ query: TrackQuery) async throws -> [NetEaseSong] {
        let text = [query.title, query.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let url = try URL.endpoint(Self.searchURL, query: ["s": text, "type": "1", "limit": Self.searchLimit])
        let data = try await http.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (response.result?.songs ?? []).compactMap(\.song)
    }

    public func lyrics(id: Int) async throws -> NetEaseLyrics {
        let url = try URL.endpoint(Self.lyricURL, query: [
            "id": String(id), "cp": "false", "tv": "0", "lv": "0", "rv": "0",
            "kv": "0", "yv": "0", "ytv": "0", "yrv": "0",
        ])
        let data = try await http.data(from: url)
        let response = try JSONDecoder().decode(LyricResponse.self, from: data)
        return NetEaseLyrics(lrc: Self.nonEmpty(response.lrc?.lyric), yrc: Self.nonEmpty(response.yrc?.lyric))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private struct SearchResponse: Decodable {
        let result: Body?

        struct Body: Decodable {
            let songs: [SongRow]?
        }

        struct SongRow: Decodable {
            let id: Int?
            let name: String?
            let artists: [Artist]?
            let duration: Double?

            /// Nil when the id, name or duration is missing.
            var song: NetEaseSong? {
                guard let id, let name, let duration else { return nil }
                return NetEaseSong(
                    id: id,
                    title: name,
                    artist: artists?.first?.name,
                    duration: duration / millisecondsPerSecond
                )
            }
        }

        struct Artist: Decodable {
            let name: String?
        }
    }

    private struct LyricResponse: Decodable {
        let lrc: Field?
        let yrc: Field?

        struct Field: Decodable {
            let lyric: String?
        }
    }
}
