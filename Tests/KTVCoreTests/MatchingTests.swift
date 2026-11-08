@testable import KTVCore
import Testing

@Suite struct MatchingTests {
    let q = TrackQuery(title: "溫柔", artist: "五月天", duration: 270)

    func c(_ d: Double, title: String = "温柔", artist: String? = "五月天") -> MatchCandidate {
        MatchCandidate(title: title, artist: artist, duration: d)
    }

    @Test func cleansSubtitles() {
        #expect(TitleNormalizer.clean("想見你想見你想見你 - 電視劇《想見你》片尾曲") == "想見你想見你想見你")
        #expect(TitleNormalizer.clean("Bohemian Rhapsody (Remastered 2011)") == "Bohemian Rhapsody")
    }

    @Test func cleansBracketsAndFeaturing() {
        #expect(TitleNormalizer.clean("Song [Live]") == "Song")
        #expect(TitleNormalizer.clean("Song 【MV】") == "Song")
        #expect(TitleNormalizer.clean("Song feat. Someone") == "Song")
    }

    @Test func matchKeyUnifiesScripts() {
        #expect(TitleNormalizer.matchKey("温柔") == TitleNormalizer.matchKey("溫 柔"))
    }

    @Test func matchKeyIgnoresCaseAndPunctuation() {
        #expect(TitleNormalizer.matchKey("Hello, World!") == TitleNormalizer.matchKey("hello world"))
    }

    @Test func matchKeyFallsBackWhenNothingRemains() {
        #expect(TitleNormalizer.matchKey("♪♪") == "♪♪")
    }

    @Test func artistKeyUsesFirstArtist() {
        #expect(TitleNormalizer.artistKey("五月天 Mayday feat. Someone") == TitleNormalizer.matchKey("五月天 Mayday"))
        #expect(TitleNormalizer.artistKey("周杰伦、五月天") == TitleNormalizer.matchKey("周杰伦"))
        #expect(TitleNormalizer.artistKey("A & B") == TitleNormalizer.matchKey("A"))
        #expect(TitleNormalizer.artistKey("A/B,C") == TitleNormalizer.matchKey("A"))
    }

    @Test func durationWindowWithSameArtist() {
        #expect(TrackMatcher.accepts(c(272.9), for: q))
        #expect(!TrackMatcher.accepts(c(273.1), for: q))
    }

    @Test func stricterWhenArtistDiffers() {
        #expect(TrackMatcher.accepts(c(270.9, artist: "Mayday"), for: q))
        #expect(!TrackMatcher.accepts(c(271.1, artist: "Mayday"), for: q))
    }

    @Test func stricterWithoutArtist() {
        let n = TrackQuery(title: "溫柔", artist: nil, duration: 270)
        #expect(TrackMatcher.accepts(c(270.9), for: n))
        #expect(!TrackMatcher.accepts(c(271.1), for: n))
    }

    @Test func artistContainmentCounts() {
        #expect(TrackMatcher.accepts(c(272, artist: "五月天 Mayday"), for: q))
    }

    @Test func rejectsOtherTitle() {
        #expect(!TrackMatcher.accepts(c(270, title: "倔強"), for: q))
    }

    @Test func rejectsTheVersionSeenInSpike() {
        #expect(!TrackMatcher.accepts(
            c(204.8, title: "我多想擁抱你", artist: "黑屋乐队"),
            for: TrackQuery(title: "我多想擁抱你", artist: "黑屋乐队", duration: 193)
        ))
    }

    @Test func picksClosestDuration() {
        #expect(TrackMatcher.best([c(272.5), c(270.5)], for: q) { $0 }?.duration == 270.5)
    }

    @Test func bestIsNilWhenNothingAccepted() {
        #expect(TrackMatcher.best([c(300)], for: q) { $0 } == nil)
    }

    @Test func youtubeBracketTitle() {
        let r = YouTubeTitleParser.parse(title: "周杰倫 Jay Chou【告白氣球 Love Confession】Official MV", channel: "周杰倫 Jay Chou")
        #expect(r.title == "告白氣球" && r.artist == "周杰倫 Jay Chou")
    }

    @Test func youtubeBracketWithoutArtistUsesChannel() {
        let r = YouTubeTitleParser.parse(title: "【告白氣球】Official MV", channel: "周杰倫")
        #expect(r.title == "告白氣球" && r.artist == "周杰倫")
    }

    @Test func youtubeDashTitle() {
        let r = YouTubeTitleParser.parse(title: "五月天 Mayday - 溫柔 (Official Music Video)", channel: nil)
        #expect(r.title == "溫柔" && r.artist == "五月天 Mayday")
    }

    @Test func youtubeDashTitleSwapsWhenRightIsChannel() {
        let r = YouTubeTitleParser.parse(title: "溫柔 - 五月天", channel: "五月天")
        #expect(r.title == "溫柔" && r.artist == "五月天")
    }

    @Test func youtubeTopicChannel() {
        let r = YouTubeTitleParser.parse(title: "溫柔", channel: "五月天 - Topic")
        #expect(r.title == "溫柔" && r.artist == "五月天")
    }

    @Test func youtubePlainTitleUsesChannel() {
        let r = YouTubeTitleParser.parse(title: "溫柔 (Official)", channel: "五月天")
        #expect(r.title == "溫柔" && r.artist == "五月天")
    }

    @Test func youtubePlainTitleWithoutChannelHasNoArtist() {
        let r = YouTubeTitleParser.parse(title: "溫柔", channel: "  ")
        #expect(r.title == "溫柔" && r.artist == nil)
    }

    @Test func queryFromBrowserUsesYouTubeParser() {
        let snapshot = PlaybackSnapshot(
            title: "周杰倫 Jay Chou【告白氣球 Love Confession】Official MV", artist: "周杰倫 Jay Chou",
            duration: 250, elapsed: nil, timestamp: nil, rate: 1, isPlaying: true, bundleID: "com.google.Chrome"
        )
        #expect(TitleNormalizer.query(from: snapshot) == TrackQuery(title: "告白氣球", artist: "周杰倫 Jay Chou", duration: 250))
    }

    @Test func queryFromPlayerCleansTitleAndKeepsArtist() {
        let snapshot = PlaybackSnapshot(
            title: "溫柔 (Remastered)", artist: "五月天",
            duration: 270, elapsed: nil, timestamp: nil, rate: 1, isPlaying: true, bundleID: "com.spotify.client"
        )
        #expect(TitleNormalizer.query(from: snapshot) == TrackQuery(title: "溫柔", artist: "五月天", duration: 270))
    }
}
