import Foundation
import KTVCore
import os

/// The settings the window edits. Every change is saved, published and handed to `onChange` once.
@MainActor
public final class SettingsViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "KTVLyrics", category: "SettingsViewModel")

    @Published public private(set) var settings: OverlaySettings
    /// Why the last attempt to change "open at login" failed. Nil when it worked.
    @Published public private(set) var loginItemError: String?

    private let store: any SettingsStoring
    private let loginItem: any LoginItemControlling
    private let onChange: (OverlaySettings) -> Void

    public init(
        store: any SettingsStoring,
        loginItem: any LoginItemControlling = LoginItemController(),
        onChange: @escaping (OverlaySettings) -> Void
    ) {
        self.store = store
        self.loginItem = loginItem
        self.onChange = onChange
        self.settings = store.load()
    }

    /// Switches to a named look. Replaces the whole style, including any tweaks.
    public func selectPreset(_ preset: StylePreset) {
        update { $0.with(\.preset, preset).with(\.style, preset.style) }
    }

    public func update(_ change: (OverlaySettings) -> OverlaySettings) {
        let next = change(settings)
        settings = next
        store.save(next)
        onChange(next)
    }

    /// Registers or removes the login item. On failure the setting stays off and the reason is kept.
    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
            update { $0.with(\.launchAtLogin, enabled) }
        } catch {
            Self.logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            loginItemError = error.localizedDescription
            update { $0.with(\.launchAtLogin, false) }
        }
    }
}
