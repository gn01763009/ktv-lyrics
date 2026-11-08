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
public enum PanelPlacement {
    /// The panel frame for `settings`, clamped to stay inside the chosen screen's visible area.
    /// The saved display is used when present, otherwise the first screen. With no screens the frame sits at the origin.
    public static func frame(settings: OverlaySettings, contentSize: CGSize, screens: [ScreenInfo]) -> CGRect {
        guard let screen = screens.first(where: { $0.id == settings.displayID }) ?? screens.first else {
            return CGRect(origin: .zero, size: contentSize)
        }
        let area = screen.visibleFrame
        // Re-clamped here because a decoded anchor skips the initializer's clamp.
        let anchor = NormalizedPoint(x: settings.anchor.x, y: settings.anchor.y)
        let originX = area.minX + CGFloat(anchor.x) * area.width - contentSize.width / 2
        let originY = area.minY + CGFloat(anchor.y) * area.height
        return CGRect(
            x: clampedOrigin(originX, length: contentSize.width, in: area.minX, extent: area.width),
            y: clampedOrigin(originY, length: contentSize.height, in: area.minY, extent: area.height),
            width: contentSize.width,
            height: contentSize.height
        )
    }

    /// The anchor that places `frame` on `screen`. Coordinates are measured from the visible area's origin.
    public static func anchor(for frame: CGRect, on screen: ScreenInfo) -> NormalizedPoint {
        let area = screen.visibleFrame
        return NormalizedPoint(
            x: fraction(frame.midX - area.minX, of: area.width),
            y: fraction(frame.minY - area.minY, of: area.height)
        )
    }

    /// Keeps a span of `length` inside `[start, start + extent]`. A span longer than the extent aligns to `start`.
    private static func clampedOrigin(_ origin: CGFloat, length: CGFloat, in start: CGFloat, extent: CGFloat) -> CGFloat {
        if length >= extent { return start }
        return min(max(origin, start), start + extent - length)
    }

    private static func fraction(_ offset: CGFloat, of extent: CGFloat) -> Double {
        guard extent > 0 else { return 0 }
        return Double(offset / extent)
    }
}
