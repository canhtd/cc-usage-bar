import Foundation

/// Remembers which keyed alerts have already been delivered.
///
/// `ThresholdTracker` does the same job for Claude sections, but its state is shaped around
/// profiles, sections and reset windows. The Apify rules produce free-form keys instead --
/// a billing cycle, an hour bucket, a run id -- so they need a plain key ledger.
///
/// Keys are stored with their delivery time so the ledger can be pruned. Without that, the
/// expensive-run rule would grow it by one entry per run, forever.
nonisolated struct AlertLedger: Codable, Equatable, Sendable {
    /// Long enough that a monthly billing-cycle key cannot be forgotten and re-fire while
    /// the cycle it names is still current.
    static let retention: TimeInterval = 45 * 24 * 3600

    private(set) var deliveredAt: [String: Date] = [:]

    init(deliveredAt: [String: Date] = [:]) {
        self.deliveredAt = deliveredAt
    }

    func contains(_ key: String) -> Bool { deliveredAt[key] != nil }

    /// The alerts that have not fired yet, in the order the rules produced them.
    func pending(_ alerts: [PendingAlert]) -> [PendingAlert] {
        alerts.filter { !contains($0.key) }
    }

    /// The most recent delivery time among keys starting with `prefix`.
    ///
    /// Lets a rule rate-limit itself on real elapsed time rather than on key identity --
    /// see the spike rule, whose key changes on the wall-clock hour.
    func lastDelivery(withPrefix prefix: String) -> Date? {
        deliveredAt.filter { $0.key.hasPrefix(prefix) }.values.max()
    }

    /// Splits pending alerts into the ones to post and the ones a higher-priority alert in
    /// the same group has superseded.
    ///
    /// Order carries the priority: the rules emit the most important member of a group
    /// first. Pure, so the policy is testable without a notification centre.
    static func partition(
        _ alerts: [PendingAlert]
    ) -> (post: [PendingAlert], superseded: [PendingAlert]) {
        var post: [PendingAlert] = []
        var superseded: [PendingAlert] = []
        var claimed: Set<String> = []
        for alert in alerts {
            guard let group = alert.group else {
                post.append(alert)
                continue
            }
            if claimed.insert(group).inserted {
                post.append(alert)
            } else {
                superseded.append(alert)
            }
        }
        return (post, superseded)
    }

    mutating func markDelivered(_ keys: [String], at date: Date = Date()) {
        for key in keys { deliveredAt[key] = date }
    }

    mutating func prune(now: Date = Date(), retention: TimeInterval = retention) {
        let cutoff = now.addingTimeInterval(-retention)
        deliveredAt = deliveredAt.filter { $0.value >= cutoff }
    }
}
