import CoreGraphics
import Foundation
import os

/// A point in 0...1 coordinates. Values are clamped on construction and on decode.
public struct NormalizedPoint: Equatable, Codable, Sendable {
    public let x, y: Double

    public init(x: Double, y: Double) {
        self.x = SettingBounds.anchor.validated(x, fallback: SettingBounds.defaultAnchor)
        self.y = SettingBounds.anchor.validated(y, fallback: SettingBounds.defaultAnchor)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(Double.self, forKey: .x),
            y: try container.decode(Double.self, forKey: .y)
        )
    }
}

/// Everything the user can change in the overlay settings panel.
public struct OverlaySettings: Equatable, Codable, Sendable {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "OverlaySettings")

    public var size, opacity: Double
    public var preset: StylePreset
    public var style: OverlayStyle
    public var showTitleCard, showCountdown, showBanner, useNetEase, launchAtLogin: Bool
    public var anchor: NormalizedPoint
    public var displayID: String?

    public static let defaults = OverlaySettings(
        size: SettingBounds.defaultSize,
        opacity: SettingBounds.defaultOpacity,
        preset: .classic,
        style: StylePreset.classic.style,
        showTitleCard: true,
        showCountdown: true,
        showBanner: true,
        useNetEase: true,
        launchAtLogin: false,
        anchor: NormalizedPoint(x: 0.5, y: 0.05),
        displayID: nil
    )

    public init(
        size: Double,
        opacity: Double,
        preset: StylePreset,
        style: OverlayStyle,
        showTitleCard: Bool,
        showCountdown: Bool,
        showBanner: Bool,
        useNetEase: Bool,
        launchAtLogin: Bool,
        anchor: NormalizedPoint,
        displayID: String?
    ) {
        self.size = SettingBounds.size.validated(size, fallback: SettingBounds.defaultSize)
        self.opacity = SettingBounds.opacity.validated(opacity, fallback: SettingBounds.defaultOpacity)
        self.preset = preset
        self.style = style
        self.showTitleCard = showTitleCard
        self.showCountdown = showCountdown
        self.showBanner = showBanner
        self.useNetEase = useNetEase
        self.launchAtLogin = launchAtLogin
        self.anchor = anchor
        self.displayID = displayID
    }

    /// Decodes every field with `decodeIfPresent`, so older or partial JSON keeps defaults for the rest.
    /// An unknown preset falls back to classic. A missing style follows the decoded preset.
    /// Size, opacity, and the style and anchor values are clamped through their initializers.
    public init(from decoder: Decoder) throws {
        let fallback = Self.defaults
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presetName = try container.decodeIfPresent(String.self, forKey: .preset)
        let preset = presetName.flatMap(StylePreset.init(rawValue:)) ?? fallback.preset
        if let presetName, StylePreset(rawValue: presetName) == nil {
            Self.logger.notice("Unknown overlay preset \(presetName, privacy: .public); using classic")
        }
        self.init(
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? fallback.size,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? fallback.opacity,
            preset: preset,
            style: try container.decodeIfPresent(OverlayStyle.self, forKey: .style) ?? preset.style,
            showTitleCard: try container.decodeIfPresent(Bool.self, forKey: .showTitleCard) ?? fallback.showTitleCard,
            showCountdown: try container.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? fallback.showCountdown,
            showBanner: try container.decodeIfPresent(Bool.self, forKey: .showBanner) ?? fallback.showBanner,
            useNetEase: try container.decodeIfPresent(Bool.self, forKey: .useNetEase) ?? fallback.useNetEase,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin,
            anchor: try container.decodeIfPresent(NormalizedPoint.self, forKey: .anchor) ?? fallback.anchor,
            displayID: try container.decodeIfPresent(String.self, forKey: .displayID)
        )
    }

    /// A copy with one field replaced. The receiver is left unchanged.
    public func with<V>(_ path: WritableKeyPath<OverlaySettings, V>, _ value: V) -> OverlaySettings {
        var copy = self
        copy[keyPath: path] = value
        return copy
    }
}
