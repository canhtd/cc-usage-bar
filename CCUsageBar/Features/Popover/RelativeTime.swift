import Foundation

/// Human wording for "when did this last update?".
///
/// `RelativeDateTimeFormatter` alone says "in 0 seconds" for a timestamp that is a
/// microsecond in the future, which is what a just-completed fetch always is.
nonisolated enum RelativeTime {
    static func describe(_ date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}
