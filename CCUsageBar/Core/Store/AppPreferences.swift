import Foundation

/// How often the app re-runs `/usage` on its own.
nonisolated enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60

    var id: Int { rawValue }
    var seconds: TimeInterval? { self == .off ? nil : TimeInterval(rawValue) * 60 }
    var label: String { self == .off ? "Off" : "Every \(rawValue) min" }
}

/// What the status item shows.
nonisolated enum MenuBarDisplay: String, CaseIterable, Identifiable, Sendable {
    case percentages
    case iconOnly

    var id: String { rawValue }
    var label: String { self == .percentages ? "Icon and percentages" : "Icon only" }
}

/// User preferences, persisted in `UserDefaults` and observed by the whole UI.
@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let refreshInterval = "refreshInterval"
        static let menuBarDisplay = "menuBarDisplay"
        static let notifySession = "notifySession"
        static let notifyWeek = "notifyWeek"
        static let thresholds = "notificationThresholds"
        static let profiles = "profiles"
        static let activeProfile = "activeProfileID"
    }

    private let defaults: UserDefaults

    var refreshInterval: RefreshInterval { didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) } }
    var menuBarDisplay: MenuBarDisplay { didSet { defaults.set(menuBarDisplay.rawValue, forKey: Key.menuBarDisplay) } }
    var notifyOnSession: Bool { didSet { defaults.set(notifyOnSession, forKey: Key.notifySession) } }
    var notifyOnWeek: Bool { didSet { defaults.set(notifyOnWeek, forKey: Key.notifyWeek) } }
    var thresholds: [Int] { didSet { defaults.set(thresholds, forKey: Key.thresholds) } }
    var profiles: [Profile] { didSet { persistProfiles() } }
    var activeProfileID: UUID { didSet { defaults.set(activeProfileID.uuidString, forKey: Key.activeProfile) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshInterval =
            RefreshInterval(rawValue: defaults.object(forKey: Key.refreshInterval) as? Int ?? 5)
            ?? .fiveMinutes
        menuBarDisplay =
            MenuBarDisplay(rawValue: defaults.string(forKey: Key.menuBarDisplay) ?? "")
            ?? .percentages
        notifyOnSession = defaults.object(forKey: Key.notifySession) as? Bool ?? true
        notifyOnWeek = defaults.object(forKey: Key.notifyWeek) as? Bool ?? true
        thresholds = (defaults.array(forKey: Key.thresholds) as? [Int])?.sorted() ?? [80, 95]
        // Resolved in locals first: reading a property back during `init` is not allowed
        // for the observed storage the `@Observable` macro generates.
        let stored = (defaults.data(forKey: Key.profiles))
            .flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        let resolvedProfiles = stored.isEmpty ? [Profile.defaultProfile] : stored
        let storedActive = defaults.string(forKey: Key.activeProfile)
            .flatMap(UUID.init(uuidString:))
        let resolvedActive = resolvedProfiles.contains { $0.id == storedActive }
            ? storedActive! : resolvedProfiles[0].id
        profiles = resolvedProfiles
        activeProfileID = resolvedActive
    }

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles.first ?? .defaultProfile
    }

    /// Notification thresholds are entered as free text; keep them sane and unique.
    func setThresholds(_ values: [Int]) {
        thresholds = Set(values.map { min(max($0, 1), 100) }).sorted()
    }

    func notificationsEnabled(forSectionTitled title: String) -> Bool {
        let lower = title.lowercased()
        if lower.contains("session") { return notifyOnSession }
        if lower.contains("week") { return notifyOnWeek }
        return notifyOnSession || notifyOnWeek
    }

    // MARK: - Profile editing

    func addProfile(_ profile: Profile) {
        profiles.append(profile)
    }

    func removeProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles[0].id }
    }

    func updateProfile(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Key.profiles)
    }
}
