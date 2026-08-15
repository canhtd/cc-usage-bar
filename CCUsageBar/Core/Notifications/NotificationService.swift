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
    private var didRequestAuthorization = false
    private let storeURL: URL
    private let center: UNUserNotificationCenter?
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "notifications")

    init(storeURL: URL = AppSupport.file("thresholds.json")) {
        self.storeURL = storeURL
        // A unit-test host has no bundle identity; UNUserNotificationCenter would trap.
        center = Bundle.main.bundleIdentifier == nil ? nil : .current()
        if let data = try? Data(contentsOf: storeURL),
            let decoded = try? JSONDecoder().decode(ThresholdTracker.self, from: data) {
            tracker = decoded
        }
    }

    /// Evaluates a snapshot and posts one notification per new crossing.
    func process(
        snapshot: UsageSnapshot, profile: Profile, preferences: AppPreferences
    ) async {
        let events = tracker.evaluate(
            snapshot: snapshot, profileID: profile.id, profileName: profile.shortName,
            thresholds: preferences.thresholds,
            isEnabled: { preferences.notificationsEnabled(forSectionTitled: $0.title) })
        persist()
        guard !events.isEmpty, await ensureAuthorized() else { return }
        for event in events { await post(event) }
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

    private func post(_ event: ThresholdEvent) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tracker) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
