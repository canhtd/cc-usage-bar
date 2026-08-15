import SwiftUI

/// The Apify block in the popover: budget, cycle, spend sparkline, recent runs (A4).
///
/// Renders nothing at all while the module is disabled -- the point of an optional module
/// is that somebody who does not use Apify never sees it, not even as an invitation.
struct ApifySectionView: View {
    @Bindable var model: AppModel
    let openSettings: () -> Void
    @State private var window: ApifyChartWindow = .day

    private var apify: ApifyRuntime { model.apify }

    var body: some View {
        if apify.isEnabled {
            VStack(alignment: .leading, spacing: 5) {
                header
                if let usage = apify.usage {
                    figures(usage)
                    ProgressView(value: Double(usage.percentUsed ?? 0), total: 100)
                        .progressViewStyle(.linear)
                        .tint(tint)
                        .opacity(usage.percentUsed == nil ? 0.35 : 1)
                    Text(cycleText(usage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    chart
                    runs(usage)
                }
                errorLine
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Apify")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let percent = apify.usage?.percentUsed {
                Text("\(percent)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(tint)
            }
        }
    }

    private func figures(_ usage: ApifyUsage) -> some View {
        Text(spendText(usage))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 4) {
            let samples = model.history.apifySeries(
                since: Date().addingTimeInterval(-window.interval))
            // Two points draw a straight line that reads as a stray rule, not a trend.
            if samples.count >= 3 {
                Picker("Range", selection: $window) {
                    ForEach(ApifyChartWindow.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                ApifySparkline(samples: samples, tint: tint)
            }
        }
    }

    @ViewBuilder
    private func runs(_ usage: ApifyUsage) -> some View {
        let recent = Array(usage.runs.prefix(ApifyRuntime.shownRunCount))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recent runs")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                ForEach(recent) { run in ApifyRunRow(run: run) }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var errorLine: some View {
        if let message = apify.state.message {
            HStack(spacing: 6) {
                Image(systemName: apify.state.isLoading ? "clock" : "exclamationmark.triangle")
                Text(offlineMessage(message))
                if apify.state.needsSettings {
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(apify.state.needsSettings ? .primary : .secondary)
            .padding(.top, 2)
        }
    }

    // MARK: - Text

    private func spendText(_ usage: ApifyUsage) -> String {
        guard let max = usage.maxMonthlyUsageUsd else {
            return "\(ApifyRules.money(usage.monthlyUsageUsd)) this month (no monthly cap)"
        }
        return "\(ApifyRules.money(usage.monthlyUsageUsd)) of \(ApifyRules.money(max)) this month"
    }

    private func cycleText(_ usage: ApifyUsage) -> String {
        let days = usage.daysRemaining()
        let date = usage.cycleEndAt.formatted(date: .abbreviated, time: .omitted)
        return "Cycle resets \(date) (\(days) \(days == 1 ? "day" : "days"))"
    }

    /// An offline failure is worth pairing with the age of the figure still on screen.
    private func offlineMessage(_ message: String) -> String {
        guard apify.state == .failed(.offline), let updated = apify.lastUpdated else {
            return message
        }
        return "Offline, last updated \(RelativeTime.describe(updated))."
    }

    private var tint: Color {
        switch MenuBarTitle.severity(forPercent: apify.usage?.percentUsed) {
        case .normal, .unknown: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// Windows offered by the popover's Apify sparkline.
enum ApifyChartWindow: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        }
    }
}
