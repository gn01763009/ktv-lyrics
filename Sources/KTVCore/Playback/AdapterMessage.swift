import Foundation

/// What one line of media-adapter output means for playback.
public enum AdapterEvent: Equatable, Sendable {
    case playing(PlaybackSnapshot)
    case nothing
    case ignored
}

/// Parses one JSON line written by the media adapter.
public enum AdapterMessage {
    private static let dataType = "data"
    private static let microsPerSecond = 1_000_000.0
    private static let defaultRate = 1.0

    public static func parse(_ line: Data) -> AdapterEvent {
        guard let row = try? JSONDecoder().decode(Row.self, from: line), row.type == dataType else {
            return .ignored
        }
        guard let payload = row.payload, let title = payload.title, !title.isEmpty else {
            return .nothing
        }
        return .playing(snapshot(title: title, payload: payload))
    }

    private static func snapshot(title: String, payload: Payload) -> PlaybackSnapshot {
        PlaybackSnapshot(
            title: title,
            artist: payload.artist,
            duration: seconds(payload.durationMicros) ?? 0,
            elapsed: seconds(payload.elapsedTimeMicros),
            timestamp: seconds(payload.timestampEpochMicros),
            rate: payload.playbackRate ?? defaultRate,
            isPlaying: payload.playing ?? false,
            bundleID: payload.bundleIdentifier ?? ""
        )
    }

    private static func seconds(_ micros: Double?) -> Double? {
        micros.map { $0 / microsPerSecond }
    }

    private struct Row: Decodable {
        let type: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let durationMicros: Double?
        let elapsedTimeMicros: Double?
        let timestampEpochMicros: Double?
        let playbackRate: Double?
        let playing: Bool?
        let bundleIdentifier: String?
    }
}
