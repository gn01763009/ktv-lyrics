import AppKit
import Carbon.HIToolbox
import Testing
@testable import KTVOverlayUI

@Suite struct PanelTests {
    private let startFrame = CGRect(x: 100, y: 200, width: 1200, height: 320)

    @Test @MainActor func panelIsClickThroughByDefault() {
        let p = makePanel()
        #expect(p.ignoresMouseEvents && !p.isOpaque && !p.canBecomeKey && !p.canBecomeMain && p.level == .screenSaver)
        #expect(!p.hasShadow && !p.hidesOnDeactivate && p.backgroundColor == .clear)
        #expect(p.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]))
        #expect(p.styleMask.isSuperset(of: [.borderless, .nonactivatingPanel]))
    }

    @Test @MainActor func moveModeAcceptsMouseThenRestores() {
        let p = makePanel()
        p.isMoveMode = true
        #expect(!p.ignoresMouseEvents)
        p.isMoveMode = false
        #expect(p.ignoresMouseEvents)
    }

    @Test @MainActor func moveModeShowsTheMoveFrame() {
        let view = OverlayView(frame: CGRect(origin: .zero, size: startFrame.size))
        let p = OverlayPanel(contentRect: startFrame, view: view)
        p.isMoveMode = true
        #expect(view.showsMoveFrame)
        p.isMoveMode = false
        #expect(!view.showsMoveFrame)
    }

    @Test @MainActor func movingReportsFrame() {
        let p = makePanel()
        var reported: [CGRect] = []
        p.onMoved = { reported.append($0) }
        p.isMoveMode = true
        p.dragBy(CGSize(width: 30, height: -10))
        p.dragBy(CGSize(width: 5, height: 5))
        #expect(reported.isEmpty)
        p.endDrag()
        let expected = startFrame.offsetBy(dx: 35, dy: -5)
        #expect(reported == [expected])
        #expect(p.frame == expected)
    }

    @Test @MainActor func draggingDoesNothingOutsideMoveMode() {
        let p = makePanel()
        var reported: [CGRect] = []
        p.onMoved = { reported.append($0) }
        p.dragBy(CGSize(width: 30, height: 30))
        p.endDrag()
        #expect(reported.isEmpty)
        #expect(p.frame == startFrame)
    }

    @Test func defaultHotKeyIsControlOptionK() {
        #expect(HotKeyCenter.defaultKeyCode == UInt32(kVK_ANSI_K))
        #expect(HotKeyCenter.defaultModifiers == UInt32(controlKey | optionKey))
    }

    @MainActor private func makePanel() -> OverlayPanel {
        OverlayPanel(contentRect: startFrame, view: OverlayView(frame: CGRect(origin: .zero, size: startFrame.size)))
    }
}
