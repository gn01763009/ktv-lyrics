import Foundation
import KTVCore
import os

/// Finds the lyrics for one track: the user's imported text first, then their chosen version,
/// then the cache, then a fresh lookup that is saved to the cache.
struct LyricsLocator: Sendable {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "LyricsLocator")

    let cache: LyricsCache

    /// With `usesCache` false the cache is neither read nor written. Used when the query is not trustworthy,
    /// for example a track whose duration is still unknown.
    func locate(
        _ query: TrackQuery,
        override: SongOverride,
        resolver: any LyricsResolving,
        usesCache: Bool = true
    ) async -> LyricsOutcome {
        if let imported = importedLyrics(override) { return .found(imported) }
        if let chosen = await chosenCandidate(query, override: override, resolver: resolver) {
            return .found(chosen)
        }
        if usesCache, let cached = cache.load(query) { return cached }
        let outcome = await resolver.resolve(query)
        if usesCache { save(outcome, for: query) }
        return outcome
    }

    /// The imported LRC as lyrics. Text with no usable lines is logged and ignored.
    private func importedLyrics(_ override: SongOverride) -> Lyrics? {
        guard let text = override.importedLRC else { return nil }
        let parsed = LRCParser.parse(text)
        let lines = LyricsBuilder.lines(from: parsed)
        guard !lines.isEmpty else {
            Self.logger.error("Imported LRC has no usable lines; looking the song up instead")
            return nil
        }
        return Lyrics(source: .imported, lines: lines, credits: parsed.credits)
    }

    /// The version the user picked, or nil when none is stored or that version is no longer offered.
    private func chosenCandidate(_ query: TrackQuery, override: SongOverride, resolver: any LyricsResolving) async -> Lyrics? {
        guard let id = override.candidateID else { return nil }
        let match = await resolver.candidates(query).first { $0.id == id }
        if match == nil { Self.logger.notice("Chosen lyrics version \(id, privacy: .public) is gone; using the default") }
        return match?.lyrics
    }

    private func save(_ outcome: LyricsOutcome, for query: TrackQuery) {
        do {
            try cache.save(outcome, for: query)
        } catch {
            Self.logger.error("Could not cache lyrics: \(error.localizedDescription, privacy: .public)")
        }
    }
}
