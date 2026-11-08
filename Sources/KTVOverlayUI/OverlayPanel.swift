import AppKit

/// A borderless, transparent window that floats above everything and lets clicks through,
/// until move mode is on and the user can drag it.
public final class OverlayPanel: NSPanel {
    private let overlayView: OverlayView
    private var isDragging = false

    /// Called once per drag, when the mouse is released, with the final frame.
    public var onMoved: ((CGRect) -> Void)?

    public var isMoveMode = false {
        didSet {
            guard isMoveMode != oldValue else { return }
            ignoresMouseEvents = !isMoveMode
            overlayView.showsMoveFrame = isMoveMode
            if !isMoveMode { isDragging = false }
        }
    }

    public init(contentRect: CGRect, view: OverlayView) {
        overlayView = view
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        view.frame = CGRect(origin: .zero, size: contentRect.size)
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// The panel is mostly transparent, and the controller keeps the visible text inside the screen.
    /// So macOS must not pull the panel back when it hangs past an edge.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Moves the panel by `delta` points (screen coordinates). Does nothing outside move mode.
    func dragBy(_ delta: CGSize) {
        guard isMoveMode else { return }
        isDragging = true
        setFrameOrigin(CGPoint(x: frame.origin.x + delta.width, y: frame.origin.y + delta.height))
    }

    /// Ends a drag and reports the final frame. Does nothing if no drag happened.
    func endDrag() {
        guard isMoveMode, isDragging else { return }
        isDragging = false
        onMoved?(frame)
    }
}
