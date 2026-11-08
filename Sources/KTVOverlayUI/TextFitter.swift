import AppKit

/// Picks a font size that keeps a text on one line.
public enum TextFitter {
    /// `preferred`, or a smaller size when the text would be wider than `maxWidth`.
    public static func fontSize(for text: String, fontName: String, preferred: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard preferred > 0, maxWidth > 0 else { return preferred }
        let natural = OutlinedText.width(text, font: KaraokeFont.resolve(name: fontName, size: preferred))
        return natural > maxWidth ? preferred * maxWidth / natural : preferred
    }
}

enum KaraokeFont {
    /// Weight passed to `NSFontManager` when only a family name is known; 9 is bold.
    private static let familyWeight = 9

    /// A PostScript name, else a family name such as `Kaiti TC`, else the bold system font.
    static func resolve(name: String, size: CGFloat) -> NSFont {
        NSFont(name: name, size: size)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: familyWeight, size: size)
            ?? .boldSystemFont(ofSize: size)
    }
}
