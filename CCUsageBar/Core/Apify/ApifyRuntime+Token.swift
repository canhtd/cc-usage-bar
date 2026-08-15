import Foundation

/// Token handling and alert generation, split out to keep `ApifyRuntime` under the file
/// size limit. Both are user-facing entry points rather than part of the polling loop.
extension ApifyRuntime {
    /// Stores the token, returning a message if the keychain refused.
    func saveToken(_ token: String) -> String? {
        do {
            try tokenStore.save(token)
            accountUsername = nil
            resetIdleState()
            return nil
        } catch {
            return "The keychain refused to store the token (\(error))."
        }
    }

    @discardableResult
    func clearToken() -> String? {
        saveToken("")
    }

    /// `GET /v2/users/me`, so the user can prove the token works before trusting the bar.
    func testConnection() async -> Result<String, ApifyClient.ClientError> {
        let token = (try? tokenStore.read()) ?? nil
        guard let token, !token.isEmpty else { return .failure(.noToken) }
        do {
            let user = try await client.user(token: token)
            accountUsername = user.username
            return .success(user.username)
        } catch let error as ApifyClient.ClientError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    // MARK: - Alerts

    /// Runs the three pure rules over a fresh poll, honouring the per-rule toggles (A3).
    ///
    /// `samples` is the Apify spend history inside the spike window; the caller supplies it
    /// because `HistoryStore` owns it and this type deliberately holds no history.
    func alerts(
        for usage: ApifyUsage, samples: [ApifySample], now: Date = Date()
    ) -> [PendingAlert] {
        var pending: [PendingAlert] = []
        if preferences.notifyBudget {
            pending += ApifyRules.budgetAlerts(
                usage: usage, thresholds: preferences.budgetThresholds)
        }
        if preferences.notifySpike,
            let spike = ApifyRules.spikeAlert(
                usage: usage, samples: samples, spikePercent: preferences.spikePercent, now: now) {
            pending.append(spike)
        }
        if preferences.notifyRun {
            pending += ApifyRules.expensiveRunAlerts(
                runs: usage.runs, minimumUsd: preferences.runCostUsd)
        }
        return pending
    }
}
