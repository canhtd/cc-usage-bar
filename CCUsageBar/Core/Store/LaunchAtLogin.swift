import Foundation
import OSLog
import ServiceManagement

/// Thin wrapper over `SMAppService` so the settings toggle stays declarative.
@MainActor
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.danny.ccusagebar", category: "login-item")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the status actually achieved, so the UI can fall back if the user declined.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled
    }

    /// True when macOS is holding the request for the user to approve in System Settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
