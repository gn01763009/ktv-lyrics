import AppKit
import KTVCore

/// One row of subtitle text and how much of it has been sung.
struct LyricRow {
    let text: String
    private let words: [WordTiming]?
    private let sweep: Sweep?

    static let blank = LyricRow(text: "", words: nil, sweep: nil)

    static func unsung(_ text: String) -> LyricRow {
        LyricRow(text: text, words: nil, sweep: nil)
    }

    static func line(_ line: LyricLine, sweep: Sweep?) -> LyricRow {
        LyricRow(text: line.text, words: line.words, sweep: sweep)
    }

    /// Width in points, from the row's left edge, that is already sung. Never more than the whole text.
    func sungWidth(font: NSFont) -> CGFloat {
        let whole = OutlinedText.width(text, font: font)
        switch sweep {
        case nil:
            return 0
        case .linear(let progress):
            return whole * Self.unit(progress)
        case .word(let index, let progress):
            guard let words, words.indices.contains(index) else { return whole }
            let before = words[..<index].map(\.text).joined()
            let current = OutlinedText.width(words[index].text, font: font) * Self.unit(progress)
            return min(whole, OutlinedText.width(before, font: font) + current)
        }
    }

    private static func unit(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }
}
