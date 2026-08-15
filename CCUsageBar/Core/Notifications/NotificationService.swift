import Foundation
import OSLog
import UserNotifications

/// Delivers threshold notifications and persists which ones have already fired.
///
/// Authorisation is requested lazily -- the first time a section is actually about to
/// notify -- so a user who never enables notifications is never prompted.
@MainActor
@Observable
final class NotificationService {
    private(set) var tracker = ThresholdTracker()
    private(set) var ledger = AlertLedger()
    private var didRequestAuthorization = false
    private let storeURL: URL
    private let ledgerURL: URL
    private let center: UNUserNotificationCenter?
    private let router = NotificationRouter()
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "notifications")

    init(
        storeURL: URL = AppSupport.file("thresholds.json"),
        ledgerURL: URL = AppSupport.file("alerts.json")
    ) {
        self.storeURL = storeURL
        self.ledgerURL = ledgerURL
        // A unit-test host has no bundle identity; UNUserNotificationCenter would trap.
        center = Bundle.main.bundleIdentifier == nil ? nil : .current()
        if let data = try? Data(contentsOf: storeURL),
            let decoded = try? JSONDecoder().decode(ThresholdTracker.self, from: data) {
            tracker = decoded
        }
        if let data = try? Data(contentsOf: ledgerURL),
            let decoded = try? JSONDecoder().decode(AlertLedger.self, from: data) {
            ledger = decoded
        }
        center?.delegate = router
    }

    /// Evaluates a snapshot and posts one notification per new crossing.
    ///
    /// A crossing is recorded only once the notification centre has accepted it. Marking
    /// first would mean that the very first crossing -- the one that triggers the
    /// permission prompt, before the user has answered it -- is silently consumed and
    /// never shown again for that reset window.
    func process(
        snapshot: UsageSnapshot, profile: Profile, preferences: AppPreferences
    ) async {
        tracker.prune(snapshot: snapshot, profileID: profile.id)
        let events = tracker.pendingEvents(
            snapshot: snapshot, profileID: profile.id, profileName: profile.shortName,
            thresholds: preferences.thresholds,
            isEnabled: { preferences.notificationsEnabled(forSectionTitled: $0.title) })
        guard !events.isEmpty, await ensureAuthorized() else { return persist() }

        var delivered: [ThresholdEvent] = []
        for event in events where await post(event) { delivered.append(event) }
        tracker.markDelivered(delivered)
        persist()
    }

    /// Delivers keyed alerts from the Apify rules (A3).
    ///
    /// Same deliver-then-mark order as `process`: a key is remembered only once the
    /// notification centre has accepted it, so the crossing that triggers the permission
    /// prompt is not consumed while the prompt is still on screen.
    func deliver(_ alerts: [PendingAlert]) async {
        ledger.prune()
        let fresh = ledger.pending(alerts)
        guard !fresh.isEmpty, await ensureAuthorized() else { return persistLedger() }

        var delivered: [String] = []
        for alert in fresh where await post(alert) { delivered.append(alert.key) }
        ledger.markDelivered(delivered)
        persistLedger()
    }

    /// Asks for permission the first time it is needed; later calls just read the status.
    @discardableResult
    func ensureAuthorized() async -> Bool {
        guard let center else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            guard !didRequestAuthorization else { return false }
            didRequestAuthorization = true
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                log.error("authorisation failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    /// Returns whether the notification centre accepted the alert.
    private func post(_ event: ThresholdEvent) async -> Bool {
        guard let center else { return false }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            log.error("could not post notification: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Returns whether the notification centre accepted the alert.
    private func post(_ alert: PendingAlert) async -> Bool {
        guard let center else { return false }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        // Validated again on the way out, in `NotificationRouter.open`.
        if let url = alert.url, NotificationRouter.isOpenable(url) {
            content.userInfo = [NotificationRouter.urlKey: url.absoluteString]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch {
            log.error("could not post alert: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func persistLedger() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? data.write(to: ledgerURL, options: .atomic)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tracker) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
