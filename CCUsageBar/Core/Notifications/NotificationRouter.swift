import AppKit
import Foundation
import OSLog
import UserNotifications

/// Handles clicks on delivered notifications.
///
/// Opening a URL is the only outbound action this app can take besides its allowlisted
/// Apify requests, so the host is checked here as well: the notification payload is data
/// that came, however indirectly, from a server response, and `NSWorkspace.open` will
/// launch anything -- including a `file://` or a custom scheme registered by another app.
/// Only `https://console.apify.com/...` is ever opened (A3/R-A3).
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let urlKey = "ccusagebar.alertURL"
    nonisolated static let allowedHost = "console.apify.com"

    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "notifications")

    /// Whether this URL may be handed to `NSWorkspace`. Pure, so it is unit-tested.
    nonisolated static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), host == allowedHost else { return false }
        // Symmetric with `ApifyEndpoint.validate`: a non-default port is a different
        // endpoint, whatever the host says.
        guard url.port == nil || url.port == 443 else { return false }
        return url.user == nil && url.password == nil
    }

    func open(_ url: URL) {
        guard Self.isOpenable(url) else {
            log.error("refused to open a notification URL outside \(Self.allowedHost, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let text = response.notification.request.content.userInfo[Self.urlKey] as? String,
            let url = URL(string: text)
        else { return }
        open(url)
    }

    /// Menu-bar apps are usually frontmost-less; without this the banner is swallowed when
    /// the app happens to be active.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
