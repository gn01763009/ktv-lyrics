import Foundation
import os

/// The user's per-song adjustments: a timing offset, an imported LRC text, and the chosen candidate.
public struct SongOverride: Equatable, Codable, Sendable {
    public let offset: Double
    public let importedLRC: String?
    public let candidateID: String?

    public init(offset: Double, importedLRC: String?, candidateID: String?) {
        self.offset = offset
        self.importedLRC = importedLRC
        self.candidateID = candidateID
    }

    /// No adjustments: zero offset, no imported text, no chosen candidate.
    public static let none = SongOverride(offset: 0, importedLRC: nil, candidateID: nil)
}

/// Saves and loads one `SongOverride` per track, as JSON files in its own directory.
public struct SongOverrideStore: Sendable {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "SongOverrideStore")

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The stored override, or `.none` when the track has none or its file cannot be read.
    /// An unreadable file is kept, since it holds user data, and the failure is logged.
    public func load(_ query: TrackQuery) -> SongOverride {
        let url = fileURL(for: query)
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SongOverride.self, from: data)
        } catch {
            Self.logger.error("Ignoring unreadable song override \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .none
        }
    }

    /// Stores the override, creating the directory on first use.
    public func save(_ songOverride: SongOverride, for query: TrackQuery) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(songOverride)
        try data.write(to: fileURL(for: query), options: .atomic)
    }

    private func fileURL(for query: TrackQuery) -> URL {
        directory.appendingPathComponent(TrackFileKey.fileName(for: query))
    }
}
