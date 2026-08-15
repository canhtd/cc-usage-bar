import Foundation
import OSLog
import Security

/// Token handling and alert generation, split out to keep `ApifyRuntime` under the file
/// size limit. Both are user-facing entry points rather than part of the polling loop.
extension ApifyRuntime {
    /// The three answers the keychain can give, kept apart so a failure is never mistaken
    /// for an empty slot.
    enum TokenLookup: Sendable {
        case token(String)
        case missing
        case unavailable(OSStatus)

        var presence: ApifyRuntime.TokenPresence {
            switch self {
            case .token: return .present
            case .missing: return .missing
            case .unavailable(let status): return .unavailable(status)
            }
        }
    }

    /// The same three answers with the secret left out, so it can be observed by views.
    enum TokenPresence: Equatable, Sendable {
        case present
        case missing
        case unavailable(OSStatus)

        /// Whether the UI should act as though a token is stored. An unavailable keychain
        /// answers `true`: presenting a locked or broken keychain as "you have not set a
        /// token yet" hides the real fault and offers a fix that cannot work.
        var impliesToken: Bool { self != .missing }
    }

    /// Whether a token is stored, as far as the last completed keychain read knows.
    ///
    /// Only meaningful while the module is on -- a disabled module never opens the
    /// keychain -- and `false` until the first read comes back, so a view body can render
    /// while the confidential-information dialog is still on screen.
    var hasToken: Bool {
        preferences.isEnabled && (tokenPresence?.impliesToken ?? false)
    }

    /// Reads the token off the main actor, coalescing concurrent callers onto one read.
    ///
    /// The returned lookup carries the secret and is meant to be used and dropped; only
    /// `tokenPresence` is kept.
    func lookupToken() async -> TokenLookup {
        if let lookupTask { return await lookupTask.value }
        let store = tokenStore
        let task = Task<TokenLookup, Never> { [log] in
            do {
                guard let token = try await store.read(), !token.isEmpty else { return .missing }
                return .token(token)
            } catch ApifyTokenStore.StoreError.keychain(let status) {
                log.error("keychain read failed: \(status, privacy: .public)")
                return .unavailable(status)
            } catch {
                log.error("keychain item is unreadable")
                return .unavailable(errSecInvalidData)
            }
        }
        lookupTask = task
        let lookup = await task.value
        lookupTask = nil
        setTokenPresence(lookup.presence)
        return lookup
    }

    /// Recomputes the state the module sits in when it is not mid-request.
    ///
    /// The keychain is only consulted once the module is known to be enabled, so a user who
    /// never turns Apify on is never a reason for this app to open the keychain at launch.
    /// The read itself is asynchronous, so this returns immediately and the state settles
    /// when the keychain answers -- possibly minutes later, if a dialog is waiting on a
    /// human. Until then the module reports `waitingForKeychain`, which is not an error.
    func resetIdleState() {
        guard preferences.isEnabled else {
            setState(.disabled)
            setTokenPresence(nil)
            return
        }
        setState(.waitingForKeychain)
        Task { [weak self] in await self?.settleIdleState() }
    }

    private func settleIdleState() async {
        let lookup = await lookupToken()
        // A poll, or a change of mind about the module, may have overtaken the read.
        guard preferences.isEnabled, !isRefreshing, state == .waitingForKeychain else { return }
        switch lookup {
        case .token: setState(.loading)
        case .missing: setState(.needsToken)
        case .unavailable(let status): setState(.keychainUnavailable(status))
        }
    }

    /// Stores the token, returning a message if the keychain refused.
    func saveToken(_ token: String) async -> String? {
        do {
            try await tokenStore.save(token)
            accountUsername = nil
            resetIdleState()
            return nil
        } catch {
            return "The keychain refused to store the token (\(error))."
        }
    }

    @discardableResult
    func clearToken() async -> String? {
        await saveToken("")
    }

    /// `GET /v2/users/me`, so the user can prove the token works before trusting the bar.
    ///
    /// Gated on the module being enabled, which keeps the Settings caption literally true:
    /// with the toggle off this app makes no request at all, not even a diagnostic one.
    func testConnection() async -> Result<String, ApifyClient.ClientError> {
        guard preferences.isEnabled else { return .failure(.moduleDisabled) }
        let token: String
        switch await lookupToken() {
        case .token(let value): token = value
        case .missing: return .failure(.noToken)
        case .unavailable(let status): return .failure(.transport("keychain error \(status)"))
        }
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
        for usage: ApifyUsage,
        samples: [ApifySample],
        lastSpikeAt: Date? = nil,
        now: Date = Date()
    ) -> [PendingAlert] {
        var pending: [PendingAlert] = []
        if preferences.notifyBudget {
            pending += ApifyRules.budgetAlerts(
                usage: usage, thresholds: preferences.budgetThresholds)
        }
        if preferences.notifySpike,
            let spike = ApifyRules.spikeAlert(
                usage: usage, samples: samples, spikePercent: preferences.spikePercent,
                lastSpikeAt: lastSpikeAt, now: now) {
            pending.append(spike)
        }
        if preferences.notifyRun {
            pending += ApifyRules.expensiveRunAlerts(
                runs: usage.runs, minimumUsd: preferences.runCostUsd)
        }
        return pending
    }
}
