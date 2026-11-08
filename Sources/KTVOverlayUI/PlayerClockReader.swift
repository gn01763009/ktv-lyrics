import Foundation
import KTVCore
import os

public protocol PlayerClockReading {
    func read(_ player: ScriptablePlayer) -> PlayerSample?
}

/// Asks Spotify or Music for its playback position through AppleScript.
/// Only call this for a player the caller has confirmed is running: AppleScript launches closed apps.
/// Runs on the main thread.
public final class PlayerClockReader: PlayerClockReading {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "PlayerClockReader")
    private static let playingState = "playing"
    private static let resultItemCount = 2

    private var scripts: [ScriptablePlayer: NSAppleScript] = [:]

    public init() {}

    public func read(_ player: ScriptablePlayer) -> PlayerSample? {
        guard let script = script(for: player) else {
            Self.logger.error("Cannot compile clock script for \(player.rawValue, privacy: .public)")
            return nil
        }
        let before = Date().timeIntervalSince1970
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        let after = Date().timeIntervalSince1970
        if let error {
            Self.logger.error("Clock read failed for \(player.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        guard result.numberOfItems == Self.resultItemCount,
              let position = result.atIndex(1)?.doubleValue,
              let state = result.atIndex(2)?.stringValue else {
            Self.logger.error("Unexpected clock reply from \(player.rawValue, privacy: .public)")
            return nil
        }
        return Self.sample(position: position, state: state, at: (before + after) / 2)
    }

    /// The sample for a reply, or nil, with a log, when the position is not a finite, non-negative time.
    static func sample(position: Double, state: String, at: Double) -> PlayerSample? {
        guard position.isFinite, position >= 0 else {
            logger.error("Rejected clock position \(position, privacy: .public)")
            return nil
        }
        return PlayerSample(position: position, isPlaying: state == playingState, at: at)
    }

    private func script(for player: ScriptablePlayer) -> NSAppleScript? {
        if let cached = scripts[player] { return cached }
        let source = "tell application \"\(player.rawValue)\" to return {player position, player state as text}"
        guard let script = NSAppleScript(source: source) else { return nil }
        scripts[player] = script
        return script
    }
}
