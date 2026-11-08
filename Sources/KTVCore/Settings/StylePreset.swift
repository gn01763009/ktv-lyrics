import Foundation

/// A color with 0...1 channels. Channels are clamped on construction.
public struct RGBAColor: Equatable, Codable, Sendable {
    public let r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = Self.clamp(r)
        self.g = Self.clamp(g)
        self.b = Self.clamp(b)
        self.a = Self.clamp(a)
    }

    /// A color from a `0xRRGGBB` literal.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            r: Self.channel(hex, shift: 16),
            g: Self.channel(hex, shift: 8),
            b: Self.channel(hex, shift: 0),
            a: alpha
        )
    }

    private static let channelMax: Double = 255

    private static func channel(_ hex: UInt32, shift: UInt32) -> Double {
        Double((hex >> shift) & 0xFF) / channelMax
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// How one subtitle line is painted: unsung and sung fill and stroke, plus font and layout.
public struct OverlayStyle: Equatable, Codable, Sendable {
    public let unsungFill, unsungStroke, sungFill, sungStroke: RGBAColor
    /// Stroke width as a percentage of the font size.
    public let strokeWidth: Double
    public let fontName: String
    public let scale: Double
    public let singleLine: Bool

    public init(
        unsungFill: RGBAColor,
        unsungStroke: RGBAColor,
        sungFill: RGBAColor,
        sungStroke: RGBAColor,
        strokeWidth: Double,
        fontName: String,
        scale: Double,
        singleLine: Bool
    ) {
        self.unsungFill = unsungFill
        self.unsungStroke = unsungStroke
        self.sungFill = sungFill
        self.sungStroke = sungStroke
        self.strokeWidth = strokeWidth
        self.fontName = fontName
        self.scale = scale
        self.singleLine = singleLine
    }
}

/// The named looks offered in the settings panel.
public enum StylePreset: String, CaseIterable, Codable, Sendable {
    case classic, neon, quiet, gold

    public var style: OverlayStyle {
        switch self {
        case .classic: Self.classicStyle
        case .neon: Self.neonStyle
        case .quiet: Self.quietStyle
        case .gold: Self.goldStyle
        }
    }

    private static let classicStyle = OverlayStyle(
        unsungFill: RGBAColor(hex: 0xFFFFFF),
        unsungStroke: RGBAColor(hex: 0x000000),
        sungFill: RGBAColor(hex: 0x1746E0),
        sungStroke: RGBAColor(hex: 0xFFFFFF),
        strokeWidth: 20,
        fontName: "PingFangTC-Semibold",
        scale: 1,
        singleLine: false
    )
    private static let neonStyle = OverlayStyle(
        unsungFill: RGBAColor(hex: 0xFFFFFF),
        unsungStroke: RGBAColor(hex: 0x3B1060),
        sungFill: RGBAColor(hex: 0xFF5FD2),
        sungStroke: RGBAColor(hex: 0x3B1060),
        strokeWidth: 16,
        fontName: "PingFangTC-Semibold",
        scale: 1,
        singleLine: false
    )
    private static let quietStyle = OverlayStyle(
        unsungFill: RGBAColor(hex: 0xFFFFFF, alpha: 0.94),
        unsungStroke: RGBAColor(hex: 0x000000, alpha: 0.72),
        sungFill: RGBAColor(hex: 0xFFCF5A),
        sungStroke: RGBAColor(hex: 0x000000, alpha: 0.72),
        strokeWidth: 13,
        fontName: "PingFangTC-Medium",
        scale: 0.72,
        singleLine: true
    )
    private static let goldStyle = OverlayStyle(
        unsungFill: RGBAColor(hex: 0xFFF8E6),
        unsungStroke: RGBAColor(hex: 0x4D2500),
        sungFill: RGBAColor(hex: 0xFFB516),
        sungStroke: RGBAColor(hex: 0x4D2500),
        strokeWidth: 20,
        fontName: "Kaiti TC",
        scale: 1,
        singleLine: false
    )
}
