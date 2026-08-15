import Foundation
import Testing

@testable import CCUsageBar

/// The three Apify alert rules (A3), which are pure and therefore fully testable.
@Suite("Apify alert rules")
struct ApifyRulesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func usage(
        spend: Double, cap: Double? = 500, runs: [ApifyRunSummary] = []
    ) -> ApifyUsage {
        ApifyUsage(
            monthlyUsageUsd: spend, maxMonthlyUsageUsd: cap,
            cycleStartAt: now.addingTimeInterval(-10 * 86400),
            cycleEndAt: now.addingTimeInterval(20 * 86400),
            capturedAt: now, runs: runs)
    }

    // MARK: - R-A1 budget

    @Test("every threshold at or below the current percentage fires")
    func budgetThresholds() {
        let alerts = ApifyRules.budgetAlerts(
            usage: usage(spend: 410), thresholds: [50, 80, 95])
        #expect(alerts.count == 2)
        #expect(alerts.map(\.key) == [
            "apify|budget|\(usage(spend: 410).cycleKey)|80",
            "apify|budget|\(usage(spend: 410).cycleKey)|50",
        ])
        #expect(alerts[0].title == "Apify at 82% of budget")
        #expect(alerts[0].body == "$410.00 of $500.00 used this cycle.")
        #expect(alerts[0].url == nil)
    }

    @Test("all crossed thresholds share a group, so only the highest is announced")
    func budgetThresholdsAreGrouped() {
        let alerts = ApifyRules.budgetAlerts(usage: usage(spend: 410), thresholds: [50, 80, 95])
        #expect(Set(alerts.compactMap(\.group)).count == 1)
        let (post, superseded) = AlertLedger.partition(alerts)
        #expect(post.map(\.key) == [alerts[0].key], "only the 80 crossing is posted")
        #expect(superseded.map(\.key) == [alerts[1].key], "the 50 crossing is recorded silently")
    }

    @Test("nothing fires below the lowest threshold")
    func budgetBelowThreshold() {
        #expect(ApifyRules.budgetAlerts(usage: usage(spend: 100), thresholds: [50]).isEmpty)
    }

    @Test("a plan with no cap has no percentage, so the budget rule cannot fire")
    func budgetWithoutCap() {
        #expect(
            ApifyRules.budgetAlerts(usage: usage(spend: 900, cap: nil), thresholds: [50]).isEmpty)
    }

    @Test("the key changes with the billing cycle, so each cycle re-arms")
    func budgetKeyPerCycle() {
        let first = usage(spend: 410)
        var second = first
        second.cycleStartAt = first.cycleStartAt.addingTimeInterval(30 * 86400)
        let a = ApifyRules.budgetAlerts(usage: first, thresholds: [50])
        let b = ApifyRules.budgetAlerts(usage: second, thresholds: [50])
        #expect(a.first?.key != b.first?.key)
    }

    // MARK: - R-A2 spike

    @Test("a jump of at least the configured share of budget within the hour fires")
    func spikeFires() throws {
        let samples = [
            ApifySample(timestamp: now.addingTimeInterval(-3000), monthlyUsageUsd: 100),
            ApifySample(timestamp: now.addingTimeInterval(-600), monthlyUsageUsd: 130),
        ]
        let alert = try #require(
            ApifyRules.spikeAlert(
                usage: usage(spend: 160), samples: samples, spikePercent: 10, now: now))
        #expect(alert.body == "Apify spent $60.00 in the last hour (12.0% of budget).")
        #expect(alert.key == "apify|spike|\(Int(now.timeIntervalSince1970 / 3600))")
    }

    @Test("a jump below the configured share does not fire")
    func spikeBelowThreshold() {
        let samples = [
            ApifySample(timestamp: now.addingTimeInterval(-3000), monthlyUsageUsd: 100),
            ApifySample(timestamp: now.addingTimeInterval(-600), monthlyUsageUsd: 110),
        ]
        #expect(
            ApifyRules.spikeAlert(
                usage: usage(spend: 120), samples: samples, spikePercent: 10, now: now) == nil)
    }

    @Test("one sample is not a trend")
    func spikeNeedsTwoSamples() {
        let samples = [ApifySample(timestamp: now.addingTimeInterval(-600), monthlyUsageUsd: 100)]
        #expect(
            ApifyRules.spikeAlert(
                usage: usage(spend: 400), samples: samples, spikePercent: 10, now: now) == nil)
    }

    @Test("samples older than the window are ignored, so a slow month cannot look like a spike")
    func spikeIgnoresOldSamples() {
        let samples = [
            ApifySample(timestamp: now.addingTimeInterval(-8 * 3600), monthlyUsageUsd: 10),
            ApifySample(timestamp: now.addingTimeInterval(-7 * 3600), monthlyUsageUsd: 20),
            ApifySample(timestamp: now.addingTimeInterval(-300), monthlyUsageUsd: 299),
        ]
        #expect(
            ApifyRules.spikeAlert(
                usage: usage(spend: 300), samples: samples, spikePercent: 10, now: now) == nil)
    }

    @Test("a sparse hour still works: two samples 55 minutes apart are enough")
    func spikeToleratesSparseHistory() throws {
        let samples = [
            ApifySample(timestamp: now.addingTimeInterval(-3300), monthlyUsageUsd: 40),
            ApifySample(timestamp: now.addingTimeInterval(-60), monthlyUsageUsd: 190),
        ]
        #expect(
            ApifyRules.spikeAlert(
                usage: usage(spend: 200), samples: samples, spikePercent: 10, now: now) != nil)
    }

    @Test("spend going down is not a spike, and a plan with no cap has no share to compare")
    func spikeEdgeCases() {
        let samples = [
            ApifySample(timestamp: now.addingTimeInterval(-3000), monthlyUsageUsd: 200),
            ApifySample(timestamp: now.addingTimeInterval(-600), monthlyUsageUsd: 210),
        ]
        #expect(
            ApifyRules.spikeAlert(
                usage: usage(spend: 150), samples: samples, spikePercent: 10, now: now) == nil)
        #expect(
            ApifyRules.spikeAlert(
                usage: usage(spend: 400, cap: nil), samples: samples, spikePercent: 10, now: now)
                == nil)
    }

    @Test("a sustained burn does not fire twice across the wall-clock hour boundary")
    func spikeDoesNotDoubleFireAtTheBoundary() throws {
        // 10:58 and 11:03 fall in different hour buckets, so the key alone would let the
        // second one through while the burn is the same burn.
        let firstFire = try #require(ApifyDateFormats.parse("2026-08-15T10:58:00Z"))
        let secondLook = try #require(ApifyDateFormats.parse("2026-08-15T11:03:00Z"))
        let laterLook = try #require(ApifyDateFormats.parse("2026-08-15T12:05:00Z"))

        func samples(endingAt now: Date, spend: Double) -> [ApifySample] {
            [
                ApifySample(timestamp: now.addingTimeInterval(-3000), monthlyUsageUsd: spend - 60),
                ApifySample(timestamp: now.addingTimeInterval(-300), monthlyUsageUsd: spend - 10),
            ]
        }

        let first = ApifyRules.spikeAlert(
            usage: usage(spend: 160), samples: samples(endingAt: firstFire, spend: 160),
            spikePercent: 10, lastSpikeAt: nil, now: firstFire)
        #expect(first != nil, "the first spike should fire")

        let second = ApifyRules.spikeAlert(
            usage: usage(spend: 230), samples: samples(endingAt: secondLook, spend: 230),
            spikePercent: 10, lastSpikeAt: firstFire, now: secondLook)
        #expect(second == nil, "still inside the window; must not fire again")

        let third = ApifyRules.spikeAlert(
            usage: usage(spend: 300), samples: samples(endingAt: laterLook, spend: 300),
            spikePercent: 10, lastSpikeAt: firstFire, now: laterLook)
        #expect(third != nil, "more than an hour later, a fresh spike should fire")
        #expect(third?.key != first?.key, "successive spikes need distinct keys")
    }

    // MARK: - R-A3 expensive run

    @Test("runs at or above the limit alert once each, keyed by run id, linking to the console")
    func expensiveRuns() throws {
        let runs = [
            ApifyRunSummary(
                id: "r1", actorName: "Crawler", status: "RUNNING", costUsd: 12.5, startedAt: now),
            ApifyRunSummary(
                id: "r2", actorName: "Maps", status: "SUCCEEDED", costUsd: 0.75, startedAt: now),
            ApifyRunSummary(
                id: "r3", actorName: "Maps", status: "FAILED", costUsd: 5, startedAt: now),
        ]
        let alerts = ApifyRules.expensiveRunAlerts(runs: runs, minimumUsd: 5)
        #expect(alerts.map(\.key) == ["apify|run|r1", "apify|run|r3"])
        #expect(alerts[0].body == "Crawler run cost $12.50.")
        let url = try #require(alerts[0].url)
        #expect(url.absoluteString == "https://console.apify.com/actors/runs/r1")
    }

    @Test("a zero limit is treated as off rather than as \"alert on everything\"")
    func expensiveRunsDisabled() {
        let runs = [
            ApifyRunSummary(
                id: "r1", actorName: "Crawler", status: "RUNNING", costUsd: 0, startedAt: nil)
        ]
        #expect(ApifyRules.expensiveRunAlerts(runs: runs, minimumUsd: 0).isEmpty)
    }
}
