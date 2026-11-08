import Carbon.HIToolbox
import os

/// A global hot key. Carbon's RegisterEventHotKey needs no accessibility permission.
public final class HotKeyCenter {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "HotKeyCenter")
    private static let signature: OSType = 0x4B54_564C  // 'KTVL'

    /// Default combination: control + option + K.
    public static let defaultKeyCode = UInt32(kVK_ANSI_K)
    public static let defaultModifiers = UInt32(controlKey | optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void

    /// Returns nil, and logs why, when the system refuses the registration.
    public init?(
        keyCode: UInt32 = HotKeyCenter.defaultKeyCode,
        modifiers: UInt32 = HotKeyCenter.defaultModifiers,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        guard installHandler(), registerHotKey(keyCode: keyCode, modifiers: modifiers) else {
            removeHandler()
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        removeHandler()
    }

    private func installHandler() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().handler()
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        if status != noErr { Self.logger.error("InstallEventHandler failed, status \(status, privacy: .public)") }
        return status == noErr
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let status = RegisterEventHotKey(
            keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status != noErr {
            Self.logger.error("RegisterEventHotKey failed, status \(status, privacy: .public)")
        }
        return status == noErr
    }

    private func removeHandler() {
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }
}
