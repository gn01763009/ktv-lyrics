@testable import KTVCore
import Foundation
import Testing

@Suite struct StorageTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400
    private let lyrics = Lyrics(
        source: .lrclib,
        lines: [LyricLine(start: 1, end: 3, holdEnd: 3, text: "溫柔")],
        credits: []
    )
    private var query: TrackQuery {
        TrackQuery(title: "溫柔", artist: "五月天", duration: 270.2)
    }

    /// Runs `body` in a fresh directory that does not exist yet, and removes whatever it left behind.
    private func withTempDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    @Test func foundIsCachedForever() throws {
        try withTempDirectory { dir in
            try LyricsCache(directory: dir, now: { start }).save(.found(lyrics), for: query)
            let later = LyricsCache(directory: dir, now: { start.addingTimeInterval(365 * day) })
            #expect(later.load(query) == .found(lyrics))
        }
    }

    @Test func incompleteOutcomesAreNotStored() throws {
        try withTempDirectory { dir in
            let cache = LyricsCache(directory: dir, now: { start })
            try cache.save(.unavailable, for: query)
            try cache.save(.foundPartial(lyrics), for: query)
            #expect(cache.load(query) == nil)
            #expect(!FileManager.default.fileExists(atPath: dir.path))
        }
    }

    @Test func notFoundExpiresAfterADay() throws {
        try withTempDirectory { dir in
            try LyricsCache(directory: dir, now: { start }).save(.notFound, for: query)
            let at23Hours = LyricsCache(directory: dir, now: { start.addingTimeInterval(23 * hour) })
            let at25Hours = LyricsCache(directory: dir, now: { start.addingTimeInterval(25 * hour) })
            #expect(at23Hours.load(query) == .notFound)
            #expect(at25Hours.load(query) == nil)
        }
    }

    @Test func keyIgnoresScriptAndRoundsDuration() throws {
        try withTempDirectory { dir in
            let saved = TrackQuery(title: "溫柔", artist: "五月天", duration: 270.2)
            let looked = TrackQuery(title: "温柔", artist: "五月天", duration: 269.8)
            try LyricsCache(directory: dir, now: { start }).save(.found(lyrics), for: saved)
            #expect(LyricsCache(directory: dir, now: { start }).load(looked) == .found(lyrics))
        }
    }

    @Test func corruptFileReadsAsMissing() throws {
        try withTempDirectory { dir in
            let cache = LyricsCache(directory: dir, now: { start })
            try cache.save(.found(lyrics), for: query)
            for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                try Data("not json {".utf8).write(to: file)
            }
            #expect(cache.load(query) == nil)
            #expect(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).isEmpty)
        }
    }

    @Test func overrideDefaultsToNone() {
        withTempDirectory { dir in
            #expect(SongOverrideStore(directory: dir).load(query) == .none)
        }
    }

    @Test func overrideRoundTrips() throws {
        try withTempDirectory { dir in
            let store = SongOverrideStore(directory: dir)
            let override = SongOverride(offset: 0.3, importedLRC: nil, candidateID: "x")
            try store.save(override, for: query)
            #expect(store.load(query) == override)
        }
    }

    @Test func staleLookupIsIgnored() {
        let first = LookupGate().next()
        let second = first.next()
        #expect(!second.accepts(first.currentID))
        #expect(second.accepts(second.currentID))
    }
}
