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

    mutating func markDelivered(_ keys: [String], at date: Date = Date()) {
        for key in keys { deliveredAt[key] = date }
    }

    mutating func prune(now: Date = Date(), retention: TimeInterval = retention) {
        let cutoff = now.addingTimeInterval(-retention)
        deliveredAt = deliveredAt.filter { $0.value >= cutoff }
    }
}
