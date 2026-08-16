import SwiftUI

/// The left-click popover: native controls, never a terminal dump (F2).
struct PopoverView: View {
    @Bindable var model: AppModel
    let openSettings: () -> Void
    @State private var showRawOutput = false

    private var runtime: ProfileRuntime { model.activeRuntime }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            PopoverFooter(
                model: model, showRawOutput: $showRawOutput, openSettings: openSettings)
        }
        .frame(width: PopoverLayout.width)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(.secondary)
            Text("Claude Code Usage")
                .font(.headline)
            Spacer()
            if model.preferences.profiles.count > 1 {
                Picker("Profile", selection: profileBinding) {
                    ForEach(model.preferences.profiles) { profile in
                        Text(profile.shortName).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var profileBinding: Binding<UUID> {
        Binding(
            get: { model.preferences.activeProfileID },
            set: { model.selectProfile(id: $0) })
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot = runtime.snapshot, !snapshot.isEmpty {
                    ForEach(snapshot.sections) { section in
                        UsageSectionRow(
                            section: section,
                            samples: model.history.series(
                                profileID: runtime.profile.id,
                                sectionKey: section.storageKey,
                                since: Date().addingTimeInterval(-24 * 3600)))
                    }
                } else {
                    EmptyStateView(state: runtime.state)
                }
                if model.apify.isEnabled {
                    Divider()
                    ApifySectionView(model: model, openSettings: openSettings)
                }
                if showRawOutput {
                    RawOutputView(rows: runtime.rawRows)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: PopoverLayout.maxContentHeight(
            showRawOutput: showRawOutput, apifyEnabled: model.apify.isEnabled))
        // A `ScrollView` is greedy: on its own it swallows every point the cap above
        // allows, which left a block of dead space under the last section whenever the
        // content was shorter -- most visibly with the Apify block switched off. Fixing
        // the vertical size makes it report the height of its content instead, so the
        // cap only bites once there really is more content than fits.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shown before the first successful fetch, or when a fetch failed.
private struct EmptyStateView: View {
    let state: UsageState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading /usage from Claude Code…")
                }
            } else {
                Label {
                    Text(state.message ?? "No usage data yet.")
                } icon: {
                    Image(systemName: state.symbolName ?? "questionmark.circle")
                }
                .foregroundStyle(state == .needsSetup ? .primary : .secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
