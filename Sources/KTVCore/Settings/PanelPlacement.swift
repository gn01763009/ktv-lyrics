import CoreGraphics

/// A display as the placement maths sees it. `id` identifies it for `OverlaySettings.displayID`.
public struct ScreenInfo: Equatable, Sendable {
    public let id: String
    public let frame, visibleFrame: CGRect

    public init(id: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Converts between the saved anchor and the panel's frame on a screen.
///
/// The panel is a wide transparent window, but only the text block inside it is visible. The block is what
/// is kept on screen, so the anchor can reach every edge. The transparent panel may hang past the screen edge.
public enum PanelPlacement {
    /// The visible block is this many font sizes wide, matching the renderer's minimum box width.
    private static let blockWidthEms: CGFloat = 12.5
    /// The visible block is this many font sizes tall: two lyric rows and their margin.
    private static let blockHeightEms: CGFloat = 3

    /// The size of the visible text block for `settings`, never wider than the panel itself.
    public static func textBlockSize(settings: OverlaySettings, contentWidth: CGFloat) -> CGSize {
        let fontSize = CGFloat(settings.size * settings.style.scale)
        return CGSize(width: min(contentWidth, fontSize * blockWidthEms), height: fontSize * blockHeightEms)
    }

    /// The panel frame for `settings`. The text block stays inside the chosen screen's visible area:
    /// `frame.midX` within `[minX + blockWidth / 2, maxX - blockWidth / 2]` and `frame.minY` within
    /// `[minY, maxY - blockHeight]`. The panel itself may extend past the edge.
    /// The saved display is used when present, otherwise the first screen. With no screens the frame sits at the origin.
    public static func frame(settings: OverlaySettings, contentSize: CGSize, screens: [ScreenInfo]) -> CGRect {
        guard let screen = screens.first(where: { $0.id == settings.displayID }) ?? screens.first else {
            return CGRect(origin: .zero, size: contentSize)
        }
        let area = screen.visibleFrame
        let block = textBlockSize(settings: settings, contentWidth: contentSize.width)
        // Re-clamped here because a decoded anchor skips the initializer's clamp.
        let anchor = NormalizedPoint(x: settings.anchor.x, y: settings.anchor.y)
        let midX = clamped(
            area.minX + CGFloat(anchor.x) * area.width,
            lower: area.minX + block.width / 2, upper: area.maxX - block.width / 2, fallback: area.midX
        )
        let minY = clamped(
            area.minY + CGFloat(anchor.y) * area.height,
            lower: area.minY, upper: area.maxY - block.height, fallback: area.minY
        )
        return CGRect(x: midX - contentSize.width / 2, y: minY, width: contentSize.width, height: contentSize.height)
    }

    /// The anchor that places `frame` on `screen`. Coordinates are measured from the visible area's origin.
    public static func anchor(for frame: CGRect, on screen: ScreenInfo) -> NormalizedPoint {
        let area = screen.visibleFrame
        return NormalizedPoint(
            x: fraction(frame.midX - area.minX, of: area.width),
            y: fraction(frame.minY - area.minY, of: area.height)
        )
    }

    /// `value` limited to `lower...upper`. When the range is empty (the block is larger than the screen), `fallback`.
    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat, fallback: CGFloat) -> CGFloat {
        guard lower <= upper else { return fallback }
        return min(max(value, lower), upper)
    }

    private static func fraction(_ offset: CGFloat, of extent: CGFloat) -> Double {
        guard extent > 0 else { return 0 }
        return Double(offset / extent)
    }
}
