import Foundation

/// Pure parser turning the rendered `/usage` screen into a `UsageSnapshot`.
///
/// Input is plain text read back from `ANSIScreen` -- escape codes are already gone, and
/// the differential Ink repaints have been resolved into the characters the user sees.
/// The parser is anchored on the percentage line rather than on known section names, so a
/// section Claude Code adds later still appears with its title and bar.
nonisolated enum UsageParser {
    /// A line such as `████████▌            25% used`, with or without the bar glyphs.
    ///
    /// Built per use rather than stored: `Regex` is not `Sendable`, and a static instance
    /// would be shared mutable state under strict concurrency.
    private static var percentLine: Regex<(Substring, Substring)> {
        #/^[\u{2580}-\u{259F}\s]*?(\d{1,3})\s*%\s+used\s*$/#
    }
    /// Block-drawing glyphs used for the bars, so a bar line is never mistaken for a title.
    private static let barCharacters = CharacterSet(charactersIn: "\u{2580}"..."\u{259F}")

    static func parse(screenText: String, now: Date = Date()) -> UsageSnapshot {
        let lines = screenText.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var order: [String] = []
        var byTitle: [String: UsageSection] = [:]

        for (index, line) in lines.enumerated() {
            guard let match = line.wholeMatch(of: percentLine), let percent = Int(match.1),
                percent <= 100
            else { continue }
            guard let title = title(before: index, in: lines) else { continue }

            var section = UsageSection(title: title, percentUsed: percent)
            let trailer = trailer(after: index, in: lines)
            section.resetsText = trailer.resets
            section.resetsAt = trailer.resets.flatMap { ResetDateParser.parse($0, now: now) }
            section.note = trailer.note

            if byTitle[title] == nil { order.append(title) }
            // Ink repaints the panel more than once; the last rendering wins.
            byTitle[title] = section
        }

        return UsageSnapshot(sections: order.compactMap { byTitle[$0] }, capturedAt: now)
    }

    /// The section heading: the nearest preceding line that is not itself bar data.
    private static func title(before index: Int, in lines: [String]) -> String? {
        var cursor = index - 1
        while cursor >= 0, index - cursor <= 3 {
            let candidate = lines[cursor]
            cursor -= 1
            if candidate.isEmpty { continue }
            if isBarOrData(candidate) { continue }
            guard candidate.count <= 80 else { return nil }
            return candidate
        }
        return nil
    }

    private static func isBarOrData(_ line: String) -> Bool {
        if line.lowercased().hasPrefix("resets") { return true }
        if line.wholeMatch(of: percentLine) != nil { return true }
        if line.unicodeScalars.contains(where: { barCharacters.contains($0) }) { return true }
        return false
    }

    /// The "Resets …" line and any adjacent note that belong to the bar at `index`.
    private static func trailer(after index: Int, in lines: [String]) -> (
        resets: String?, note: String?
    ) {
        var resets: String?
        var note: String?
        var cursor = index + 1
        while cursor < lines.count, cursor - index <= 3 {
            let line = lines[cursor]
            cursor += 1
            if line.isEmpty { continue }
            if resets == nil, line.lowercased().hasPrefix("resets") {
                resets = line
                continue
            }
            if note == nil, isNote(line) {
                note = line
                continue
            }
            break
        }
        return (resets, note)
    }

    /// Informational lines Claude Code prints under a bar, such as the weekly-limit promo.
    private static func isNote(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard line.hasPrefix("+") || lower.contains("promo") else { return false }
        return !lower.contains("% used")
    }
}
