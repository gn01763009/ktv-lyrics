/// All timing constants for lyric display. Values come from the v1 design spec.
public enum LyricsTiming {
    /// Gap (seconds) between lines that starts a new section (interlude).
    public static let interludeMinGap: Double = 10
    /// Number of countdown stars shown before a line.
    public static let starCount: Int = 4
    /// Seconds per countdown star.
    public static let starSeconds: Double = 0.8
    /// Total countdown length: starCount * starSeconds.
    public static let countdownSeconds: Double = 3.2
    /// The title card is shown for at most this many seconds.
    public static let titleMaxSeconds: Double = 10
    /// Each line is shown this many seconds before it is sung.
    public static let subtitleLead: Double = 0.25
    /// Upper bound on singing pace, seconds per character.
    public static let maxSecondsPerChar: Double = 0.7
    /// Pace used when a song has too few usable lines to measure one.
    public static let fallbackSecondsPerChar: Double = 0.45
    /// Margin (seconds) kept free before the next line starts.
    public static let lineGapMargin: Double = 0.12
    /// How long the last line stays on screen after it ends.
    public static let trailingHold: Double = 3
}
