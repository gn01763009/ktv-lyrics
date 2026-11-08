import AppKit
import KTVCore

/// Fill and stroke colours for one piece of text, plus the stroke width as a percentage of the font size.
struct Ink {
    /// `NSAttributedString.Key.strokeWidth` for the dark rim, which sits just outside a white stroke.
    private static let rimExtraWidth: CGFloat = 4
    /// Negative widths fill and stroke in one colour; this thins the fill so the stroke stays visible.
    private static let fillWidth: CGFloat = -3.5
    private static let rimColor = NSColor.black.withAlphaComponent(0.85)

    let fill, stroke: NSColor
    let strokeWidth: CGFloat
    /// Only text with a white stroke gets a rim, so it stays readable over bright backgrounds.
    let hasRim: Bool

    init(fill: RGBAColor, stroke: RGBAColor, strokeWidth: Double) {
        self.fill = fill.nsColor
        self.stroke = stroke.nsColor
        self.strokeWidth = CGFloat(strokeWidth)
        hasRim = stroke.isWhite
    }

    static func unsung(_ style: OverlayStyle) -> Ink {
        Ink(fill: style.unsungFill, stroke: style.unsungStroke, strokeWidth: style.strokeWidth)
    }

    static func sung(_ style: OverlayStyle) -> Ink {
        Ink(fill: style.sungFill, stroke: style.sungStroke, strokeWidth: style.strokeWidth)
    }

    /// Layers to paint, back to front, as colour and `strokeWidth`.
    var layers: [(color: NSColor, width: CGFloat)] {
        (hasRim ? [(Self.rimColor, strokeWidth + Self.rimExtraWidth)] : [])
            + [(stroke, strokeWidth), (fill, Self.fillWidth)]
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var isWhite: Bool { r == 1 && g == 1 && b == 1 }
}

enum OutlinedText {
    static func width(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Draws `text` with its baseline box at `point`: rim, stroke, then fill, with round joins.
    static func draw(_ text: String, at point: NSPoint, font: NSFont, ink: Ink) {
        guard !text.isEmpty else { return }
        NSGraphicsContext.current?.cgContext.setLineJoin(.round)
        for layer in ink.layers {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: layer.color, .strokeColor: layer.color, .strokeWidth: layer.width,
            ]
            NSAttributedString(string: text, attributes: attributes).draw(at: point)
        }
    }

    /// Draws `ink` only inside `clip`, for the sung part of a line.
    static func drawClipped(_ text: String, at point: NSPoint, font: NSFont, ink: Ink, clip: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: clip).setClip()
        draw(text, at: point, font: font, ink: ink)
        NSGraphicsContext.restoreGraphicsState()
    }
}
