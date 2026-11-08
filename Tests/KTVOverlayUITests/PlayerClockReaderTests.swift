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
}
