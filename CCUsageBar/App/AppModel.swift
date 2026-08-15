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
    let apify: ApifyRuntime

    private(set) var runtimes: [UUID: ProfileRuntime] = [:]
    private var scheduler: RefreshScheduler?
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "app")

    init(
        preferences: AppPreferences = AppPreferences(),
        history: HistoryStore = HistoryStore(),
        notifications: NotificationService = NotificationService(),
        apify: ApifyRuntime = ApifyRuntime()
    ) {
        self.preferences = preferences
        self.history = history
        self.notifications = notifications
        self.apify = apify
        syncRuntimes()
    }

    // MARK: - Lifecycle

    func start() {
        let scheduler = RefreshScheduler { [weak self] in
            self?.refreshActive()
            self?.refreshApify()
        }
        scheduler.update(interval: preferences.refreshInterval)
        self.scheduler = scheduler
        // Prune first: the first fetch appends to history, and pruning afterwards would
        // race the append and could drop the sample that was just written.
        Task { [weak self] in
            await self?.history.loadAndPrune()
            self?.refreshActive()
            self?.refreshApify()
        }
    }

    func stopAll() {
        scheduler?.invalidate()
        for runtime in runtimes.values { runtime.stop() }
    }

    // MARK: - Profiles

    var activeProfile: Profile { preferences.activeProfile }

    var activeRuntime: ProfileRuntime { runtime(for: activeProfile) }

    /// The active runtime only if it already exists.
    ///
    /// For observers: `activeRuntime` creates a runtime on first read, and creating one
    /// inside `withObservationTracking` mutates `runtimes` from within the very read that
    /// is being tracked.
    var loadedActiveRuntime: ProfileRuntime? { runtimes[preferences.activeProfileID] }

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

    /// Polls Apify (A2).
    ///
    /// A separate task from `refreshActive` on purpose: the two paths share only the
    /// scheduler tick, so a hung PTY cannot delay the Apify figure and a slow or failing
    /// HTTP request cannot delay the Claude one.
    func refreshApify() {
        Task { await refreshApifyNow() }
    }

    func refreshApifyNow() async {
        guard let usage = await apify.refresh() else { return }
        await history.recordApify(usage)
        // Read the window after recording, so a first-ever sample cannot look like a spike:
        // the rule needs two, and the baseline is the oldest sample still in the window.
        let samples = history.apifySamples(
            since: Date().addingTimeInterval(-ApifyRules.spikeWindow))
        await notifications.deliver(apify.alerts(for: usage, samples: samples))
    }

    /// Called when the refresh-interval preference changes.
    func refreshIntervalDidChange() {
        scheduler?.update(interval: preferences.refreshInterval)
    }
}
