@testable import KTVCore
import CoreGraphics
import Foundation
import Testing

@Suite struct SettingsTests {
    private let main = ScreenInfo(
        id: "A",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 830)
    )
    private let external = ScreenInfo(
        id: "B",
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 25, width: 1920, height: 1055)
    )
    private let contentSize = CGSize(width: 1000, height: 320)

    /// Runs `body` with a uniquely named defaults suite, and removes that suite afterwards.
    private func withDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
        let name = "SettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        return try body(defaults)
    }

    private func decodeSettings(_ json: String) throws -> OverlaySettings {
        try JSONDecoder().decode(OverlaySettings.self, from: Data(json.utf8))
    }

    // MARK: Defaults and presets

    @Test func defaultsAreClassic() {
        #expect(OverlaySettings.defaults.preset == .classic && OverlaySettings.defaults.size == 46 && OverlaySettings.defaults.useNetEase)
        #expect(OverlaySettings.defaults.opacity == 1)
        #expect(OverlaySettings.defaults.anchor == NormalizedPoint(x: 0.5, y: 0.05))
        #expect(OverlaySettings.defaults.style.strokeWidth == 20)
        #expect(OverlaySettings.defaults.style == StylePreset.classic.style)
    }

    @Test func presetColors() {
        #expect(StylePreset.classic.style.sungFill == RGBAColor(hex: 0x1746E0))
        #expect(StylePreset.classic.style.unsungFill == RGBAColor(hex: 0xFFFFFF))
        #expect(StylePreset.classic.style.unsungStroke == RGBAColor(hex: 0x000000))
        #expect(StylePreset.classic.style.sungStroke == RGBAColor(hex: 0xFFFFFF))
        #expect(StylePreset.classic.style.fontName == "PingFangTC-Semibold")
        #expect(StylePreset.classic.style.strokeWidth == 20)
        #expect(StylePreset.classic.style.scale == 1)
    }

    @Test func neonColors() {
        #expect(StylePreset.neon.style.sungStroke == RGBAColor(hex: 0x3B1060))
        #expect(StylePreset.neon.style.sungFill == RGBAColor(hex: 0xFF5FD2))
        #expect(StylePreset.neon.style.unsungStroke == RGBAColor(hex: 0x3B1060))
        #expect(StylePreset.neon.style.unsungFill == RGBAColor(hex: 0xFFFFFF))
        #expect(StylePreset.neon.style.strokeWidth == 16)
        #expect(StylePreset.neon.style.fontName == "PingFangTC-Semibold")
        #expect(StylePreset.neon.style.scale == 1)
    }

    @Test func quietColorsAndScale() {
        #expect(StylePreset.quiet.style.singleLine && StylePreset.quiet.style.scale == 0.72)
        #expect(StylePreset.quiet.style.sungStroke == RGBAColor(hex: 0x000000, alpha: 0.72))
        #expect(StylePreset.quiet.style.sungFill == RGBAColor(hex: 0xFFCF5A))
        #expect(StylePreset.quiet.style.unsungFill == RGBAColor(hex: 0xFFFFFF, alpha: 0.94))
        #expect(StylePreset.quiet.style.strokeWidth == 13)
        #expect(StylePreset.quiet.style.fontName == "PingFangTC-Medium")
    }

    @Test func goldColorsAndFont() {
        #expect(StylePreset.gold.style.unsungFill == RGBAColor(hex: 0xFFF8E6))
        #expect(StylePreset.gold.style.unsungStroke == RGBAColor(hex: 0x4D2500))
        #expect(StylePreset.gold.style.sungStroke == RGBAColor(hex: 0x4D2500))
        #expect(StylePreset.gold.style.sungFill == RGBAColor(hex: 0xFFB516))
        #expect(StylePreset.gold.style.fontName == "Kaiti TC")
        #expect(StylePreset.gold.style.strokeWidth == 20)
        #expect(StylePreset.gold.style.scale == 1)
    }

    @Test func onlyQuietIsSingleLine() {
        #expect(StylePreset.allCases.filter { $0.style.singleLine } == [.quiet])
    }

    @Test func hexDecodesChannelsAndAlpha() {
        let color = RGBAColor(hex: 0x1746E0, alpha: 0.5)
        #expect(color == RGBAColor(r: 0x17 / 255, g: 0x46 / 255, b: 0xE0 / 255, a: 0.5))
    }

    @Test func rgbaInitClampsOutOfRangeChannels() {
        #expect(RGBAColor(r: 2, g: -1, b: 0.5, a: 9) == RGBAColor(r: 1, g: 0, b: 0.5, a: 1))
    }

    @Test func normalizedPointClampsToUnitSquare() {
        #expect(NormalizedPoint(x: 1.5, y: -0.2) == NormalizedPoint(x: 1, y: 0))
    }

    @Test func withReturnsCopyAndLeavesOriginalUnchanged() {
        let original = OverlaySettings.defaults
        let changed = original.with(\.size, 60)
        #expect(changed.size == 60)
        #expect(original.size == 46)
        #expect(changed.with(\.size, 46) == original)
    }

    // MARK: Persistence

    @Test func roundTrips() throws {
        try withDefaults { defaults in
            let store = UserDefaultsSettingsStore(defaults: defaults)
            let changed = OverlaySettings.defaults.with(\.size, 60)
            store.save(changed)
            #expect(store.load() == changed)
        }
    }

    @Test func corruptDataFallsBackToDefaults() throws {
        try withDefaults { defaults in
            defaults.set(Data("亂碼 {".utf8), forKey: UserDefaultsSettingsStore.storageKey)
            #expect(UserDefaultsSettingsStore(defaults: defaults).load() == .defaults)
        }
    }

    @Test func missingKeysUseDefaults() throws {
        let decoded = try decodeSettings(#"{"size":60}"#)
        #expect(decoded.size == 60)
        #expect(decoded == OverlaySettings.defaults.with(\.size, 60))
    }

    @Test func unknownPresetFallsBackToClassic() throws {
        let decoded = try decodeSettings(#"{"preset":"nope","size":50}"#)
        #expect(decoded.preset == .classic)
        #expect(decoded.size == 50)
        #expect(decoded.style == StylePreset.classic.style)
    }

    @Test func missingStyleFollowsDecodedPreset() throws {
        let decoded = try decodeSettings(#"{"preset":"neon"}"#)
        #expect(decoded.preset == .neon)
        #expect(decoded.style == StylePreset.neon.style)
    }

    // MARK: Placement

    @Test func placesOnSavedDisplay() {
        let settings = OverlaySettings.defaults.with(\.displayID, "B")
        let placed = PanelPlacement.frame(settings: settings, contentSize: contentSize, screens: [main, external])
        #expect(external.visibleFrame.contains(placed))
        #expect(!main.visibleFrame.intersects(placed))
    }

    @Test func missingDisplayFallsBackToFirst() {
        let settings = OverlaySettings.defaults.with(\.displayID, "gone")
        let placed = PanelPlacement.frame(settings: settings, contentSize: contentSize, screens: [main, external])
        #expect(main.visibleFrame.contains(placed))
    }

    @Test func clampsToVisibleArea() {
        let settings = OverlaySettings.defaults.with(\.anchor, NormalizedPoint(x: 1, y: 1))
        let placed = PanelPlacement.frame(settings: settings, contentSize: contentSize, screens: [main])
        #expect(main.visibleFrame.contains(placed))
        #expect(placed.size == contentSize)
    }

    @Test func oversizedContentAlignsToVisibleOrigin() {
        let huge = CGSize(width: 2000, height: 1000)
        let placed = PanelPlacement.frame(settings: .defaults, contentSize: huge, screens: [main])
        #expect(placed.origin == CGPoint(x: main.visibleFrame.minX, y: main.visibleFrame.minY))
        #expect(placed.size == huge)
    }

    @Test func noScreensReturnsOriginRect() {
        let placed = PanelPlacement.frame(settings: .defaults, contentSize: contentSize, screens: [])
        #expect(placed == CGRect(origin: .zero, size: contentSize))
    }

    @Test func anchorRoundTrips() {
        let original = CGRect(origin: CGPoint(x: 200, y: 300), size: contentSize)
        let anchor = PanelPlacement.anchor(for: original, on: main)
        let settings = OverlaySettings.defaults.with(\.anchor, anchor)
        let placed = PanelPlacement.frame(settings: settings, contentSize: contentSize, screens: [main])
        #expect(abs(placed.minX - original.minX) < 1)
        #expect(abs(placed.minY - original.minY) < 1)
    }
}
