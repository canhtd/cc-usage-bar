import SwiftUI

/// Threshold notifications (F4). Permission is requested lazily, on first enable.
struct NotificationSettingsView: View {
    @Bindable var model: AppModel
    @State private var thresholdText = ""

    var body: some View {
        Form {
            Section("Notify me about") {
                Toggle("Current session", isOn: sessionBinding)
                Toggle("Current week", isOn: weekBinding)
            }
            Section("Thresholds") {
                TextField("Percentages", text: $thresholdText)
                    .onSubmit(commitThresholds)
                Text("Comma-separated percentages. Each threshold fires once per section, per profile, per reset window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Apply", action: commitThresholds)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { thresholdText = model.preferences.thresholds.map(String.init).joined(separator: ", ") }
    }

    private var sessionBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.notifyOnSession },
            set: { enable in
                model.preferences.notifyOnSession = enable
                if enable { Task { await model.notifications.ensureAuthorized() } }
            })
    }

    private var weekBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.notifyOnWeek },
            set: { enable in
                model.preferences.notifyOnWeek = enable
                if enable { Task { await model.notifications.ensureAuthorized() } }
            })
    }

    private func commitThresholds() {
        let values = thresholdText
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard !values.isEmpty else {
            thresholdText = model.preferences.thresholds.map(String.init).joined(separator: ", ")
            return
        }
        model.preferences.setThresholds(values)
        thresholdText = model.preferences.thresholds.map(String.init).joined(separator: ", ")
    }
}
