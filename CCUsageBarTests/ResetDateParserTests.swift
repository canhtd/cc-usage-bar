import Foundation
import Testing

@testable import CCUsageBar

@Suite("Reset date parser")
struct ResetDateParserTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func components(_ date: Date, zone: String) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test("A bare clock time later today resolves to today")
    func timeLaterToday() throws {
        let now = date("2026-08-15T03:00:00Z")
        let parsed = try #require(
            ResetDateParser.parse("Resets 1:09pm (Asia/Saigon)", now: now, calendar: calendar))
        let parts = components(parsed, zone: "Asia/Saigon")
        #expect(parts.day == 15)
        #expect(parts.hour == 13)
        #expect(parts.minute == 9)
    }

    @Test("A bare clock time already past rolls to tomorrow")
    func timeAlreadyPast() throws {
        let now = date("2026-08-15T09:00:00Z")  // 4pm in Saigon
        let parsed = try #require(
            ResetDateParser.parse("Resets 1:09pm (Asia/Saigon)", now: now, calendar: calendar))
        let parts = components(parsed, zone: "Asia/Saigon")
        #expect(parts.day == 16)
        #expect(parts.hour == 13)
    }

    @Test("A dated reset keeps its month, day and time")
    func datedReset() throws {
        let now = date("2026-08-15T04:00:00Z")
        let parsed = try #require(
            ResetDateParser.parse(
                "Resets Aug 19 at 2:59am (Asia/Saigon)", now: now, calendar: calendar))
        let parts = components(parsed, zone: "Asia/Saigon")
        #expect(parts.month == 8)
        #expect(parts.day == 19)
        #expect(parts.hour == 2)
        #expect(parts.minute == 59)
    }

    @Test("A date that already passed this year rolls into next year")
    func datedResetWrapsYear() throws {
        let now = date("2026-12-28T00:00:00Z")
        let parsed = try #require(
            ResetDateParser.parse("Resets Jan 3 at 12am (UTC)", now: now, calendar: calendar))
        #expect(components(parsed, zone: "UTC").year == 2027)
    }

    @Test("Midnight and noon are not confused")
    func midnightAndNoon() throws {
        let now = date("2026-08-15T00:30:00Z")
        let midnight = try #require(
            ResetDateParser.parse("Resets 12am (UTC)", now: now, calendar: calendar))
        #expect(components(midnight, zone: "UTC").hour == 0)
        #expect(components(midnight, zone: "UTC").day == 16)
        let noon = try #require(
            ResetDateParser.parse("Resets 12:00pm (UTC)", now: now, calendar: calendar))
        #expect(components(noon, zone: "UTC").hour == 12)
        #expect(components(noon, zone: "UTC").day == 15)
    }

    @Test("A 24-hour clock is understood")
    func twentyFourHourClock() throws {
        let now = date("2026-08-15T01:00:00Z")
        let parsed = try #require(
            ResetDateParser.parse("Resets 18:45 (UTC)", now: now, calendar: calendar))
        #expect(components(parsed, zone: "UTC").hour == 18)
        #expect(components(parsed, zone: "UTC").minute == 45)
    }

    @Test("An unparsable wording yields nil rather than a wrong date")
    func unparsable() {
        #expect(ResetDateParser.parse("Resets soon", now: Date(), calendar: calendar) == nil)
        #expect(ResetDateParser.parse("", now: Date(), calendar: calendar) == nil)
    }
}
