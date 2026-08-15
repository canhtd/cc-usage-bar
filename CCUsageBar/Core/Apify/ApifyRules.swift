import Foundation

/// The three Apify alert rules (A3), pure so every one of them is unit-tested.
///
/// Each rule returns alerts with a stable key; `NotificationService` drops the ones already
/// delivered and records the rest only after the notification centre accepts them, so a
/// rule may safely report the same crossing on every poll.
nonisolated enum ApifyRules {
    static let defaultBudgetThresholds = [50, 80, 95]
    static let defaultSpikePercent = 10.0
    static let defaultRunCostUsd = 5.0
    /// R-A2 looks at the trailing hour.
    static let spikeWindow: TimeInterval = 3600

    // MARK: - R-A1 budget thresholds

    /// Fires once per threshold per billing cycle.
    static func budgetAlerts(usage: ApifyUsage, thresholds: [Int]) -> [PendingAlert] {
        guard let percent = usage.percentUsed, let max = usage.maxMonthlyUsageUsd else {
            return []
        }
        return thresholds.sorted(by: >)
            .filter { percent >= $0 }
            .map { threshold in
                PendingAlert(
                    key: "apify|budget|\(usage.cycleKey)|\(threshold)",
                    title: "Apify at \(percent)% of budget",
                    body: "\(money(usage.monthlyUsageUsd)) of \(money(max)) used this cycle.")
            }
    }

    // MARK: - R-A2 spike

    /// Fires when spend over the trailing hour is at least `spikePercent` of the budget.
    ///
    /// Keyed by the hour bucket, so a sustained burn alerts once an hour rather than on
    /// every poll. Needs two samples; sparse history is fine, because the baseline is the
    /// oldest sample still inside the window rather than a fixed offset.
    static func spikeAlert(
        usage: ApifyUsage,
        samples: [ApifySample],
        spikePercent: Double,
        now: Date = Date()
    ) -> PendingAlert? {
        guard let max = usage.maxMonthlyUsageUsd, max > 0, spikePercent > 0 else { return nil }
        let window = samples
            .filter { $0.timestamp >= now.addingTimeInterval(-spikeWindow) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let baseline = window.first, window.count >= 2 else { return nil }

        let delta = usage.monthlyUsageUsd - baseline.monthlyUsageUsd
        guard delta > 0 else { return nil }
        let share = delta / max * 100
        guard share >= spikePercent else { return nil }

        let bucket = Int(now.timeIntervalSince1970 / spikeWindow)
        return PendingAlert(
            key: "apify|spike|\(bucket)",
            title: "Apify spend is spiking",
            body: "Apify spent \(money(delta)) in the last hour "
                + "(\(percent(share))% of budget).")
    }

    // MARK: - R-A3 expensive run

    /// Fires once per run id, whether the run is still going or already finished.
    static func expensiveRunAlerts(
        runs: [ApifyRunSummary], minimumUsd: Double
    ) -> [PendingAlert] {
        guard minimumUsd > 0 else { return [] }
        return runs
            .filter { $0.costUsd >= minimumUsd }
            .map { run in
                PendingAlert(
                    key: "apify|run|\(run.id)",
                    title: "Expensive Apify run",
                    body: "\(run.actorName) run cost \(money(run.costUsd)).",
                    url: run.consoleURL)
            }
    }

    // MARK: - Formatting

    static func money(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// One recorded Apify spend reading, as the spike rule sees it.
nonisolated struct ApifySample: Sendable, Equatable {
    var timestamp: Date
    var monthlyUsageUsd: Double
}
