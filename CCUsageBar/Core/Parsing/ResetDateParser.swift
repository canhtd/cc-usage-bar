import Foundation

/// Turns the "Resets …" line printed by `/usage` into a `Date`.
///
/// Observed wordings are `Resets 1:09pm (Asia/Saigon)` for the rolling session window and
/// `Resets Aug 19 at 2:59am (Asia/Saigon)` for the weekly window. Anything that cannot be
/// understood yields `nil`; the raw text is still shown to the user, so an unparsed
/// wording degrades to "we show what Claude said" rather than to a wrong date.
nonisolated enum ResetDateParser {
    static let monthNames = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ]

    static func parse(_ line: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        var working = line.trimmingCharacters(in: .whitespaces)
        var timeZone = calendar.timeZone
        if let match = working.firstMatch(of: #/\(([^)]+)\)\s*$/#) {
            let name = String(match.1).trimmingCharacters(in: .whitespaces)
            timeZone = TimeZone(identifier: name) ?? TimeZone(abbreviation: name) ?? timeZone
            working = String(working[..<match.range.lowerBound])
        }
        working = working.replacingOccurrences(
            of: #"^\s*Resets\s+"#, with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespaces)

        guard let time = parseTime(in: working) else { return nil }
        var zoned = calendar
        zoned.timeZone = timeZone

        if let day = parseMonthDay(in: working) {
            return resolveDated(day: day, time: time, now: now, calendar: zoned)
        }
        return resolveTimeOnly(time: time, now: now, calendar: zoned)
    }

    // MARK: - Components

    private struct Time { var hour: Int; var minute: Int }
    private struct MonthDay { var month: Int; var day: Int }

    private static func parseTime(in text: String) -> Time? {
        if let match = text.firstMatch(of: #/(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/#) {
            guard var hour = Int(match.1) else { return nil }
            let minute = match.2.flatMap { Int($0) } ?? 0
            let isPM = match.3.lowercased() == "pm"
            if hour == 12 { hour = 0 }
            if isPM { hour += 12 }
            return Time(hour: hour, minute: minute)
        }
        if let match = text.firstMatch(of: #/\b(\d{1,2}):(\d{2})\b/#),
            let hour = Int(match.1), let minute = Int(match.2), hour < 24 {
            return Time(hour: hour, minute: minute)
        }
        return nil
    }

    private static func parseMonthDay(in text: String) -> MonthDay? {
        guard let match = text.firstMatch(of: #/(?i)\b([A-Za-z]{3,9})\.?\s+(\d{1,2})\b/#) else {
            return nil
        }
        let prefix = String(match.1).lowercased().prefix(3)
        guard let index = monthNames.firstIndex(of: String(prefix)), let day = Int(match.2),
            (1...31).contains(day)
        else { return nil }
        return MonthDay(month: index + 1, day: day)
    }

    // MARK: - Resolution

    /// A bare clock time means the next occurrence of that time.
    private static func resolveTimeOnly(time: Time, now: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }
        return candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    /// A month and day carry no year; pick the year that puts the date nearest to now.
    private static func resolveDated(
        day: MonthDay, time: Time, now: Date, calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.year = calendar.component(.year, from: now)
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }
        let sixMonths: TimeInterval = 180 * 24 * 3600
        if candidate.timeIntervalSince(now) < -sixMonths {
            return calendar.date(byAdding: .year, value: 1, to: candidate)
        }
        if candidate.timeIntervalSince(now) > sixMonths {
            return calendar.date(byAdding: .year, value: -1, to: candidate)
        }
        return candidate
    }
}
