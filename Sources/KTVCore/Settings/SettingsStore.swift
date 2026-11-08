import Foundation
import os

/// Loads and saves the overlay settings as one value.
public protocol SettingsStoring: Sendable {
    func load() -> OverlaySettings
    func save(_ settings: OverlaySettings)
}

/// Keeps the settings as JSON `Data` under `storageKey` in a `UserDefaults` suite.
public struct UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    public static let storageKey = "overlaySettings.v1"

    private static let logger = Logger(subsystem: "KTVLyrics", category: "SettingsStore")

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored settings, or `.defaults` when nothing is stored or the data cannot be decoded.
    public func load() -> OverlaySettings {
        guard let data = defaults.data(forKey: Self.storageKey) else { return .defaults }
        do {
            return try JSONDecoder().decode(OverlaySettings.self, from: data)
        } catch {
            Self.logger.error("Ignoring unreadable overlay settings: \(error.localizedDescription, privacy: .public)")
            return .defaults
        }
    }

    /// Stores the settings. An encoding failure is logged and the stored value is left as it was.
    public func save(_ settings: OverlaySettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            Self.logger.error("Could not encode overlay settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
