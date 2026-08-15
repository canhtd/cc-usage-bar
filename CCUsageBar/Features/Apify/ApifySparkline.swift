import Charts
import SwiftUI

/// Apify spend over the selected window (A4).
///
/// Unlike the Claude sparklines this plots dollars, not a percentage, so the Y domain is
/// derived from the data: a plan with no monthly cap has no percentage at all, and even on
/// a capped plan a month that only ever reaches 12% would be a flat line at the bottom of a
/// 0-100 axis. Padding the domain keeps a nearly-flat series from filling the whole box.
struct ApifySparkline: View {
    let samples: [HistorySample]
    let tint: Color

    private var amounts: [Double] { samples.compactMap(\.amountUsd) }

    private var domain: ClosedRange<Double> {
        guard let low = amounts.min(), let high = amounts.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, max(high * 0.02, 0.01))
        return (low - padding)...(high + padding)
    }

    var body: some View {
        Chart(samples) { sample in
            if let amount = sample.amountUsd {
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Spend", amount)
                )
                .foregroundStyle(tint.opacity(0.18))
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Spend", amount)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 34)
        .padding(.top, 2)
        .accessibilityLabel("Apify spend over the selected window")
    }
}
