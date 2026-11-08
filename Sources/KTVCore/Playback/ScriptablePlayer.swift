/// Players the app can ask directly for their playback position.
public enum ScriptablePlayer: String, Sendable {
    case spotify = "Spotify"
    case music = "Music"

    private static let spotifyBundleID = "com.spotify.client"
    private static let musicBundleID = "com.apple.Music"

    /// The scriptable player behind `bundleID`, but only while that app is running.
    public static func toPoll(bundleID: String, running: Set<String>) -> ScriptablePlayer? {
        guard running.contains(bundleID) else { return nil }
        switch bundleID {
        case spotifyBundleID: return .spotify
        case musicBundleID: return .music
        default: return nil
        }
    }
}
