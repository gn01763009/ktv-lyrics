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
