import CryptoKit
import Foundation
import os

/// The on-disk file name for a track, shared by every store in this directory layout.
enum TrackFileKey {
    /// The SHA-256 of `matchKey(title)|artistKey|rounded duration`, as a `.json` file name.
    /// A duration that cannot be represented as an Int is keyed as 0 rather than trapping.
    static func fileName(for query: TrackQuery) -> String {
        let artist = query.artist.map(TitleNormalizer.artistKey) ?? ""
        let seconds = Int(exactly: query.duration.rounded()) ?? 0
        let key = "\(TitleNormalizer.matchKey(query.title))|\(artist)|\(seconds)"
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }
}

/// Caches lookup outcomes per track. Found lyrics never expire; not-found results expire after `notFoundLifetime`.
public struct LyricsCache: Sendable {
    /// How long a not-found result is trusted before the track is looked up again.
    static let notFoundLifetime: TimeInterval = 24 * 60 * 60

    private static let logger = Logger(subsystem: "KTVLyrics", category: "LyricsCache")

    /// The JSON stored in each cache file.
    private struct Entry: Codable {
        let outcome: LyricsOutcome
        let savedAt: Date
    }

    private let directory: URL
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// A cache stored in the subdirectory `name`, so results found under different provider settings never mix.
    public func scoped(_ name: String) -> LyricsCache {
        LyricsCache(directory: directory.appendingPathComponent(name, isDirectory: true), now: now)
    }

    /// The cached outcome, or nil when nothing usable is stored. Unreadable files are deleted and logged.
    public func load(_ query: TrackQuery) -> LyricsOutcome? {
        let url = fileURL(for: query)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let entry = readEntry(at: url) else { return nil }
        switch entry.outcome {
        case .found:
            return entry.outcome
        case .notFound:
            let age = now().timeIntervalSince(entry.savedAt)
            return age < Self.notFoundLifetime ? entry.outcome : nil
        case .foundPartial, .unavailable:
            // Never written by the app, but an old or hand-edited file may hold one: ignore it.
            return nil
        }
    }

    /// Stores the outcome, creating the cache directory on first use.
    /// Outcomes that are not `isCacheable` (a provider failed) are skipped, so a network failure is never remembered.
    public func save(_ outcome: LyricsOutcome, for query: TrackQuery) throws {
        guard outcome.isCacheable else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Entry(outcome: outcome, savedAt: now()))
        try data.write(to: fileURL(for: query), options: .atomic)
    }

    private func fileURL(for query: TrackQuery) -> URL {
        directory.appendingPathComponent(TrackFileKey.fileName(for: query))
    }

    private func readEntry(at url: URL) -> Entry? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Entry.self, from: data)
        } catch {
            Self.logger.error("Discarding unreadable lyrics cache \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            removeFile(at: url)
            return nil
        }
    }

    private func removeFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Could not delete lyrics cache \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
