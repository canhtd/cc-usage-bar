import AppKit
import Foundation
import OSLog

/// The single owner of app state: preferences, per-profile runtimes, history, notifications.
///
/// Views and the status item read from here; nothing else holds mutable app state.
@MainActor
@Observable
final class AppModel {
    let preferences: AppPreferences
    let history: HistoryStore
    let notifications: NotificationService

    private(set) var runtimes: [UUID: ProfileRuntime] = [:]
    private var scheduler: RefreshScheduler?
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "app")

    init(
        preferences: AppPreferences = AppPreferences(),
        history: HistoryStore = HistoryStore(),
        notifications: NotificationService = NotificationService()
    ) {
        self.preferences = preferences
        self.history = history
        self.notifications = notifications
        syncRuntimes()
    }

    // MARK: - Lifecycle

    func start() {
        Task { await history.loadAndPrune() }
        let scheduler = RefreshScheduler { [weak self] in self?.refreshActive() }
        scheduler.update(interval: preferences.refreshInterval)
        self.scheduler = scheduler
        refreshActive()
    }

    func stopAll() {
        scheduler?.invalidate()
        for runtime in runtimes.values { runtime.stop() }
    }

    // MARK: - Profiles

    var activeProfile: Profile { preferences.activeProfile }

    var activeRuntime: ProfileRuntime { runtime(for: activeProfile) }

    /// Looks up a runtime, creating it on first use.
    ///
    /// Deliberately does not push edited profile values into an existing runtime: this is
    /// read from view bodies, and mutating observable state while SwiftUI is rendering is
    /// how update loops start. Edits arrive through `syncRuntimes()` instead.
    func runtime(for profile: Profile) -> ProfileRuntime {
        if let existing = runtimes[profile.id] { return existing }
        let runtime = ProfileRuntime(profile: profile)
        runtimes[profile.id] = runtime
        return runtime
    }

    /// Applies profile edits, creates runtimes for new profiles, and tears down sessions
    /// for deleted ones. Called from the settings UI, never from a view body.
    func syncRuntimes() {
        let live = Set(preferences.profiles.map(\.id))
        for (id, runtime) in runtimes where !live.contains(id) {
            runtime.stop()
            runtimes.removeValue(forKey: id)
        }
        for profile in preferences.profiles {
            runtime(for: profile).apply(profile)
        }
    }

    func selectProfile(id: UUID) {
        guard preferences.activeProfileID != id else { return }
        preferences.activeProfileID = id
        if activeRuntime.snapshot == nil { refreshActive() }
    }

    // MARK: - Refreshing

    func refreshActive() {
        let profile = activeProfile
        Task { await refresh(profile: profile) }
    }

    func refresh(profile: Profile) async {
        let runtime = runtime(for: profile)
        guard let snapshot = await runtime.refresh() else { return }
        await history.record(snapshot, profileID: profile.id)
        await notifications.process(
            snapshot: snapshot, profile: profile, preferences: preferences)
    }

    /// Called when the refresh-interval preference changes.
    func refreshIntervalDidChange() {
        scheduler?.update(interval: preferences.refreshInterval)
    }
}
