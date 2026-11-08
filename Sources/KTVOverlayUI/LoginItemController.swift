import Foundation
import ServiceManagement

/// Turns "open at login" on or off.
public protocol LoginItemControlling {
    /// Throws a `LocalizedError` whose description is shown to the user.
    func setEnabled(_ enabled: Bool) throws
}

/// Why the system did not accept the login item.
enum LoginItemError: LocalizedError {
    case requiresApproval
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval: return "需要先到「系統設定 › 一般 › 登入項目」允許 KTV Lyrics"
        case .failed(let reason): return "無法設定開機啟動：\(reason)"
        }
    }
}

/// `SMAppService.mainApp`: registers this app as a login item.
public struct LoginItemController: LoginItemControlling {
    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            throw LoginItemError.failed(error.localizedDescription)
        }
        if enabled, service.status == .requiresApproval { throw LoginItemError.requiresApproval }
    }
}
