import Foundation
import Testing

@testable import CCUsageBar

/// F5: 30-day retention, pruned on launch.
@Suite("History retention")
struct HistoryRetentionTests {
    private let profile = UUID()
    private let other = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(daysAgo: Double, percent: Int = 10, title: String = "Current session")
        -> HistorySample
    {
        HistorySample(
            timestamp: now.addingTimeInterval(-daysAgo * 24 * 3600),
            profileID: profile,
            section: UsageSection(title: title, percentUsed: percent))
    }

    @Test("Samples older than 30 days are dropped, newer ones kept")
    func prunesByAge() {
        let samples = [sample(daysAgo: 45), sample(daysAgo: 31), sample(daysAgo: 29), sample(daysAgo: 0)]
        let kept = HistoryRetention.prune(samples, now: now)
        #expect(kept.count == 2)
        #expect(kept.allSatisfy { $0.timestamp >= now.addingTimeInterval(-HistoryRetention.interval) })
    }

    @Test("Pruning sorts oldest first")
    func prunesSorted() {
        let kept = HistoryRetention.prune([sample(daysAgo: 1), sample(daysAgo: 10)], now: now)
        #expect(kept[0].timestamp < kept[1].timestamp)
    }

    @Test("A sample exactly on the boundary is kept")
    func boundaryIsInclusive() {
        let kept = HistoryRetention.prune([sample(daysAgo: 30)], now: now)
        #expect(kept.count == 1)
    }

    @Test("Pruning an empty history is a no-op")
    func emptyHistory() {
        #expect(HistoryRetention.prune([], now: now).isEmpty)
    }

    @Test("A series is filtered by profile, section and window")
    func seriesFiltering() {
        var samples = [
            sample(daysAgo: 0.5, percent: 20),
            sample(daysAgo: 0.2, percent: 30),
            sample(daysAgo: 3, percent: 40),
            sample(daysAgo: 0.1, percent: 50, title: "Current week (all models)"),
        ]
        samples.append(
            HistorySample(
                timestamp: now, profileID: other,
                section: UsageSection(title: "Current session", percentUsed: 99)))

        let series = HistoryRetention.series(
            samples, profileID: profile, sectionKey: "current session",
            since: now.addingTimeInterval(-24 * 3600))
        #expect(series.map(\.percentUsed) == [20, 30])
    }

    @Test("Section keys are case-insensitive by construction")
    func storageKeyIsLowercased() {
        #expect(UsageSection(title: "Current Week (All Models)", percentUsed: 1).storageKey
            == "current week (all models)")
    }

    @Test("A sample encodes and decodes losslessly")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = sample(daysAgo: 2, percent: 77)
        let restored = try decoder.decode(HistorySample.self, from: encoder.encode(original))
        #expect(restored == original)
    }
}
