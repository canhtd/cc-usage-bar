import Foundation

/// One notification the app wants to deliver, with the identity that keeps it from
/// firing twice.
///
/// Shared by the Claude threshold rules and the Apify rules so both go through the same
/// deliver-then-mark path in `NotificationService`: a crossing is recorded only once the
/// notification centre has accepted it, never before.
nonisolated struct PendingAlert: Hashable, Sendable {
    /// Stable identity, e.g. `apify|budget|<cycleStart>|80`. Recorded on delivery.
    var key: String
    var title: String
    var body: String
    /// Opened when the user clicks the notification.
    ///
    /// The only URLs this app ever opens are Apify console run pages; `NotificationService`
    /// re-checks the host before handing anything to `NSWorkspace`.
    var url: URL?
}
