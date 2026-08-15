import Foundation
import Testing

@testable import CCUsageBar

/// The keyed once-only ledger behind the Apify alerts.
@Suite("Alert ledger")
struct AlertLedgerTests {
    private func alert(_ key: String) -> PendingAlert {
        PendingAlert(key: key, title: "t", body: "b")
    }

    @Test("an alert is pending until it is marked delivered")
    func pendingUntilDelivered() {
        var ledger = AlertLedger()
        let alerts = [alert("a"), alert("b")]
        #expect(ledger.pending(alerts).count == 2)
        ledger.markDelivered(["a"])
        #expect(ledger.pending(alerts).map(\.key) == ["b"])
        #expect(ledger.contains("a"))
    }

    @Test("marking nothing delivered leaves everything pending")
    func deliveryFailureKeepsAlertPending() {
        var ledger = AlertLedger()
        ledger.markDelivered([])
        #expect(ledger.pending([alert("a")]).count == 1)
    }

    @Test("keys past the retention window are forgotten, newer ones are kept")
    func prune() {
        let now = Date()
        var ledger = AlertLedger()
        ledger.markDelivered(["old"], at: now.addingTimeInterval(-60 * 24 * 3600))
        ledger.markDelivered(["recent"], at: now.addingTimeInterval(-24 * 3600))
        ledger.prune(now: now)
        #expect(ledger.contains("old") == false)
        #expect(ledger.contains("recent"))
    }

    @Test("a month-old billing-cycle key survives pruning, so it cannot re-fire mid-cycle")
    func retentionOutlastsABillingCycle() {
        #expect(AlertLedger.retention > 31 * 24 * 3600)
    }

    @Test("the ledger round-trips through JSON, which is how it is persisted")
    func codable() throws {
        var ledger = AlertLedger()
        ledger.markDelivered(["apify|run|abc"])
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(AlertLedger.self, from: data)
        #expect(decoded.contains("apify|run|abc"))
    }

    // MARK: - Grouping and prefix lookup

    @Test("ungrouped alerts all post; grouped ones collapse to the first of each group")
    func partition() {
        let alerts = [
            PendingAlert(key: "b|95", title: "t", body: "b", group: "b"),
            PendingAlert(key: "b|80", title: "t", body: "b", group: "b"),
            PendingAlert(key: "b|50", title: "t", body: "b", group: "b"),
            alert("spike"),
            PendingAlert(key: "r|1", title: "t", body: "b", group: "r"),
        ]
        let (post, superseded) = AlertLedger.partition(alerts)
        #expect(post.map(\.key) == ["b|95", "spike", "r|1"])
        #expect(superseded.map(\.key) == ["b|80", "b|50"])
    }

    @Test("an empty list partitions to nothing rather than tripping")
    func partitionEmpty() {
        let (post, superseded) = AlertLedger.partition([])
        #expect(post.isEmpty)
        #expect(superseded.isEmpty)
    }

    @Test("the ledger reports when a prefix last fired, which is how spikes rate-limit")
    func lastDeliveryByPrefix() {
        let now = Date()
        var ledger = AlertLedger()
        #expect(ledger.lastDelivery(withPrefix: ApifyRules.spikeKeyPrefix) == nil)
        ledger.markDelivered(["apify|spike|100"], at: now.addingTimeInterval(-7200))
        ledger.markDelivered(["apify|spike|101"], at: now.addingTimeInterval(-600))
        ledger.markDelivered(["apify|budget|x|80"], at: now)
        let last = ledger.lastDelivery(withPrefix: ApifyRules.spikeKeyPrefix)
        #expect(last == now.addingTimeInterval(-600))
    }
}
