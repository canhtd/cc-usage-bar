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
}
