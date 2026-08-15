import SwiftUI

/// Settings › Apify (A3): enable, token, connection test, and the three rules.
struct ApifySettingsView: View {
    @Bindable var model: AppModel
    @State private var tokenText = ""
    @State private var thresholdText = ""
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult: Equatable {
        case success(String)
        case failure(String)
    }

    private var apify: ApifyRuntime { model.apify }
    private var preferences: ApifyPreferences { model.apify.preferences }

    var body: some View {
        Form {
            Section {
                Toggle("Monitor Apify usage", isOn: enabledBinding)
                Text("Adds Apify spend to the menu bar and the popover, and enables the alert rules below. Nothing is requested while this is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            tokenSection
            if preferences.isEnabled {
                rulesSection
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadFields)
    }

    // MARK: - Token

    private var tokenSection: some View {
        Section("API token") {
            SecureField("Apify API token", text: $tokenText)
                .onSubmit(saveToken)
            HStack {
                if let result = testResult { resultLabel(result) }
                Spacer()
                Button("Save", action: saveToken)
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Test connection", action: testConnection)
                    .disabled(isTesting || !apify.hasToken)
                if isTesting { ProgressView().controlSize(.small) }
            }
            Text("Stored in your keychain, sent only to api.apify.com. Create one under Settings → API & Integrations in the Apify console.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if apify.hasToken {
                Button("Remove token", role: .destructive) {
                    apify.clearToken()
                    tokenText = ""
                    testResult = nil
                }
            }
        }
    }

    @ViewBuilder
    private func resultLabel(_ result: TestResult) -> some View {
        switch result {
        case .success(let username):
            Label("Connected as \(username)", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        Section("Alerts") {
            Toggle("Budget thresholds", isOn: bind(\.notifyBudget))
            TextField("Percentages", text: $thresholdText)
                .onSubmit(commitThresholds)
                .disabled(!preferences.notifyBudget)
            Toggle("Spending spike", isOn: bind(\.notifySpike))
            // Not `LabeledContent`: it lays the field's own title out as a second label,
            // which wraps a word like "Percent" down the middle of the row.
            numberRow(
                "Spike is", suffix: "% of budget in an hour",
                value: bind(\.spikePercent), fractionDigits: 0...1,
                enabled: preferences.notifySpike)
            Toggle("Expensive runs", isOn: bind(\.notifyRun))
            numberRow(
                "Alert above", prefix: "$", suffix: "per run",
                value: bind(\.runCostUsd), fractionDigits: 0...2,
                enabled: preferences.notifyRun)
            Text("Each alert fires once: per threshold per billing cycle, once an hour for a spike, and once per run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numberRow(
        _ title: String, prefix: String? = nil, suffix: String,
        value: Binding<Double>, fractionDigits: ClosedRange<Int>, enabled: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 8)
            if let prefix { Text(prefix).foregroundStyle(.secondary) }
            TextField(
                "", value: value, format: .number.precision(.fractionLength(fractionDigits))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .disabled(!enabled)
    }

    // MARK: - Actions

    private func loadFields() {
        thresholdText = preferences.budgetThresholds.map(String.init).joined(separator: ", ")
        if let username = apify.accountUsername { testResult = .success(username) }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.isEnabled },
            set: { enable in
                apify.setEnabled(enable)
                if enable {
                    Task { await model.notifications.ensureAuthorized() }
                    model.refreshApify()
                }
            })
    }

    private func bind<Value>(
        _ keyPath: ReferenceWritableKeyPath<ApifyPreferences, Value>
    ) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { preferences[keyPath: keyPath] = $0 })
    }

    private func saveToken() {
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        if let error = apify.saveToken(token) {
            testResult = .failure(error)
            return
        }
        // Never leave the token sitting in view state once the keychain owns it.
        tokenText = ""
        testResult = nil
        model.refreshApify()
    }

    private func testConnection() {
        isTesting = true
        Task {
            switch await apify.testConnection() {
            case .success(let username): testResult = .success(username)
            case .failure(let error): testResult = .failure(error.message)
            }
            isTesting = false
        }
    }

    private func commitThresholds() {
        let values = thresholdText.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if !values.isEmpty { preferences.setBudgetThresholds(values) }
        thresholdText = preferences.budgetThresholds.map(String.init).joined(separator: ", ")
    }
}
