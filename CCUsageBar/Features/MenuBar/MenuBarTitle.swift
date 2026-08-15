import Foundation

/// Pure formatting for the status item, so the thresholds in F1 are testable without AppKit.
nonisolated enum MenuBarTitle {
    /// Colour bands: default up to 69%, orange 70-89%, red from 90%.
    enum Severity: Sendable, Equatable {
        case normal
        case warning
        case critical
        case unknown
    }

    /// Shown when there is no trustworthy number.
    static let placeholder = "—"

    static func severity(forPercent percent: Int?) -> Severity {
        guard let percent else { return .unknown }
        switch percent {
        case ..<70: return .normal
        case 70..<90: return .warning
        default: return .critical
        }
    }

    /// `47% · 25%` -- session first, then the all-models week.
    ///
    /// A section Claude Code did not report is shown as `—` rather than omitted, so the
    /// two slots stay in the same place and the bar does not jump around.
    static func text(for snapshot: UsageSnapshot?, state: UsageState) -> String {
        guard let snapshot, !state.isUnknown else { return placeholder }
        let parts = [snapshot.sessionSection, snapshot.weekAllModelsSection]
            .map { $0.map { "\($0.percentUsed)%" } ?? placeholder }
        if parts.allSatisfy({ $0 == placeholder }) {
            // No familiar section names; fall back to the first bar Claude Code reported.
            guard let first = snapshot.sections.first else { return placeholder }
            return "\(first.percentUsed)%"
        }
        return parts.joined(separator: " · ")
    }

    /// The band driving the title colour: whichever displayed number is worse.
    static func severity(for snapshot: UsageSnapshot?, state: UsageState) -> Severity {
        guard let snapshot, !state.isUnknown else { return .unknown }
        let candidates = [snapshot.sessionSection, snapshot.weekAllModelsSection]
            .compactMap { $0?.percentUsed }
        let worst = candidates.max() ?? snapshot.sections.map(\.percentUsed).max()
        return severity(forPercent: worst)
    }

    /// SF Symbol reflecting the worst band, so icon-only mode still carries the signal.
    static func symbolName(for severity: Severity) -> String {
        switch severity {
        case .normal: return "gauge.with.dots.needle.33percent"
        case .warning: return "gauge.with.dots.needle.67percent"
        case .critical: return "gauge.with.dots.needle.100percent"
        case .unknown: return "gauge.with.dots.needle.bottom.0percent"
        }
    }
}
