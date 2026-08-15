import Charts
import SwiftUI

/// Usage history over 24h / 7d / 30d, one line per section (F5).
struct HistorySettingsView: View {
    @Bindable var model: AppModel
    @State private var window: HistoryWindow = .day

    enum HistoryWindow: String, CaseIterable, Identifiable {
        case day = "24 hours"
        case week = "7 days"
        case month = "30 days"

        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .day: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 30 * 24 * 3600
            }
        }
    }

    private var since: Date { Date().addingTimeInterval(-window.interval) }
    private var profileID: UUID { model.preferences.activeProfileID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $window) {
                ForEach(HistoryWindow.allCases) { option in Text(option.rawValue).tag(option) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if points.isEmpty && apifyPoints.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text(
                        "History is recorded after each successful refresh and kept for \(HistoryRetention.days) days."))
            } else {
                // Scrolls because the two charts together can be taller than the tab, and
                // a clipped axis is worse than a scroll bar.
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !points.isEmpty { chart }
                        if !apifyPoints.isEmpty { apifyChart }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var chart: some View {
        Chart(points) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Used", sample.percentUsed)
            )
            .foregroundStyle(by: .value("Section", sample.sectionTitle))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                }
            }
        }
        .chartLegend(position: .bottom)
        .frame(minHeight: 220)
    }

    /// Apify spend is dollars, not a percentage, so it needs its own axis rather than a
    /// second series on the 0-100 chart above.
    private var apifyChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Apify spend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart(apifyPoints) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Spend", sample.amountUsd ?? 0)
                )
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.monotone)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(ApifyRules.money(amount))
                        }
                    }
                }
            }
            .frame(minHeight: 140)
        }
    }

    private var apifyPoints: [HistorySample] {
        guard model.apify.isEnabled else { return [] }
        return model.history.apifySeries(since: since)
    }

    private var points: [HistorySample] {
        model.history.sectionTitles(profileID: profileID)
            .flatMap {
                model.history.series(profileID: profileID, sectionKey: $0.key, since: since)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
