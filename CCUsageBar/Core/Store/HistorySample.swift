import Foundation

/// One recorded percentage for one section of one profile.
nonisolated struct HistorySample: Codable, Hashable, Sendable, Identifiable {
    var timestamp: Date
    var profileID: UUID
    var sectionKey: String
    var sectionTitle: String
    var percentUsed: Int
    var resetsAt: Date?

    var id: String { "\(profileID.uuidString)|\(sectionKey)|\(timestamp.timeIntervalSince1970)" }

    init(timestamp: Date, profileID: UUID, section: UsageSection) {
        self.timestamp = timestamp
        self.profileID = profileID
        self.sectionKey = section.storageKey
        self.sectionTitle = section.title
        self.percentUsed = section.percentUsed
        self.resetsAt = section.resetsAt
    }
}

/// Retention policy, kept pure so it can be tested without touching the disk.
nonisolated enum HistoryRetention {
    static let days = 30

    static var interval: TimeInterval { TimeInterval(days) * 24 * 3600 }

    /// Drops samples older than the retention window and returns them in time order.
    static func prune(
        _ samples: [HistorySample], now: Date = Date(), retention: TimeInterval = interval
    ) -> [HistorySample] {
        let cutoff = now.addingTimeInterval(-retention)
        return samples.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Samples for one section of one profile within a window, oldest first.
    static func series(
        _ samples: [HistorySample], profileID: UUID, sectionKey: String, since: Date
    ) -> [HistorySample] {
        samples
            .filter {
                $0.profileID == profileID && $0.sectionKey == sectionKey && $0.timestamp >= since
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
