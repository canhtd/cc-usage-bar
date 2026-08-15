import Foundation

/// A threshold crossing worth telling the user about.
nonisolated struct ThresholdEvent: Hashable, Sendable {
    var profileID: UUID
    var profileName: String
    var sectionTitle: String
    var threshold: Int
    var percentUsed: Int

    var title: String { "\(sectionTitle) at \(percentUsed)%" }
    var body: String {
        "\(profileName): usage has passed \(threshold)% for \(sectionTitle.lowercased())."
    }
}

/// Decides which threshold notifications to fire, exactly once per reset window.
///
/// Pure and persistable: the whole decision is a set-membership test, so it is unit-tested
/// without a notification centre, and the fired set survives relaunches on disk.
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

    /// Returns the crossings to notify about and marks them as delivered.
    ///
    /// `isEnabled` lets the caller switch sections off without the tracker knowing about
    /// section names. Thresholds are evaluated highest-first so a jump from 10% to 97%
    /// reports the most severe crossing first.
    mutating func evaluate(
        snapshot: UsageSnapshot,
        profileID: UUID,
        profileName: String,
        thresholds: [Int],
        isEnabled: (UsageSection) -> Bool
    ) -> [ThresholdEvent] {
        var events: [ThresholdEvent] = []
        for section in snapshot.sections {
            dropStaleKeys(profileID: profileID, section: section)
            guard isEnabled(section) else { continue }
            for threshold in thresholds.sorted(by: >) where section.percentUsed >= threshold {
                let key = Self.key(profileID: profileID, section: section, threshold: threshold)
                guard !fired.contains(key) else { continue }
                fired.insert(key)
                events.append(
                    ThresholdEvent(
                        profileID: profileID, profileName: profileName,
                        sectionTitle: section.title, threshold: threshold,
                        percentUsed: section.percentUsed))
            }
        }
        return events
    }

    /// Forgets keys for a section whose reset window has rolled over, keeping the set small.
    private mutating func dropStaleKeys(profileID: UUID, section: UsageSection) {
        let prefix = "\(profileID.uuidString)|\(section.storageKey)|"
        let current = prefix + Self.windowKey(for: section) + "|"
        fired = fired.filter { !$0.hasPrefix(prefix) || $0.hasPrefix(current) }
    }
}
