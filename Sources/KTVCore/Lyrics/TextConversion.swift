import Foundation
import os

/// Converts lyric text between Chinese scripts. Pure apart from logging.
public enum TextConversion {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "TextConversion")
    private static let simplifiedToTraditional = StringTransform("Simplified-Traditional")

    /// Returns the Traditional form of `text`. If ICU cannot convert it, the input is returned unchanged and logged.
    public static func toTraditional(_ text: String) -> String {
        guard let converted = text.applyingTransform(simplifiedToTraditional, reverse: false) else {
            logger.error("Simplified-Traditional conversion failed; keeping the original text")
            return text
        }
        return converted
    }
}
