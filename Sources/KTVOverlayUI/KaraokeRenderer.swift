import AppKit
import KTVCore

/// Draws one frame of the overlay into the current graphics context. Holds no state between frames.
struct KaraokeRenderer {
    static let bannerText = "《來賓請掌聲鼓勵》"
    static let starGlyph = "★"
    static let originalArtistLabel = "原唱："

    private static let sideMargin: CGFloat = 20
    private static let bottomMargin: CGFloat = 16
    private static let rowSpacing: CGFloat = 1.42
    private static let minBoxWidth: CGFloat = 12.5
    private static let boxPadding: CGFloat = 2.2
    private static let bannerBottom: CGFloat = 40
    private static let noticeSize: CGFloat = 22
    private static let noticeBottom: CGFloat = 24
    private static let titleScale: CGFloat = 1.4
    private static let creditScale: CGFloat = 0.74
    private static let creditSpacing: CGFloat = 1.02
    private static let creditsBottom: CGFloat = 12
    private static let titleGap: CGFloat = 10
    private static let sweepPadding: CGFloat = 0.3
    private static let sweepDescent: CGFloat = 0.35
    private static let sweepHeight: CGFloat = 1.9
    private static let redTitleFill = RGBAColor(hex: 0xE5202A)
    private static let blueTitleFill = RGBAColor(hex: 0x35A7F0)
    private static let titleStroke = RGBAColor(hex: 0xFFFFFF)

    let content: OverlayContent
    let settings: OverlaySettings
    let canvas: CGSize

    private var style: OverlayStyle { settings.style }
    private var em: CGFloat { CGFloat(settings.size * style.scale) }
    private var unsungInk: Ink { .unsung(style) }
    private var maxTextWidth: CGFloat { canvas.width - 2 * Self.sideMargin }

    func draw() {
        switch content.scene {
        case .idle: drawNotice()
        case .title: drawTitleCard()
        case .interlude(let showBanner): if showBanner { drawBanner() }
        case .countdown(let upcoming, let stars): drawCountdown(upcoming: upcoming, stars: stars)
        case .singing(let index, let sweep): drawLine(at: index, sweep: sweep)
        case .held(let index): drawLine(at: index, sweep: .linear(1))
        }
    }

    // MARK: Scenes

    private func drawLine(at index: Int, sweep: Sweep) {
        guard content.lines.indices.contains(index) else { return }
        let line = content.lines[index]
        let active = LyricRow.line(line, sweep: sweep)
        if style.singleLine {
            drawCentered(active, y: Self.bottomMargin)
            return
        }
        let next = content.lines.indices.contains(index + 1) ? content.lines[index + 1] : nil
        let other = next.flatMap { $0.slot != line.slot ? LyricRow.unsung($0.text) : nil } ?? .blank
        line.slot == 0 ? drawRows(top: active, bottom: other) : drawRows(top: other, bottom: active)
    }

    private func drawCountdown(upcoming: Int, stars: Int) {
        guard content.lines.indices.contains(upcoming) else { return }
        let line = content.lines[upcoming]
        let starRow = LyricRow.unsung((line.part ?? "") + String(repeating: Self.starGlyph, count: max(0, stars)))
        if style.singleLine {
            drawCentered(starRow, y: Self.bottomMargin)
        } else {
            drawRows(top: starRow, bottom: .unsung(line.text))
        }
    }

    private func drawBanner() {
        drawCentered(.unsung(Self.bannerText), y: Self.bannerBottom)
    }

    private func drawNotice() {
        guard let notice = content.notice, !notice.isEmpty else { return }
        drawCentered(.unsung(notice), y: Self.noticeBottom, size: Self.noticeSize)
    }

    private func drawTitleCard() {
        let credits = (content.artist.map { [Self.originalArtistLabel + $0] } ?? []) + content.credits
        let lineHeight = em * Self.creditSpacing
        let boxLeft = (canvas.width - em * Self.minBoxWidth) / 2
        let creditInk = content.usesRedTitle ? titleInk(Self.blueTitleFill) : unsungInk
        for (position, text) in credits.reversed().enumerated() {
            let y = Self.creditsBottom + CGFloat(position) * lineHeight
            let font = fitted(text, size: em * Self.creditScale, maxWidth: canvas.width - boxLeft - Self.sideMargin)
            OutlinedText.draw(text, at: NSPoint(x: boxLeft, y: y), font: font, ink: creditInk)
        }
        let fill = content.usesRedTitle ? Self.redTitleFill : Self.blueTitleFill
        let titleY = Self.creditsBottom + Self.titleGap + CGFloat(credits.count) * lineHeight
        drawCentered(.unsung(content.title), y: titleY, size: em * Self.titleScale, ink: titleInk(fill))
    }

    private func titleInk(_ fill: RGBAColor) -> Ink {
        Ink(fill: fill, stroke: Self.titleStroke, strokeWidth: style.strokeWidth)
    }

    // MARK: Layout

    /// Two rows in a shared box: the top row aligned left, the bottom row aligned right.
    private func drawRows(top: LyricRow, bottom: LyricRow) {
        let topFont = fitted(top.text, size: em), bottomFont = fitted(bottom.text, size: em)
        let topWidth = OutlinedText.width(top.text, font: topFont)
        let bottomWidth = OutlinedText.width(bottom.text, font: bottomFont)
        let boxWidth = min(maxTextWidth, max(em * Self.minBoxWidth, max(topWidth, bottomWidth) + em * Self.boxPadding))
        let boxLeft = (canvas.width - boxWidth) / 2
        let bottomY = Self.bottomMargin
        drawRow(top, at: NSPoint(x: boxLeft, y: bottomY + em * Self.rowSpacing), font: topFont)
        drawRow(bottom, at: NSPoint(x: boxLeft + boxWidth - bottomWidth, y: bottomY), font: bottomFont)
    }

    private func drawCentered(_ row: LyricRow, y: CGFloat, size: CGFloat? = nil, ink: Ink? = nil) {
        let font = fitted(row.text, size: size ?? em)
        let x = (canvas.width - OutlinedText.width(row.text, font: font)) / 2
        drawRow(row, at: NSPoint(x: x, y: y), font: font, ink: ink)
    }

    private func drawRow(_ row: LyricRow, at point: NSPoint, font: NSFont, ink: Ink? = nil) {
        guard !row.text.isEmpty else { return }
        OutlinedText.draw(row.text, at: point, font: font, ink: ink ?? unsungInk)
        let sungWidth = row.sungWidth(font: font)
        guard sungWidth > 0 else { return }
        let size = font.pointSize
        let padding = size * Self.sweepPadding
        let isComplete = sungWidth >= OutlinedText.width(row.text, font: font)
        let clip = NSRect(
            x: point.x - padding,
            y: point.y - size * Self.sweepDescent,
            width: padding + sungWidth + (isComplete ? padding : 0),
            height: size * Self.sweepHeight
        )
        OutlinedText.drawClipped(row.text, at: point, font: font, ink: .sung(style), clip: clip)
    }

    private func fitted(_ text: String, size: CGFloat, maxWidth: CGFloat? = nil) -> NSFont {
        let fitted = TextFitter.fontSize(
            for: text, fontName: style.fontName, preferred: size, maxWidth: maxWidth ?? maxTextWidth
        )
        return KaraokeFont.resolve(name: style.fontName, size: fitted)
    }
}
