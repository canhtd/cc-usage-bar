#if DEBUG

    import Foundation

    /// Builds an `AppModel` whose Apify half is backed by `ApifyFixture` instead of the
    /// network, so the Apify UI can be screenshotted on a machine with no Apify token.
    ///
    /// Debug builds only, and carefully side-effect free: the Apify preferences live in a
    /// throwaway `UserDefaults` suite and the seeded history goes to a temporary file, so a
    /// capture run cannot enable the module for real or write fabricated spend into the
    /// user's own history.
    @MainActor
    enum DebugFixtureModel {
        private static let suiteName = "com.danny.ccusagebar.fixture"

        static func make() -> AppModel {
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            let preferences = ApifyPreferences(defaults: defaults)
            preferences.isEnabled = true

            // The real history is copied, not opened: the capture appends fabricated Apify
            // spend, and that must never land in the file the app actually keeps. Copying
            // rather than starting empty keeps the real Claude series in the screenshot.
            let historyURL = FileManager.default.temporaryDirectory
                .appending(path: "ccusagebar-fixture-history.jsonl")
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.copyItem(at: AppSupport.file("history.jsonl"), to: historyURL)

            let runtime = ApifyRuntime(preferences: preferences)
            let model = AppModel(history: HistoryStore(url: historyURL), apify: runtime)
            guard let usage = try? ApifyFixture.usage() else { return model }
            runtime.loadFixture(usage)
            Task { await seed(model.history, endingAt: usage) }
            return model
        }

        /// A day of spend leading up to the fixture reading, so the sparkline has a shape.
        private static func seed(_ history: HistoryStore, endingAt usage: ApifyUsage) async {
            let steps = 14
            for index in 0..<steps {
                let progress = Double(index) / Double(steps)
                var sample = usage
                sample.capturedAt = usage.capturedAt
                    .addingTimeInterval(-24 * 3600 * (1 - progress))
                // Slightly convex, so the line climbs rather than looking like a ramp.
                sample.monthlyUsageUsd = usage.monthlyUsageUsd * (0.72 + 0.28 * progress * progress)
                await history.recordApify(sample)
            }
            await history.recordApify(usage)
        }
    }

#endif
