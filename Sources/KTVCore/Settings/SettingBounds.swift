/// Valid ranges and defaults for stored settings. Every value read from storage is clamped into its range.
public enum SettingBounds {
    public static let size: ClosedRange<Double> = 16...96
    public static let opacity: ClosedRange<Double> = 0.1...1
    public static let scale: ClosedRange<Double> = 0.3...2
    public static let strokeWidth: ClosedRange<Double> = 0...40
    public static let channel: ClosedRange<Double> = 0...1
    public static let anchor: ClosedRange<Double> = 0...1

    public static let defaultSize: Double = 46
    public static let defaultOpacity: Double = 1
    public static let defaultStrokeWidth: Double = 20
    public static let defaultScale: Double = 1
    public static let defaultChannel: Double = 0
    public static let defaultAlpha: Double = 1
    public static let defaultAnchor: Double = 0
}

extension ClosedRange where Bound == Double {
    /// `value` clamped into the range, or `fallback` when `value` is NaN or infinite.
    func validated(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
