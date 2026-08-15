import Foundation

/// A threshold crossing worth telling the user about.
nonisolated struct ThresholdEvent: Hashable, Sendable {
    var profileID: UUID
    var profileName: String
    var sectionTitle: String
    var threshold: Int
    var percentUsed: Int
    /// Identity in the fired set, carried on the event so delivery can mark exactly the
    /// alerts that actually reached the user.
    var key: String

    var title: String { "\(sectionTitle) at \(percentUsed)%" }
    var body: String {
        "\(profileName): usage has passed \(threshold)% for \(sectionTitle.lowercased())."
    }
}

/// Decides which threshold notifications to fire, exactly once per reset window.
///
/// Pure and persistable: the whole decision is a set-membership test, so it is unit-tested
/// without a notification centre, and the fired set survives relaunches on disk.
///
/// Deciding and recording are separate calls on purpose. Recording a crossing before the
/// notification has been accepted means an alert lost to a denied permission prompt or a
/// failed `add` is lost for the entire reset window -- the user never hears about the 95%
/// they were meant to hear about.
nonisolated struct ThresholdTracker: Codable, Sendable, Equatable {
    /// Keys of notifications already delivered, as `profile|section|window|threshold`.
    private(set) var fired: Set<String> = []

    init(fired: Set<String> = []) {
        self.fired = fired
    }

    /// Identity of the current reset window for a section; a new window re-arms the alerts.
    static func windowKey(for section: UsageSection) -> String {
        if let resetsAt = section.resetsAt {
            return String(Int(resetsAt.timeIntervalSince1970.rounded()))
        }
        return section.resetsText ?? "unknown"
    }

    static func key(profileID: UUID, section: UsageSection, threshold: Int) -> String {
        "\(profileID.uuidString)|\(section.storageKey)|\(windowKey(for: section))|\(threshold)"
    }

    /// Forgets this profile's keys that no longer describe anything in the snapshot --
    /// a reset window that has rolled over, or a section Claude Code stopped reporting.
    /// Other profiles are left alone; they prune themselves when they next report.
    mutating func prune(snapshot: UsageSnapshot, profileID: UUID) {
        let profilePrefix = "\(profileID.uuidString)|"
        let live = Set(
            snapshot.sections.map {
                "\(profilePrefix)\($0.storageKey)|\(Self.windowKey(for: $0))|"
            })
        fired = fired.filter { key in
            guard key.hasPrefix(profilePrefix) else { return true }
            return live.contains { key.hasPrefix($0) }
        }
    }

    /// The crossings that have not been delivered yet. Does not record anything.
    ///
    /// `isEnabled` lets the caller switch sections off without the tracker knowing about
    /// section names. Thresholds are evaluated highest-first so a jump from 10% to 97%
    /// reports the most severe crossing first.
    func pendingEvents(
        snapshot: UsageSnapshot,
        profileID: UUID,
        profileName: String,
        thresholds: [Int],
        isEnabled: (UsageSection) -> Bool
    ) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        for section in snapshot.sections where isEnabled(section) {
            for threshold in thresholds.sorted(by: >) where section.percentUsed >= threshold {
                let key = Self.key(profileID: profileID, section: section, threshold: threshold)
                guard !fired.contains(key) else { continue }
                events.append(
                    ThresholdEvent(
                        profileID: profileID, profileName: profileName,
                        sectionTitle: section.title, threshold: threshold,
                        percentUsed: section.percentUsed, key: key))
            }
        }
        return events
    }

    /// Records the alerts the user actually received, so they never fire twice.
    mutating func markDelivered(_ events: [ThresholdEvent]) {
        for event in events { fired.insert(event.key) }
    }

    /// Prune, decide and record in one step, for callers that always deliver.
    @discardableResult
    mutating func evaluate(
        snapshot: UsageSnapshot,
        profileID: UUID,
        profileName: String,
        thresholds: [Int],
        isEnabled: (UsageSection) -> Bool
    ) -> [ThresholdEvent] {
        prune(snapshot: snapshot, profileID: profileID)
        let events = pendingEvents(
            snapshot: snapshot, profileID: profileID, profileName: profileName,
            thresholds: thresholds, isEnabled: isEnabled)
        markDelivered(events)
        return events
    }
}
