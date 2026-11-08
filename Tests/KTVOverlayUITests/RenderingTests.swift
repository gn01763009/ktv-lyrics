import AppKit
import KTVCore
import KTVOverlayUI
import Testing

@Suite struct RenderingTests {
    // Classic sung fill, 0x1746E0.
    private let sungBlue = (r: 0x17, g: 0x46, b: 0xE0)
    private let lightTitleBlue = (r: 0x35, g: 0xA7, b: 0xF0)
    private let redTitle = (r: 0xE5, g: 0x20, b: 0x2A)
    private let goldSung = (r: 0xFF, g: 0xB5, b: 0x16)
    // Credits fill the bottom 110 points; the title sits above them.
    private let creditTopPoints = 110.0
    private let canvas = CGSize(width: 1200, height: 320)

    @Test @MainActor func idleIsFullyTransparent() {
        #expect(render(.idle).maxAlpha == 0)
    }

    @Test @MainActor func lineSweepPaintsOnlyTheLeft() {
        let img = render(.singing(index: 0, sweep: .linear(0.5)))
        #expect(img.count(of: sungBlue, in: .leftHalfOfLine) > 0)
        #expect(img.count(of: sungBlue, in: .rightHalfOfLine) == 0)
    }

    @Test @MainActor func wordSweepStopsAtTheWord() {
        let img = render(.singing(index: 0, sweep: .word(index: 1, progress: 0)), words: ["一", "二"])
        #expect(img.count(of: sungBlue, in: .leftHalfOfLine) > 0)
        #expect(img.count(of: sungBlue, in: .rightHalfOfLine) == 0)
    }

    @Test @MainActor func finishedLinePaintsBothHalves() {
        let img = render(.held(index: 0))
        #expect(img.count(of: sungBlue, in: .leftHalfOfLine) > 0)
        #expect(img.count(of: sungBlue, in: .rightHalfOfLine) > 0)
    }

    @Test @MainActor func bannerDraws() {
        #expect(render(.interlude(showBanner: true)).maxAlpha > 0)
    }

    @Test @MainActor func silentInterludeIsEmpty() {
        #expect(render(.interlude(showBanner: false)).maxAlpha == 0)
    }

    @Test @MainActor func titleCardDraws() {
        #expect(render(.title).maxAlpha > 0)
    }

    @Test @MainActor func classicRedTitleCreditsUseTheSungBlue() {
        let img = render(.title)
        #expect(img.count(of: sungBlue, inRowsFromBottom: creditRows(img)) > 0)
        #expect(img.count(of: lightTitleBlue, inRowsFromBottom: creditRows(img)) == 0)
        #expect(img.count(of: redTitle, inRowsFromBottom: titleRows(img)) > 0)
    }

    @Test @MainActor func goldTitleUsesItsSungColourNotTheClassicRed() {
        let gold = OverlaySettings.defaults.with(\.preset, .gold).with(\.style, StylePreset.gold.style)
        let img = render(.title, settings: gold)
        #expect(img.count(of: goldSung, inRowsFromBottom: titleRows(img)) > 0)
        #expect(img.count(of: redTitle, inRowsFromBottom: 0...img.height) == 0)
    }

    @Test @MainActor func countdownDraws() {
        #expect(render(.countdown(upcoming: 0, stars: 3)).maxAlpha > 0)
    }

    @Test @MainActor func countdownWithBadIndexDrawsNothing() {
        #expect(render(.countdown(upcoming: 9, stars: 3)).maxAlpha == 0)
        #expect(render(.singing(index: 9, sweep: .linear(1))).maxAlpha == 0)
    }

    @Test @MainActor func noticeDrawsOnlyWhenIdle() {
        #expect(render(.idle, notice: "♪ 正在找字幕").maxAlpha > 0)
        #expect(render(.interlude(showBanner: false), notice: "♪ 正在找字幕").maxAlpha == 0)
    }

    @Test @MainActor func singleLineStyleCentersTheLine() throws {
        let settings = OverlaySettings.defaults.with(\.style, StylePreset.quiet.style)
        let image = render(.held(index: 0), settings: settings)
        let columns = try #require(image.visibleColumns)
        let center = Double(columns.lowerBound + columns.upperBound) / 2
        #expect(abs(center - Double(image.width) / 2) < 4)
    }

    @Test @MainActor func twoLineStyleAlignsTheBottomRowRight() throws {
        let image = render(.held(index: 0))
        let columns = try #require(image.visibleColumns)
        let center = (columns.lowerBound + columns.upperBound) / 2
        #expect(center > image.width / 2 + 100)
    }

