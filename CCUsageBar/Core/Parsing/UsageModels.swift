import Foundation

/// One usage bar reported by `/usage`, e.g. "Current session" or "Current week (Opus)".
///
/// The title is kept verbatim so future sections Claude Code adds still render correctly
/// without an app update; nothing downstream switches on a fixed set of names.
nonisolated struct UsageSection: Identifiable, Hashable, Codable, Sendable {
    var title: String
    var percentUsed: Int
    /// The full "Resets …" line as printed, for display.
    var resetsText: String?
    /// The same instant parsed, when the wording was understood.
    var resetsAt: Date?
    /// An adjacent informational line such as a promotional notice.
    var note: String?

    var id: String { title }

    init(
        title: String, percentUsed: Int, resetsText: String? = nil, resetsAt: Date? = nil,
        note: String? = nil
    ) {
        self.title = title
        self.percentUsed = min(max(percentUsed, 0), 100)
        self.resetsText = resetsText
        self.resetsAt = resetsAt
        self.note = note
    }

    /// A stable key for history and notification bookkeeping, independent of display casing.
    var storageKey: String { title.lowercased() }
}

/// The result of one successful `/usage` capture.
nonisolated struct UsageSnapshot: Hashable, Codable, Sendable {
    var sections: [UsageSection]
    var capturedAt: Date

    init(sections: [UsageSection], capturedAt: Date = Date()) {
        self.sections = sections
        self.capturedAt = capturedAt
    }

    var isEmpty: Bool { sections.isEmpty }

    /// The current-session bar, if Claude Code reported one.
    var sessionSection: UsageSection? {
        sections.first { $0.title.caseInsensitiveCompare("Current session") == .orderedSame }
    }

    /// The all-models weekly bar, if Claude Code reported one.
    var weekAllModelsSection: UsageSection? {
        sections.first { $0.title.caseInsensitiveCompare("Current week (all models)") == .orderedSame }
            ?? sections.first {
                let lower = $0.title.lowercased()
                return lower.hasPrefix("current week") && lower.contains("all models")
            }
    }
}
