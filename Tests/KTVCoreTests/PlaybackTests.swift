import Foundation
@testable import KTVCore
import Testing

@Suite struct PlaybackTests {
    private let songJSON = #"{"type":"data","diff":false,"payload":{"title":"簡單愛","artist":"周杰倫","durationMicros":270987000,"elapsedTimeMicros":100005000,"timestampEpochMicros":1000000000000,"playbackRate":1,"playing":true,"bundleIdentifier":"com.spotify.client"}}"#

    private func snapshot(
        title: String = "簡單愛",
        artist: String? = "周杰倫",
        elapsed: Double? = 100,
        timestamp: Double? = 1000,
        rate: Double = 1,
        isPlaying: Bool = true
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            title: title,
            artist: artist,
            duration: 270,
            elapsed: elapsed,
            timestamp: timestamp,
            rate: rate,
            isPlaying: isPlaying,
            bundleID: "com.spotify.client"
        )
    }

    @Test func parsesAdapterRow() {
        guard case .playing(let s) = AdapterMessage.parse(Data(songJSON.utf8)) else {
            Issue.record("not playing")
            return
        }
        #expect(s.title == "簡單愛")
        #expect(s.duration == 270.987)
        #expect(abs(s.position(now: 1000002)! - 102.005) < 0.001)
    }

    @Test func missingRateDefaultsToOne() {
        let json = #"{"type":"data","diff":false,"payload":{"title":"歌","durationMicros":1000000,"elapsedTimeMicros":2000000,"timestampEpochMicros":1000000000000,"playing":true,"bundleIdentifier":"com.apple.Music"}}"#
        guard case .playing(let s) = AdapterMessage.parse(Data(json.utf8)) else {
            Issue.record("not playing")
            return
        }
        #expect(s.rate == 1)
        #expect(s.artist == nil)
    }

    @Test func emptyPayloadIsNothing() {
        #expect(AdapterMessage.parse(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)) == .nothing)
    }

    @Test func missingTitleIsNothing() {
        #expect(AdapterMessage.parse(Data(#"{"type":"data","diff":false,"payload":{"artist":"周杰倫"}}"#.utf8)) == .nothing)
    }

    @Test func garbageIsIgnored() {
        #expect(AdapterMessage.parse(Data("oops".utf8)) == .ignored)
    }

    @Test func pauseGlitchKeepsPosition() {
        let previous = snapshot(elapsed: 100, timestamp: 1000)
        let glitch = snapshot(elapsed: nil, timestamp: nil)
        let merged = glitch.merging(previous: previous)
        #expect(merged.elapsed == 100)
        #expect(merged.timestamp == 1000)
        #expect(merged.position(now: 1002) == 102)
    }

    @Test func differentTrackDoesNotMerge() {
        let previous = snapshot(title: "別首歌", elapsed: 100, timestamp: 1000)
        let glitch = snapshot(elapsed: nil, timestamp: nil)
        #expect(glitch.merging(previous: previous).elapsed == nil)
    }

    @Test func smallDriftIsKept() {
        let track = snapshot()
        let first = PositionResolver().applying(PlayerSample(position: 10, isPlaying: true, at: 1000), snapshot: track)
        // Predicted position at 1000.1 is 10.1; the sample is 0.10 ahead, under the 0.12 threshold.
        let second = first.applying(PlayerSample(position: 10.2, isPlaying: true, at: 1000.1), snapshot: track)
        #expect(second == first)
    }

    @Test func driftOverThresholdSnaps() {
        let track = snapshot()
        let first = PositionResolver().applying(PlayerSample(position: 10, isPlaying: true, at: 1000), snapshot: track)
        // Predicted position at 1000.1 is 10.1; the sample is 0.13 ahead, over the threshold.
        let second = first.applying(PlayerSample(position: 10.23, isPlaying: true, at: 1000.1), snapshot: track)
        #expect(abs(second.position(snapshot: track, now: 1000.1)! - 10.23) < 1e-9)
    }

    @Test func playStateChangeSnaps() {
        let track = snapshot()
        let first = PositionResolver().applying(PlayerSample(position: 10, isPlaying: true, at: 1000), snapshot: track)
        // No drift, but the player paused: the new sample is adopted, so the clock stops at 10.
        let second = first.applying(PlayerSample(position: 10, isPlaying: false, at: 1000), snapshot: track)
        #expect(second.position(snapshot: track, now: 1005) == 10)
    }

    @Test func readingForOtherTrackIsIgnored() {
        let trackA = snapshot(title: "A", elapsed: 10, timestamp: 1000)
        let trackB = snapshot(title: "B", elapsed: 50, timestamp: 1000)
        let resolver = PositionResolver().applying(PlayerSample(position: 10, isPlaying: true, at: 1000), snapshot: trackA)
        #expect(resolver.position(snapshot: trackB, now: 1000) == 50)
    }

    @Test func pollsOnlyRunningScriptablePlayers() {
        #expect(ScriptablePlayer.toPoll(bundleID: "com.spotify.client", running: ["com.spotify.client"]) == .spotify)
        #expect(ScriptablePlayer.toPoll(bundleID: "com.spotify.client", running: []) == nil)
        #expect(ScriptablePlayer.toPoll(bundleID: "com.apple.Music", running: ["com.apple.Music"]) == .music)
        #expect(ScriptablePlayer.toPoll(bundleID: "com.google.Chrome", running: ["com.google.Chrome"]) == nil)
    }
}
