/// How long to wait before restarting a helper process that keeps failing.
public enum RestartPolicy {
    private static let baseDelay = 1.0
    private static let maxDelay = 30.0
    private static let maxDoublings = 5

    /// Seconds to wait before retry number `attempt` (0-based): 1, 2, 4, 8, 16, then 30.
    public static func delay(attempt: Int) -> Double {
        let doublings = min(max(attempt, 0), maxDoublings)
        return min(baseDelay * Double(1 << doublings), maxDelay)
    }
}
