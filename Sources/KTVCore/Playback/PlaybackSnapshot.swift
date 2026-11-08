/// One reading of the system now-playing state. All times are in seconds.
public struct PlaybackSnapshot: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let duration: Double
    public let elapsed: Double?
    public let timestamp: Double?
    public let rate: Double
    public let isPlaying: Bool
    public let bundleID: String

    public init(
        title: String,
        artist: String?,
        duration: Double,
        elapsed: Double?,
        timestamp: Double?,
        rate: Double,
        isPlaying: Bool,
        bundleID: String
    ) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
        self.isPlaying = isPlaying
        self.bundleID = bundleID
    }

    /// Identifies the song, so readings of different songs are never mixed.
    public var trackKey: String {
        "\(title)|\(artist ?? "")"
    }

    /// The playback position at `now`, or nil when the snapshot lacks a reference point.
    public func position(now: Double) -> Double? {
        guard let elapsed, let timestamp else { return nil }
        guard isPlaying else { return elapsed }
        return elapsed + (now - timestamp) * rate
    }

    /// Fills in a missing reference point from the previous reading of the same song.
    /// Players drop elapsed time for a moment on pause, so the last known point is kept.
    public func merging(previous: PlaybackSnapshot?) -> PlaybackSnapshot {
        guard let previous, elapsed == nil || timestamp == nil, previous.trackKey == trackKey else {
            return self
        }
        return PlaybackSnapshot(
            title: title,
            artist: artist,
            duration: duration,
            elapsed: previous.elapsed,
            timestamp: previous.timestamp,
            rate: rate,
            isPlaying: isPlaying,
            bundleID: bundleID
        )
    }
}