    @Test @MainActor func longLineStaysInBounds() {
        let img = render(.singing(index: 0, sweep: .linear(1)), line: String(repeating: "長", count: 80))
        #expect(img.touchesLeftOrRightEdge == false)
    }

    @Test func fitterShrinksOnlyWhenNeeded() {
        #expect(TextFitter.fontSize(for: "短", fontName: "PingFangTC-Semibold", preferred: 46, maxWidth: 1000) == 46)
        #expect(TextFitter.fontSize(for: String(repeating: "長", count: 80), fontName: "PingFangTC-Semibold", preferred: 46, maxWidth: 1000) < 46)
    }

    @Test func fitterSurvivesAnUnknownFont() {
        #expect(TextFitter.fontSize(for: "短", fontName: "No Such Font", preferred: 46, maxWidth: 1000) == 46)
    }

    // MARK: Helpers

    private func scale(_ img: RenderedImage) -> Double { Double(img.width) / canvas.width }
    private func creditRows(_ img: RenderedImage) -> ClosedRange<Int> { 0...Int(creditTopPoints * scale(img)) }
    private func titleRows(_ img: RenderedImage) -> ClosedRange<Int> { Int(creditTopPoints * scale(img))...img.height }

    @MainActor private func render(
        _ scene: KaraokeScene,
        line: String = "測試字幕一二三四",
        words: [String]? = nil,
        settings: OverlaySettings = .defaults,
        notice: String? = nil
    ) -> RenderedImage {
        let timings = words?.enumerated().map { WordTiming(text: $1, start: Double($0), duration: 1) }
        let text = words?.joined() ?? line
        let fixture = LyricLine(start: 0, end: 4, holdEnd: 8, text: text, slot: 1, words: timings)
        let content = OverlayContent(
            scene: scene, lines: [fixture], title: "測試歌名", artist: "歌手",
            credits: ["作詞：甲"], notice: notice, usesRedTitle: true
        )
        let view = OverlayView(frame: NSRect(origin: .zero, size: canvas))
        view.settings = settings
        view.content = content
        return RenderedImage(view.snapshot())
    }
}

/// RGBA8 pixels of a snapshot, top row first. Sized in pixels, which may be 2x the view's points.
private struct RenderedImage {
    enum Region { case leftHalfOfLine, rightHalfOfLine }

    private static let tolerance = 8
    private static let midpointMargin = 6
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    init(_ rep: NSBitmapImageRep) {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            if let image = rep.cgImage { context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        }
        pixels = buffer
    }

    var maxAlpha: UInt8 { stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0 }

    var touchesLeftOrRightEdge: Bool {
        (0..<height).contains { alpha(x: 0, y: $0) > 0 || alpha(x: width - 1, y: $0) > 0 }
    }

    /// Columns holding at least one visible pixel, first through last.
    var visibleColumns: ClosedRange<Int>? {
        let visible = (0..<width).filter { x in (0..<height).contains { alpha(x: x, y: $0) > 0 } }
        guard let first = visible.first, let last = visible.last else { return nil }
        return first...last
    }

    func count(of color: (r: Int, g: Int, b: Int), in region: Region) -> Int {
        guard let columns = visibleColumns else { return 0 }
        let mid = (columns.lowerBound + columns.upperBound) / 2
        let range = region == .leftHalfOfLine
            ? columns.lowerBound...(mid - Self.midpointMargin)
            : (mid + Self.midpointMargin)...columns.upperBound
        return range.reduce(0) { total, x in
            total + (0..<height).filter { matches(color, x: x, y: $0) }.count
        }
    }

    /// Matches inside rows counted up from the bottom edge, across the whole width.
    func count(of color: (r: Int, g: Int, b: Int), inRowsFromBottom rows: ClosedRange<Int>) -> Int {
        let top = max(0, height - 1 - rows.upperBound), bottom = min(height - 1, height - 1 - rows.lowerBound)
        guard top <= bottom else { return 0 }
        return (top...bottom).reduce(0) { total, y in
            total + (0..<width).filter { matches(color, x: $0, y: y) }.count
        }
    }

    private func alpha(x: Int, y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }

    private func matches(_ color: (r: Int, g: Int, b: Int), x: Int, y: Int) -> Bool {
        let base = (y * width + x) * 4
        guard pixels[base + 3] == 255 else { return false }
        return abs(Int(pixels[base]) - color.r) <= Self.tolerance
            && abs(Int(pixels[base + 1]) - color.g) <= Self.tolerance
            && abs(Int(pixels[base + 2]) - color.b) <= Self.tolerance
    }
}
