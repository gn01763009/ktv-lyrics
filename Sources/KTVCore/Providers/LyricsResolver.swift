import Foundation
import os

/// The result of a lyrics lookup. `resolve` never fails: a track with no usable lyrics is `.notFound`.
public enum LyricsOutcome: Equatable, Codable, Sendable {
    case found(Lyrics)
    case notFound

    public var lyrics: Lyrics? {
        switch self {
        case .found(let lyrics):
            return lyrics
        case .notFound:
            return nil
        }
    }
}

/// One lyrics version the user can pick. `id` is stable across lookups of the same version.
public struct LyricsCandidate: Equatable, Sendable {
    public let id: String
    public let label: String
    public let lyrics: Lyrics

    public init(id: String, label: String, lyrics: Lyrics) {
        self.id = id
        self.label = label
        self.lyrics = lyrics
    }
}

public protocol LyricsResolving: Sendable {
    /// The preferred version: word-timed NetEase, then LRCLIB lines, then NetEase lines.
    func resolve(_ query: TrackQuery) async -> LyricsOutcome
    /// Every version that passes the matching rules, in the order LRCLIB, NetEase word-timed, NetEase lines.
    func candidates(_ query: TrackQuery) async -> [LyricsCandidate]
}

/// Looks up LRCLIB and NetEase, and chooses which version to show.
public struct LyricsResolver: LyricsResolving {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "LyricsResolver")

    private let lrclib: LRCLIBClient
    /// Nil when the user has turned NetEase off, in which case it is never called.
    private let netease: NetEaseClient?

    public init(lrclib: LRCLIBClient, netease: NetEaseClient?) {
        self.lrclib = lrclib
        self.netease = netease
    }

    public func resolve(_ query: TrackQuery) async -> LyricsOutcome {
        let versions = await loadVersions(query)
        guard let chosen = versions.neteaseWord ?? versions.bestLRCLIB ?? versions.neteaseLines else {
            return .notFound
        }
        return .found(chosen.lyrics)
    }

    public func candidates(_ query: TrackQuery) async -> [LyricsCandidate] {
        let versions = await loadVersions(query)
        return versions.lrclib + [versions.neteaseWord, versions.neteaseLines].compactMap { $0 }
    }

    private func loadVersions(_ query: TrackQuery) async -> Versions {
        Self.versions(from: await fetchAll(query), for: query)
    }

    // MARK: - Fetching

    /// What the two providers returned for one track. Each part is nil or empty when that provider failed.
    private struct Fetched {
        let lrclibHits: [LRCLIBHit]
        let netease: NetEaseMatch?
    }

    /// The NetEase song that best matches the track, with its lyric fields.
    private struct NetEaseMatch {
        let song: NetEaseSong
        let lyrics: NetEaseLyrics
    }

    private func fetchAll(_ query: TrackQuery) async -> Fetched {
        async let hits = searchLRCLIB(query)
        async let match = searchNetEase(query)
        return Fetched(lrclibHits: await hits, netease: await match)
    }

    private func searchLRCLIB(_ query: TrackQuery) async -> [LRCLIBHit] {
        await Self.attempt("LRCLIB search") { try await self.lrclib.search(query) } ?? []
    }

    private func searchNetEase(_ query: TrackQuery) async -> NetEaseMatch? {
        guard let client = netease else { return nil }
        let songs = await Self.attempt("NetEase search") { try await client.search(query) } ?? []
        guard let song = TrackMatcher.best(songs, for: query, candidate: { $0.matchCandidate }) else { return nil }
        guard let lyrics = await Self.attempt("NetEase lyrics", { try await client.lyrics(id: song.id) }) else {
            return nil
        }
        return NetEaseMatch(song: song, lyrics: lyrics)
    }

    /// Runs one provider call. A thrown error is logged and becomes nil, so the other provider still counts.
    private static func attempt<T>(_ provider: String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            logger.error("\(provider, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Versions

    /// Every version built from one fetch. `bestLRCLIB` is the hit whose duration is closest to the track.
    private struct Versions {
        let lrclib: [LyricsCandidate]
        let bestLRCLIB: LyricsCandidate?
        let neteaseWord: LyricsCandidate?
        let neteaseLines: LyricsCandidate?
    }

    private static func versions(from fetched: Fetched, for query: TrackQuery) -> Versions {
        let best = TrackMatcher.best(fetched.lrclibHits, for: query, candidate: { $0.matchCandidate })
        let credits = trackCredits(ownLRC: best, netease: fetched.netease?.lyrics)
        let bestLines = best.map(lrclibLines) ?? []
        return Versions(
            lrclib: fetched.lrclibHits.compactMap { lrclibCandidate($0, credits: credits) },
            bestLRCLIB: best.flatMap { lrclibCandidate($0, credits: credits) },
            neteaseWord: fetched.netease.flatMap { wordCandidate($0, credits: credits, comparedTo: bestLines) },
            neteaseLines: fetched.netease.flatMap { lineCandidate($0, credits: credits) }
        )
    }

    /// The LRC's own credits win. Otherwise NetEase's header credits are used. One list covers every version.
    private static func trackCredits(ownLRC: LRCLIBHit?, netease: NetEaseLyrics?) -> [String] {
        let own = ownLRC.map { LRCParser.parse($0.syncedLyrics).credits } ?? []
        return own.isEmpty ? neteaseCredits(netease) : own
    }

    /// Credits from NetEase's yrc header, or from its lrc header when yrc has none. Converted to Traditional.
    private static func neteaseCredits(_ lyrics: NetEaseLyrics?) -> [String] {
        guard let lyrics else { return [] }
        let headers = [lyrics.yrc, lyrics.lrc].compactMap { $0 }.map(YRCParser.headerCredits)
        return (headers.first { !$0.isEmpty } ?? []).map(TextConversion.toTraditional)
    }

    private static func lrclibLines(_ hit: LRCLIBHit) -> [LyricLine] {
        LyricsBuilder.lines(from: LRCParser.parse(hit.syncedLyrics))
    }

    private static func lrclibCandidate(_ hit: LRCLIBHit, credits: [String]) -> LyricsCandidate? {
        let lines = lrclibLines(hit)
        guard !lines.isEmpty else { return nil }
        return LyricsCandidate(
            id: "lrclib:\(StableHash.fnv1a(hit.syncedLyrics))",
            label: "LRCLIB · 整行",
            lyrics: Lyrics(source: .lrclib, lines: lines, credits: credits)
        )
    }

    /// Word timing is offered when it parses and, if LRCLIB has a hit, its line starts agree with that hit.
    private static func wordCandidate(
        _ match: NetEaseMatch,
        credits: [String],
        comparedTo bestLines: [LyricLine]
    ) -> LyricsCandidate? {
        guard let yrc = match.lyrics.yrc else { return nil }
        let lines = YRCParser.parse(yrc, convert: TextConversion.toTraditional).lines
        guard !lines.isEmpty, WordTimingValidator.isSameVersion(words: lines, lines: bestLines) else { return nil }
        return LyricsCandidate(
            id: "netease-word:\(match.song.id)",
            label: "網易雲 · 逐字",
            lyrics: Lyrics(source: .netease, lines: lines, credits: credits)
        )
    }

    private static func lineCandidate(_ match: NetEaseMatch, credits: [String]) -> LyricsCandidate? {
        guard let lrc = match.lyrics.lrc else { return nil }
        let lines = LyricsBuilder.lines(from: LRCParser.parse(TextConversion.toTraditional(lrc)))
        guard !lines.isEmpty else { return nil }
        return LyricsCandidate(
            id: "netease-line:\(match.song.id)",
            label: "網易雲 · 整行",
            lyrics: Lyrics(source: .netease, lines: lines, credits: credits)
        )
    }
}
