import SwiftUI

/// Refresh cadence, menu bar appearance, and the login item (F5, F6, F8).
struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var preferences = model.preferences
        return Form {
            Section("Refresh") {
                Picker("Automatically refresh", selection: refreshBinding) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                Text("A refresh also runs when the Mac wakes from sleep. Manual refresh is always available from the popover and the right-click menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Picker("Show", selection: $preferences.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { display in
                        Text(display.label).tag(display)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: launchBinding)
                if LaunchAtLogin.requiresApproval {
                    Text("Approve CC Usage Bar in System Settings › General › Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var refreshBinding: Binding<RefreshInterval> {
        Binding(
            get: { model.preferences.refreshInterval },
            set: {
                model.preferences.refreshInterval = $0
                model.refreshIntervalDidChange()
            })
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { launchAtLogin = LaunchAtLogin.set($0) })
    }
}
