import Foundation

/// ISO-8601 parsing for Apify timestamps.
///
/// `ISO8601DateFormatter` is a reference type and not `Sendable`, so it cannot be held in a
/// shared `static let` under strict concurrency. `Date.ISO8601FormatStyle` is a value type
/// and covers both spellings Apify uses; the formatter is only built, locally, for the
/// unlikely case of a numeric UTC offset in place of `Z`.
nonisolated enum ApifyDateFormats {
    static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let plain = Date.ISO8601FormatStyle()

    static func parse(_ text: String) -> Date? {
        if let date = try? fractional.parse(text) { return date }
        if let date = try? plain.parse(text) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
