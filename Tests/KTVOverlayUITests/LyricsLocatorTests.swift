import Foundation
import KTVCore
@testable import KTVOverlayUI
import Testing

@Suite struct LyricsLocatorTests {
    /// Answers every request with a connection error until `online` is set, then serves one LRCLIB hit.
    private final class SwitchableHTTP: HTTPFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var isOnline = false
        private var count = 0

        var online: Bool {
            get { lock.withLock { isOnline } }
            set { lock.withLock { isOnline = newValue } }
        }

        var requests: Int { lock.withLock { count } }

        func data(from url: URL) async throws -> Data {
            lock.withLock { count += 1 }
            guard online else { throw URLError(.notConnectedToInternet) }
            if url.host == "lrclib.net" { return Self.lrclibBody }
            return Data(#"{"result":{"songs":[]}}"#.utf8)
        }

        static let lrclibBody = Data("""
        [{"trackName":"溫柔","artistName":"五月天","duration":270,"syncedLyrics":"[00:10.00]第一句\\n[00:20.00]第二句"}]
        """.utf8)
    }

    private let query = TrackQuery(title: "溫柔", artist: "五月天", duration: 270)

    private func withDirectory<T>(_ body: (URL) async throws -> T) async rethrows -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ktv-locator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    @Test func networkFailureIsNeverCachedAndTheNextLookupRecovers() async {
        await withDirectory { directory in
            let http = SwitchableHTTP()
            let cache = LyricsCache(directory: directory)
            let locator = LyricsLocator(cache: cache)
            let resolver = LyricsResolver(lrclib: LRCLIBClient(http: http), netease: NetEaseClient(http: http))

            let offline = await locator.locate(query, override: .none, resolver: resolver)
            #expect(offline == .unavailable)
            #expect(cache.load(query) == nil)
            #expect(!FileManager.default.fileExists(atPath: directory.path))

            http.online = true
            let online = await locator.locate(query, override: .none, resolver: resolver)
            guard case .found(let lyrics) = online else {
                Issue.record("expected .found after the network returned, got \(online)")
                return
            }
            #expect(lyrics.source == .lrclib && lyrics.lines.count == 2)
            #expect(cache.load(query) == online)
        }
    }

    @Test func partialOutcomeIsNotCached() async {
        await withDirectory { directory in
            let http = SwitchableHTTP()
            http.online = true
            let cache = LyricsCache(directory: directory)
            let failingNetEase = LyricsResolver(lrclib: LRCLIBClient(http: http), netease: NetEaseClient(http: FailingHTTP()))
            let outcome = await LyricsLocator(cache: cache).locate(query, override: .none, resolver: failingNetEase)
            guard case .foundPartial = outcome else {
                Issue.record("expected .foundPartial, got \(outcome)")
                return
            }
            #expect(cache.load(query) == nil)
        }
    }

    private struct FailingHTTP: HTTPFetching {
        func data(from url: URL) async throws -> Data { throw URLError(.timedOut) }
    }
}
