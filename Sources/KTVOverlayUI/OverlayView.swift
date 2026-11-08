import AppKit
import KTVCore
import os

/// A transparent view that draws the karaoke subtitles.
public final class OverlayView: NSView {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "OverlayView")

    public var content: OverlayContent = .empty {
        didSet { if content != oldValue { needsDisplay = true } }
    }

    public var settings: OverlaySettings = .defaults {
        didSet {
            alphaValue = CGFloat(settings.opacity)
            needsDisplay = true
        }
    }

    /// Draws a dashed frame around the view so the user can see what they are dragging.
    public var showsMoveFrame = false {
        didSet { if showsMoveFrame != oldValue { needsDisplay = true } }
    }

    private static let moveFrameColor = RGBAColor(hex: 0x0A84FF).nsColor
    private static let moveFrameInset: CGFloat = 4
    private static let moveFrameLineWidth: CGFloat = 2
    private static let moveFrameDash: [CGFloat] = [8, 6]

    public override var isOpaque: Bool { false }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = CGFloat(settings.opacity)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        alphaValue = CGFloat(settings.opacity)
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        KaraokeRenderer(content: content, settings: settings, canvas: bounds.size).draw()
        if showsMoveFrame { drawMoveFrame() }
    }

    private func drawMoveFrame() {
        let path = NSBezierPath(rect: bounds.insetBy(dx: Self.moveFrameInset, dy: Self.moveFrameInset))
        path.lineWidth = Self.moveFrameLineWidth
        path.setLineDash(Self.moveFrameDash, count: Self.moveFrameDash.count, phase: 0)
        Self.moveFrameColor.setStroke()
        path.stroke()
    }

    // MARK: Dragging (the panel ignores these unless it is in move mode)

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDragged(with event: NSEvent) {
        // Screen coordinates grow upward, event deltas grow downward.
        (window as? OverlayPanel)?.dragBy(CGSize(width: event.deltaX, height: -event.deltaY))
    }

    public override func mouseUp(with event: NSEvent) {
        (window as? OverlayPanel)?.endDrag()
    }

    /// The view as drawn right now, as a bitmap with a transparent background.
    public func snapshot() -> NSBitmapImageRep {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            Self.logger.error("Could not create a snapshot bitmap for bounds \(self.bounds.debugDescription, privacy: .public)")
            return NSBitmapImageRep()
        }
        cacheDisplay(in: bounds, to: rep)
        return rep
    }
}
