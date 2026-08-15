import SwiftUI

/// One `/usage` section: title, real progress bar, reset text, and a 24h sparkline.
struct UsageSectionRow: View {
    let section: UsageSection
    let samples: [HistorySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(section.percentUsed)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(tint)
            }
            ProgressView(value: Double(section.percentUsed), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
            if let resets = section.resetsText {
                Text(resets)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = section.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // Two points make a straight line that reads as a stray rule, not a trend.
            if samples.count >= 3 {
                SparklineChart(samples: samples, tint: tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.percentUsed) percent used")
    }

    /// The same bands as the menu bar (F1): neutral up to 69%, orange 70-89%, red from
    /// 90%. Using the accent colour for "normal" made every healthy reading look like a
    /// warning, because this app's accent is orange -- 8% and 78% were the same colour.
    private var tint: Color {
        switch MenuBarTitle.severity(forPercent: section.percentUsed) {
        case .normal, .unknown: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
