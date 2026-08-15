import Foundation
import Testing

@testable import CCUsageBar

/// The deliver-then-mark ordering on the Apify path, plus the grouped-budget policy.
///
/// The post itself is stubbed. The test host is the real app bundle, so the notification
/// centre is live: exercising the real path would both post banners at the user and make
/// the outcome depend on whatever permission the app happens to hold.
@MainActor
@Suite("Apify notification delivery")
struct NotificationDeliveryTests {
    private func makeService() -> NotificationService {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ccusagebar-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return NotificationService(
            storeURL: directory.appending(path: "thresholds.json"),
            ledgerURL: directory.appending(path: "alerts.json"))
    }

    private var budgetAlerts: [PendingAlert] {
        [
            PendingAlert(key: "apify|budget|c|80", title: "t", body: "b", group: "apify|budget|c"),
            PendingAlert(key: "apify|budget|c|50", title: "t", body: "b", group: "apify|budget|c"),
        ]
    }

    @Test("a key is not marked delivered when the notification centre refuses the post")
    func failedDeliveryKeepsAlertPending() async {
        let service = makeService()
        service.postHandlerForTesting = { _ in false }
        let alerts = [PendingAlert(key: "apify|run|r1", title: "t", body: "b")] + budgetAlerts

        await service.deliver(alerts)

        #expect(service.ledger.contains("apify|run|r1") == false)
        #expect(service.ledger.contains("apify|budget|c|80") == false)
        #expect(
            service.ledger.contains("apify|budget|c|50") == false,
            "a superseded key must not be burned when its leader never reached the user")
        #expect(service.ledger.pending(alerts).count == 3)
    }

    @Test("a successful post marks its key, and the same alert never fires twice")
    func successfulDeliveryMarksOnce() async {
        let service = makeService()
        let posted = Counter()
        service.postHandlerForTesting = { _ in
            posted.increment()
            return true
        }
        let alerts = [PendingAlert(key: "apify|run|r1", title: "t", body: "b")]

        await service.deliver(alerts)
        await service.deliver(alerts)

        #expect(posted.value == 1, "the second pass should have found the key already delivered")
        #expect(service.ledger.contains("apify|run|r1"))
    }

    @Test("only the highest crossed threshold is announced; the lower one is recorded")
    func groupedBudgetPostsOnce() async {
        let service = makeService()
        let posted = Counter()
        service.postHandlerForTesting = { alert in
            posted.append(alert.key)
            return true
        }

        await service.deliver(budgetAlerts)

        #expect(posted.keys == ["apify|budget|c|80"], "posted: \(posted.keys)")
        #expect(service.ledger.contains("apify|budget|c|80"))
        #expect(
            service.ledger.contains("apify|budget|c|50"),
            "the superseded threshold must be burned so it cannot fire later in the cycle")
        #expect(service.ledger.pending(budgetAlerts).isEmpty)
    }

    @Test("delivering an empty list posts nothing")
    func emptyDelivery() async {
        let service = makeService()
        let posted = Counter()
        service.postHandlerForTesting = { _ in
            posted.increment()
            return true
        }
        await service.deliver([])
        #expect(posted.value == 0)
    }
}

/// Records what the stubbed post was asked to send.
@MainActor
private final class Counter {
    private(set) var value = 0
    private(set) var keys: [String] = []

    func increment() { value += 1 }

    func append(_ key: String) {
        value += 1
        keys.append(key)
    }
}
