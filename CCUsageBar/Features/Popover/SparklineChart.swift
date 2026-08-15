import Charts
import SwiftUI

/// A 24-hour sparkline under a usage bar (F2).
///
/// Deliberately unlabelled: it answers "is this climbing fast?" at a glance, and the
/// Settings history tab is where axes and ranges belong. The plot area is tinted so a flat
/// series still reads as a chart rather than as a stray divider rule.
struct SparklineChart: View {
    let samples: [HistorySample]
    let tint: Color

    var body: some View {
        Chart(samples) { sample in
            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used", sample.percentUsed)
            )
            .foregroundStyle(tint.opacity(0.18))
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used", sample.percentUsed)
            )
            .foregroundStyle(tint)
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 34)
        .padding(.top, 2)
        .accessibilityLabel("Usage over the last 24 hours")
    }
}
