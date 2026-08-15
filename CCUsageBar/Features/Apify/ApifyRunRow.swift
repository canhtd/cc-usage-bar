import SwiftUI

/// One recent Apify run in the popover: actor, status, cost (A4).
struct ApifyRunRow: View {
    let run: ApifyRunSummary

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(run.actorName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(run.status.capitalized)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ApifyRules.money(run.costUsd))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(run.actorName), \(run.status.lowercased()), \(ApifyRules.money(run.costUsd))")
    }

    /// Apify statuses are upper-case strings; anything unrecognised stays neutral rather
    /// than being guessed at.
    private var statusColor: Color {
        switch run.status.uppercased() {
        case "RUNNING", "READY": return .accentColor
        case "SUCCEEDED": return .green
        case "FAILED", "ABORTED", "ABORTING", "TIMED-OUT", "TIMING-OUT": return .red
        default: return .secondary
        }
    }
}
