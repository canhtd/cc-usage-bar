import Foundation

/// Where a recorded sample came from.
nonisolated enum HistorySource: String, Codable, Sendable {
    case claude
    case apify
}

/// One recorded reading: a Claude section percentage, or an Apify monthly spend.
nonisolated struct HistorySample: Codable, Hashable, Sendable, Identifiable {
    var timestamp: Date
    var profileID: UUID
    var sectionKey: String
    var sectionTitle: String
    var percentUsed: Int
    var resetsAt: Date?
    var source: HistorySource
    /// Dollars, for Apify samples. `nil` for Claude, which has no cost figure.
    var amountUsd: Double?

    var id: String { "\(profileID.uuidString)|\(sectionKey)|\(timestamp.timeIntervalSince1970)" }

    init(timestamp: Date, profileID: UUID, section: UsageSection) {
        self.timestamp = timestamp
        self.profileID = profileID
        self.sectionKey = section.storageKey
        self.sectionTitle = section.title
        self.percentUsed = section.percentUsed
        self.resetsAt = section.resetsAt
        self.source = .claude
        self.amountUsd = nil
    }

    init(apify usage: ApifyUsage) {
        self.timestamp = usage.capturedAt
        self.profileID = Self.apifyProfileID
        self.sectionKey = Self.apifySectionKey
        self.sectionTitle = "Apify"
        self.percentUsed = usage.percentUsed ?? 0
        self.resetsAt = usage.cycleEndAt
        self.source = .apify
        self.amountUsd = usage.monthlyUsageUsd
    }

    /// Apify spend is account-wide, so it is filed under a fixed pseudo-profile rather
    /// than under whichever Claude profile happened to be active. Deliberately unlike
    /// `Profile.defaultID`, which shares a prefix with every other profile: a reader
    /// skimming `history.jsonl` should not have to compare the last three characters.
    static let apifyProfileID = UUID(uuidString: "A91F0000-0000-4000-8000-000000000001")!
    static let apifySectionKey = "apify|monthly-usage"

    // Written before the Apify module existed, so both new keys have to be optional on
    // the way in: an old history file must keep loading rather than losing every sample.
    private enum CodingKeys: String, CodingKey {
        case timestamp, profileID, sectionKey, sectionTitle, percentUsed, resetsAt
        case source, amountUsd
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        sectionKey = try container.decode(String.self, forKey: .sectionKey)
        sectionTitle = try container.decode(String.self, forKey: .sectionTitle)
        percentUsed = try container.decode(Int.self, forKey: .percentUsed)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        source = try container.decodeIfPresent(HistorySource.self, forKey: .source) ?? .claude
        amountUsd = try container.decodeIfPresent(Double.self, forKey: .amountUsd)
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

    /// Apify spend readings within a window, oldest first, as the spike rule wants them.
    static func apifySamples(_ samples: [HistorySample], since: Date) -> [ApifySample] {
        samples
            .filter { $0.source == .apify && $0.timestamp >= since }
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { sample in
                sample.amountUsd.map {
                    ApifySample(timestamp: sample.timestamp, monthlyUsageUsd: $0)
                }
            }
    }
}
