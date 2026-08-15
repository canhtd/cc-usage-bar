import Foundation

/// Settings for the Apify module (A3), persisted in `UserDefaults`.
///
/// Kept apart from `AppPreferences` because the module is optional: with the toggle off,
/// nothing here is read, no request is made, and the UI shows nothing at all.
///
/// The token is not here. It lives in the keychain, via `ApifyTokenStore`.
@MainActor
@Observable
final class ApifyPreferences {
    private enum Key {
        static let enabled = "apifyEnabled"
        static let budgetThresholds = "apifyBudgetThresholds"
        static let spikePercent = "apifySpikePercent"
        static let runCostUsd = "apifyRunCostUsd"
        static let notifyBudget = "apifyNotifyBudget"
        static let notifySpike = "apifyNotifySpike"
        static let notifyRun = "apifyNotifyRun"
    }

    private let defaults: UserDefaults

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }
    var budgetThresholds: [Int] {
        didSet { defaults.set(budgetThresholds, forKey: Key.budgetThresholds) }
    }
    var spikePercent: Double { didSet { defaults.set(spikePercent, forKey: Key.spikePercent) } }
    var runCostUsd: Double { didSet { defaults.set(runCostUsd, forKey: Key.runCostUsd) } }
    var notifyBudget: Bool { didSet { defaults.set(notifyBudget, forKey: Key.notifyBudget) } }
    var notifySpike: Bool { didSet { defaults.set(notifySpike, forKey: Key.notifySpike) } }
    var notifyRun: Bool { didSet { defaults.set(notifyRun, forKey: Key.notifyRun) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        let storedThresholds = defaults.array(forKey: Key.budgetThresholds) as? [Int]
        budgetThresholds = storedThresholds?.sorted() ?? ApifyRules.defaultBudgetThresholds
        let storedSpike = defaults.object(forKey: Key.spikePercent) as? Double
        spikePercent = storedSpike ?? ApifyRules.defaultSpikePercent
        let storedRunCost = defaults.object(forKey: Key.runCostUsd) as? Double
        runCostUsd = storedRunCost ?? ApifyRules.defaultRunCostUsd
        notifyBudget = defaults.object(forKey: Key.notifyBudget) as? Bool ?? true
        notifySpike = defaults.object(forKey: Key.notifySpike) as? Bool ?? true
        notifyRun = defaults.object(forKey: Key.notifyRun) as? Bool ?? true
    }

    /// Thresholds are typed as free text; keep them sane, unique and ordered.
    func setBudgetThresholds(_ values: [Int]) {
        budgetThresholds = Set(values.map { min(max($0, 1), 100) }).sorted()
    }

    /// The popover lists recent runs whenever the module is on (A4), so the runs endpoint
    /// is called for the whole time the module is enabled. The expensive-run toggle below
    /// controls only whether those runs also raise an alert.
    var needsRuns: Bool { isEnabled }
}
