import AppKit
import KTVCore

/// A display the user can put the subtitles on.
struct DisplayChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

/// The lists the settings window offers, kept apart from the layout.
enum SettingsChoices {
    static let fonts = ["PingFangTC-Semibold", "PingFangTC-Medium", "Heiti TC", "Kaiti TC"]
    static let autoDisplayName = "自動（主要螢幕）"
    static let missingDisplayName = "已中斷連線的顯示器"

    static func presetName(_ preset: StylePreset) -> String {
        switch preset {
        case .classic: return "經典 KTV"
        case .neon: return "霓虹包廂"
        case .quiet: return "低調單行"
        case .gold: return "金曲楷體"
        }
    }

    /// Fonts to list: the named ones, plus the current font when a saved style uses another.
    static func fonts(including current: String) -> [String] {
        fonts.contains(current) ? fonts : fonts + [current]
    }

    /// The connected displays, by localized name. Screens AppKit gives no number are left out.
    static func connectedDisplays(_ screens: [NSScreen] = NSScreen.screens) -> [DisplayChoice] {
        screens.compactMap { screen in
            ScreenInfo(screen).map { DisplayChoice(id: $0.id, name: screen.localizedName) }
        }
    }
}

extension RGBAColor {
    /// The color as sRGB channels. Falls back to black when the color cannot be converted.
    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent, a: srgb.alphaComponent)
    }
}
