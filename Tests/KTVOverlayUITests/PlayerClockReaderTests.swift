import Foundation
import KTVCore
@testable import KTVOverlayUI
import Testing

@Suite struct PlayerClockReaderTests {
    @Test func acceptsAFinitePosition() {
        let sample = PlayerClockReader.sample(position: 12.5, state: "playing", at: 100)
        #expect(sample == PlayerSample(position: 12.5, isPlaying: true, at: 100))
    }

    @Test func anyOtherStateMeansNotPlaying() {
        #expect(PlayerClockReader.sample(position: 0, state: "paused", at: 1)?.isPlaying == false)
    }

    @Test func rejectsNegativeAndNonFinitePositions() {
        #expect(PlayerClockReader.sample(position: -0.5, state: "playing", at: 1) == nil)
        #expect(PlayerClockReader.sample(position: .nan, state: "playing", at: 1) == nil)
        #expect(PlayerClockReader.sample(position: .infinity, state: "playing", at: 1) == nil)
    }

    @Test func scriptChecksRunningStateAndCapsTheWait() {
        let source = PlayerClockReader.scriptSource(for: .spotify)
        #expect(source.contains("if application \"Spotify\" is running then"))
        #expect(source.contains("with timeout of 1 second"))
        #expect(source.contains("end timeout"))
        #expect(PlayerClockReader.scriptSource(for: .music).contains("application \"Music\" is running"))
    }

    @Test func runningCheckComesBeforeTheTell() throws {
        let source = PlayerClockReader.scriptSource(for: .spotify)
        let running = try #require(source.range(of: "is running"))
        let tell = try #require(source.range(of: "tell application"))
        #expect(running.lowerBound < tell.lowerBound)
    }

    @Test func emptyReplyMeansNotRunning() {
        #expect(PlayerClockReader.sample(from: NSAppleEventDescriptor.null(), at: 1) == nil)
        #expect(PlayerClockReader.sample(from: NSAppleEventDescriptor.list(), at: 1) == nil)
    }

    @Test func positionAndStateReplyBecomesASample() {
        let reply = NSAppleEventDescriptor.list()
        reply.insert(NSAppleEventDescriptor(double: 12.5), at: 1)
        reply.insert(NSAppleEventDescriptor(string: "playing"), at: 2)
        #expect(PlayerClockReader.sample(from: reply, at: 7) == PlayerSample(position: 12.5, isPlaying: true, at: 7))
    }
}
