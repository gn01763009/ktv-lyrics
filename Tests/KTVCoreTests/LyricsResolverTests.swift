import Foundation
@testable import KTVCore
import Testing

@Suite struct LyricsResolverTests {
    let q = TrackQuery(title: "溫柔", artist: "五月天", duration: 270)

    func resolver(lrclib: LRCLIBScenario = .standard, netease: NetEaseScenario = .wordTimed(offset: 0)) -> LyricsResolver {
        makeResolver(FakeHTTP(routes: FakeHTTP.routes(lrclib: lrclib, netease: netease)))
    }

    func makeResolver(_ http: FakeHTTP, netease: Bool = true) -> LyricsResolver {
        LyricsResolver(lrclib: LRCLIBClient(http: http), netease: netease ? NetEaseClient(http: http) : nil)
    }

    /// Lines that start at the given times. Only the start matters to the validator.
    func lines(at starts: [Double]) -> [LyricLine] {
        starts.map { LyricLine(start: $0, end: $0 + 1, holdEnd: $0 + 1, text: "字") }
    }

    @Test func wordTimedWins() async {
        let o = await resolver(netease: .wordTimed(offset: 0)).resolve(q)
        #expect(o.lyrics?.source == .netease && o.lyrics?.isWordTimed == true && o.lyrics?.credits == ["作詞：五月天 阿信"])
    }

    @Test func versionMismatchFallsBackToLines() async {
        let o = await resolver(netease: .wordTimed(offset: 2)).resolve(q)
        #expect(o.lyrics?.source == .lrclib && o.lyrics?.isWordTimed == false && o.lyrics?.credits == ["作詞：五月天 阿信"])
    }

    @Test func lrclibLinesWhenNoWordTiming() async {
        #expect(await resolver(netease: .noYRC).resolve(q).lyrics?.source == .lrclib)
    }

    @Test func neteaseLinesWhenLrclibMisses() async {
        let o = await resolver(lrclib: .empty, netease: .noYRC).resolve(q)
        #expect(o.lyrics?.source == .netease && o.lyrics?.isWordTimed == false)
    }

    @Test func disabledNeteaseIsNeverCalled() async {
        let h = FakeHTTP.standard
        _ = await makeResolver(h, netease: false).resolve(q)
        #expect(!h.hosts.contains("music.163.com"))
    }

    @Test func neteaseFailureFallsBack() async {
        #expect(await resolver(netease: .failing).resolve(q).lyrics?.source == .lrclib)
    }

    @Test func nothingMatchesIsNotFound() async {
        #expect(await resolver(lrclib: .otherSong, netease: .otherSong).resolve(q) == .notFound)
    }

    @Test func malformedResponsesAreNotFound() async {
        #expect(await resolver(lrclib: .garbage, netease: .garbage).resolve(q) == .notFound)
    }

    @Test func validatorComparesMedianLineStart() {
        #expect(WordTimingValidator.isSameVersion(words: lines(at: [10, 20, 30]), lines: lines(at: [10.9, 20.9, 30.9])))
        #expect(!WordTimingValidator.isSameVersion(words: lines(at: [10, 20, 30]), lines: lines(at: [11.1, 21.1, 31.1])))
    }

    @Test func validatorPassesWithTooFewLines() {
        #expect(WordTimingValidator.isSameVersion(words: lines(at: [10]), lines: lines(at: [90])))
    }

    @Test func candidatesListEveryAcceptedVersion() async {
        let found = await resolver().candidates(q)
        #expect(found.map(\.id) == ["lrclib:\(StableHash.fnv1a(syncedLRC))", "netease-word:9", "netease-line:9"])
        #expect(found.map(\.label) == ["LRCLIB · 整行", "網易雲 · 逐字", "網易雲 · 整行"])
    }

    @Test func candidatesOmitMismatchedWordVersion() async {
        let found = await resolver(netease: .wordTimed(offset: 2)).candidates(q)
        #expect(found.map(\.id) == ["lrclib:\(StableHash.fnv1a(syncedLRC))", "netease-line:9"])
    }

    @Test func neteaseTextIsConvertedToTraditional() async {
        let o = await resolver(lrclib: .empty, netease: .noYRC).resolve(q)
        #expect(o.lyrics?.lines.first?.text == "這是第一句")
    }

    @Test func lrcOwnCreditsBeatNeteaseCredits() async {
        let o = await resolver(lrclib: .withCredit, netease: .wordTimed(offset: 0)).resolve(q)
        #expect(o.lyrics?.credits == ["作詞：某人"])
    }

    @Test func lrclibFallsBackToFreeTextQuery() async {
        let http = FakeHTTP(routes: FakeHTTP.routes(lrclib: .freeTextOnly, netease: .failing))
        let o = await makeResolver(http).resolve(q)
        #expect(o.lyrics?.source == .lrclib)
        #expect(http.urls.filter { $0.host == "lrclib.net" }.count == 2)
    }

    @Test func withoutArtistOnlyTitleQueryRuns() async {
        let http = FakeHTTP(routes: FakeHTTP.routes(lrclib: .standard, netease: .failing))
        let title = TrackQuery(title: "溫柔", artist: nil, duration: 270)
        let o = await makeResolver(http, netease: false).resolve(title)
        #expect(o.lyrics?.source == .lrclib)
        #expect(http.urls.count == 1)
        #expect(http.urls.first?.absoluteString.contains("artist_name") == false)
    }

    @Test func lrclibIgnoresHitsWithoutSyncedLyrics() async throws {
        let http = FakeHTTP(routes: FakeHTTP.routes(lrclib: .unsynced, netease: .noYRC))
        let hits = try await LRCLIBClient(http: http).search(q)
        #expect(hits.isEmpty)
    }

    @Test func neteaseSearchReadsSongs() async throws {
        let http = FakeHTTP(routes: FakeHTTP.routes(lrclib: .standard, netease: .wordTimed(offset: 0)))
        let songs = try await NetEaseClient(http: http).search(q)
        #expect(songs == [NetEaseSong(id: 9, title: "溫柔", artist: "五月天", duration: 270)])
    }

    @Test func neteaseEmptyLyricFieldsAreAbsent() async throws {
        let body = Data(#"{"lrc":{"lyric":""},"yrc":{"lyric":""}}"#.utf8)
        let http = FakeHTTP(routes: ["music.163.com/api/song/lyric": .success(body)])
        let lyrics = try await NetEaseClient(http: http).lyrics(id: 9)
        #expect(lyrics == NetEaseLyrics(lrc: nil, yrc: nil))
    }
}
