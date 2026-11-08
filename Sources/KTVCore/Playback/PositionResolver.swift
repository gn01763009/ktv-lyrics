/// A position reported directly by a player, taken at the moment `at`.
public struct PlayerSample: Equatable, Sendable {
    public let position: Double
    public let isPlaying: Bool
    public let at: Double
}

/// Keeps one clock reading and replaces it only when a sample disagrees with its prediction.
/// This stops small timing jitter from making lyrics jump.
public struct PositionResolver: Equatable, Sendable {
    public static let snapThreshold = 0.12

    private let reading: ClockReading?

    public init() {
        reading = nil
    }

    private init(reading: ClockReading) {
        self.reading = reading
    }

    /// Uses the held reading when it belongs to the same song, otherwise the snapshot's own clock.
    public func position(snapshot: PlaybackSnapshot, now: Double) -> Double? {
        guard let reading, reading.trackKey == snapshot.trackKey else {
            return snapshot.position(now: now)
        }
        return reading.predicted(at: now)
    }

    /// Returns a resolver that holds `sample` when it is the first for this song, the play state
    /// changed, or it drifted past `snapThreshold`. Otherwise returns `self` unchanged.
    public func applying(_ sample: PlayerSample, snapshot: PlaybackSnapshot) -> PositionResolver {
        let key = snapshot.trackKey
        guard let current = reading, current.trackKey == key else {
            return PositionResolver(reading: ClockReading(trackKey: key, sample: sample))
        }
        let predicted = current.predicted(at: sample.at)
        let playStateChanged = current.isPlaying != sample.isPlaying
        let drifted = abs(sample.position - predicted) > Self.snapThreshold
        guard playStateChanged || drifted else { return self }
        return PositionResolver(reading: ClockReading(trackKey: key, sample: sample))
    }
}

private struct ClockReading: Equatable, Sendable {
    let trackKey: String
    let position: Double
    let at: Double
    let isPlaying: Bool

    init(trackKey: String, sample: PlayerSample) {
        self.trackKey = trackKey
        self.position = sample.position
        self.at = sample.at
        self.isPlaying = sample.isPlaying
    }

    func predicted(at now: Double) -> Double {
        isPlaying ? position + (now - at) : position
    }
}
