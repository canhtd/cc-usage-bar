import Foundation
import Testing

@testable import CCUsageBar

/// Decoding of real Apify v2 response shapes, from committed fixtures.
@Suite("Apify response decoding")
struct ApifyDecodingTests {
    private func decode<Payload: Decodable & Sendable>(
        _ name: String, as type: Payload.Type
    ) throws -> Payload {
        let data = try FixtureLoader.data(named: name)
        return try ApifyClient.decoder.decode(ApifyEnvelope<Payload>.self, from: data).data
    }

    @Test("limits carry spend, cap and cycle, ignoring the fields the app does not use")
    func limits() throws {
        let limits = try decode("apify-limits.json", as: ApifyLimits.self)
        #expect(limits.current.monthlyUsageUsd == 123.456)
        #expect(limits.limits.maxMonthlyUsageUsd == 200)
        #expect(limits.monthlyUsageCycle.startAt == ApifyDateFormats.parse("2026-07-01T00:00:00Z"))

        let usage = ApifyUsage(
            monthlyUsageUsd: limits.current.monthlyUsageUsd,
            maxMonthlyUsageUsd: limits.limits.maxMonthlyUsageUsd,
            cycleStartAt: limits.monthlyUsageCycle.startAt,
            cycleEndAt: limits.monthlyUsageCycle.endAt,
            capturedAt: Date(), runs: [])
        #expect(usage.percentUsed == 62)
        // The cycle is exactly the month of July 2026.
        #expect(
            limits.monthlyUsageCycle.endAt.timeIntervalSince(limits.monthlyUsageCycle.startAt)
                == 31 * 86400)
    }

    @Test("a plan with no monthly cap decodes, and simply has no percentage")
    func uncappedLimits() throws {
        let limits = try decode("apify-limits-uncapped.json", as: ApifyLimits.self)
        #expect(limits.limits.maxMonthlyUsageUsd == nil)
        let usage = ApifyUsage(
            monthlyUsageUsd: limits.current.monthlyUsageUsd,
            maxMonthlyUsageUsd: limits.limits.maxMonthlyUsageUsd,
            cycleStartAt: limits.monthlyUsageCycle.startAt,
            cycleEndAt: limits.monthlyUsageCycle.endAt,
            capturedAt: Date(), runs: [])
        #expect(usage.percentUsed == nil)
        #expect(usage.monthlyUsageUsd == 88.5)
    }

    @Test("runs decode, including one that has not accrued any cost yet")
    func runs() throws {
        let page = try decode("apify-runs.json", as: ApifyRunPage.self)
        #expect(page.items.count == 3)
        #expect(page.items[0].id == "run-running")
        #expect(page.items[0].usageTotalUsd == 12.5)
        #expect(page.items[0].startedAt != nil)
        #expect(page.items[2].usageTotalUsd == nil)
        #expect(page.items[2].startedAt == nil)
    }

    @Test("the user and actor payloads decode")
    func userAndActor() throws {
        #expect(try decode("apify-user.json", as: ApifyUser.self).username == "danny")
        let actor = try decode("apify-act.json", as: ApifyActor.self)
        #expect(actor.displayName == "Website Content Crawler")
    }

    @Test("both ISO-8601 spellings Apify uses are accepted, and nonsense is not")
    func dates() throws {
        let fractional = try #require(ApifyDateFormats.parse("2026-07-20T11:00:00.250Z"))
        let plain = try #require(ApifyDateFormats.parse("2026-07-20T11:00:00Z"))
        #expect(fractional.timeIntervalSince(plain) == 0.25)
        #expect(ApifyDateFormats.parse("20 July 2026") == nil)
        #expect(ApifyDateFormats.parse("") == nil)
    }

    @Test("the debug screenshot fixture decodes through the same path as the network does")
    func debugFixture() throws {
        let usage = try ApifyFixture.usage()
        #expect(usage.monthlyUsageUsd == 261.4832)
        #expect(usage.maxMonthlyUsageUsd == 500)
        #expect(usage.percentUsed == 52)
        #expect(usage.runs.count == 3)
        #expect(usage.runs[0].actorName == "Website Content Crawler")
        #expect(usage.runs[0].costUsd == 6.4213)
    }
}
