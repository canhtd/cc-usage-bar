import Foundation
import Testing

@testable import CCUsageBar

/// History has to keep loading files written before the Apify module existed (A2).
@Suite("Apify history samples")
struct ApifyHistoryTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test("a v2.0 history line, with no source or amount, still decodes as a Claude sample")
    func decodesLegacyLine() throws {
        let line = """
            {"timestamp":"2026-07-20T10:00:00Z","profileID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F",\
            "sectionKey":"session","sectionTitle":"Current session","percentUsed":42}
            """
        let sample = try decoder.decode(HistorySample.self, from: Data(line.utf8))
        #expect(sample.source == .claude)
        #expect(sample.amountUsd == nil)
        #expect(sample.percentUsed == 42)
    }

    @Test("an Apify sample round-trips with its source and dollar amount intact")
    func apifySampleRoundTrip() throws {
        let usage = ApifyUsage(
            monthlyUsageUsd: 261.48, maxMonthlyUsageUsd: 500,
            cycleStartAt: Date(timeIntervalSince1970: 1_800_000_000),
            cycleEndAt: Date(timeIntervalSince1970: 1_802_000_000),
            capturedAt: Date(timeIntervalSince1970: 1_800_500_000), runs: [])
        let sample = HistorySample(apify: usage)
        #expect(sample.source == .apify)
        #expect(sample.amountUsd == 261.48)
        #expect(sample.percentUsed == 52)
        #expect(sample.profileID == HistorySample.apifyProfileID)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = try decoder.decode(
            HistorySample.self, from: try encoder.encode(sample))
        #expect(decoded == sample)
    }

    @Test("only Apify samples inside the window are handed to the spike rule, oldest first")
    func filtersSpikeWindow() {
        let now = Date()
        let claude = HistorySample(
            timestamp: now, profileID: UUID(),
            section: UsageSection(title: "Current session", percentUsed: 10))
        var recent = HistorySample(apify: usage(at: now.addingTimeInterval(-600), spend: 30))
        recent.amountUsd = 30
        let older = HistorySample(apify: usage(at: now.addingTimeInterval(-1800), spend: 10))
        let expired = HistorySample(apify: usage(at: now.addingTimeInterval(-9000), spend: 1))

        let samples = HistoryRetention.apifySamples(
            [claude, recent, expired, older], since: now.addingTimeInterval(-3600))
        #expect(samples.map(\.monthlyUsageUsd) == [10, 30])
    }

    private func usage(at date: Date, spend: Double) -> ApifyUsage {
        ApifyUsage(
            monthlyUsageUsd: spend, maxMonthlyUsageUsd: 500,
            cycleStartAt: date.addingTimeInterval(-86400),
            cycleEndAt: date.addingTimeInterval(86400), capturedAt: date, runs: [])
    }
}
