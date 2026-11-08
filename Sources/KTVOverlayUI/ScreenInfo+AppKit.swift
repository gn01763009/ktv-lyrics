import AppKit
import KTVCore

extension ScreenInfo {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    /// The placement maths' view of `screen`. Nil when AppKit gives the screen no number.
    init?(_ screen: NSScreen) {
        guard let number = screen.deviceDescription[Self.screenNumberKey] as? NSNumber else { return nil }
        self.init(id: number.stringValue, frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    static var connected: [ScreenInfo] {
        NSScreen.screens.compactMap(ScreenInfo.init)
    }
}
