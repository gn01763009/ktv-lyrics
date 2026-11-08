import Foundation
import KTVCore
import os

public protocol PlayerClockReading {
    func read(_ player: ScriptablePlayer) -> PlayerSample?
}

/// Asks Spotify or Music for its playback position through AppleScript.
/// The script itself checks that the app is running, so a player that just quit is never relaunched,
/// and it gives up after `scriptTimeoutSeconds` so a hung player cannot block the main thread.
/// Runs on the main thread.
public final class PlayerClockReader: PlayerClockReading {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "PlayerClockReader")
    private static let playingState = "playing"
    private static let resultItemCount = 2
    private static let scriptTimeoutSeconds = 1

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
        return Self.sample(from: result, at: (before + after) / 2)
    }

    /// The sample for an AppleScript reply. An empty reply means the app was not running, which is not an error.
    static func sample(from reply: NSAppleEventDescriptor, at time: Double) -> PlayerSample? {
        guard reply.numberOfItems > 0 else { return nil }
        guard reply.numberOfItems == resultItemCount,
              let position = reply.atIndex(1)?.doubleValue,
              let state = reply.atIndex(2)?.stringValue else {
            logger.error("Unexpected clock reply from the player")
            return nil
        }
        return sample(position: position, state: state, at: time)
    }

    /// Reads the clock only while the app is running, and times out instead of waiting on a hung app.
    static func scriptSource(for player: ScriptablePlayer) -> String {
        let name = player.rawValue
        return """
        if application "\(name)" is running then
            with timeout of \(scriptTimeoutSeconds) second
                tell application "\(name)" to return {player position, player state as text}
            end timeout
        end if
        """
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
        guard let script = NSAppleScript(source: Self.scriptSource(for: player)) else { return nil }
        scripts[player] = script
        return script
    }
}
