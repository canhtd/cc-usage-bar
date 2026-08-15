import SwiftUI

/// Last-updated time, current state, refresh, raw-output toggle, and a way into Settings.
struct PopoverFooter: View {
    @Bindable var model: AppModel
    @Binding var showRawOutput: Bool
    let openSettings: () -> Void

    private var runtime: ProfileRuntime { model.activeRuntime }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = runtime.state.message, !runtime.state.isLoading {
                Label {
                    Text(message).font(.caption)
                } icon: {
                    Image(systemName: runtime.state.symbolName ?? "info.circle")
                }
                .foregroundStyle(runtime.state == .ready ? .secondary : .primary)
            }
            HStack(spacing: 10) {
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showRawOutput.toggle()
                } label: {
                    Label(
                        showRawOutput ? "Hide raw" : "Show raw output",
                        systemImage: showRawOutput ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.link)
                .font(.caption)

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Button {
                    model.refreshAll()
                } label: {
                    if isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isFetching)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Busy while either half is in flight, so the button does not look idle during an
    /// Apify request that has not come back yet.
    private var isFetching: Bool { runtime.isFetching || model.apify.isRefreshing }

    private var updatedText: String {
        guard let updated = runtime.lastUpdated else { return "Never updated" }
        return "Updated \(RelativeTime.describe(updated))"
    }
}
