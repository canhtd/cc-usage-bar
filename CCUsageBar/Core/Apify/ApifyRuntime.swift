import Foundation
import OSLog
import Security

/// Owns the Apify half of the app: token, polling, cached usage and error state (A2).
///
/// Deliberately independent of `ProfileRuntime`. `AppModel` polls the two on the same
/// cadence but in separate tasks, so a network failure here never delays or blanks the
/// Claude numbers, and a stuck PTY never stops Apify from updating.
@MainActor
@Observable
final class ApifyRuntime {
    let preferences: ApifyPreferences
    private(set) var usage: ApifyUsage?
    private(set) var state: ApifyState = .disabled
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    /// Filled in by "Test connection"; shown next to the token field.
    var accountUsername: String?

    let client: ApifyClient
    let tokenStore: any ApifyTokenStoring
    /// What the last completed keychain read said. Presence only, never the token itself:
    /// this type holds the secret for the length of one request and no longer. `nil` until
    /// the first read has come back, which is a wait the UI has to be able to describe.
    private(set) var tokenPresence: TokenPresence?
    /// The keychain read in flight, if any. A scheduler tick that arrives while the
    /// keychain dialog is still up joins it instead of queueing a second blocking call.
    var lookupTask: Task<TokenLookup, Never>?
    /// actor id -> display name. Names change too rarely to be worth expiring.
    var actorNames: [String: String] = [:]
    /// Not private: `ApifyRuntime+Token` logs keychain failures through it.
    let log = Logger(subsystem: "com.danny.ccusagebar", category: "apify")

    /// How many runs the popover shows.
    static let shownRunCount = 3
    /// Actor-name lookups allowed per poll. A page of 25 runs from 25 different actors
    /// would otherwise mean 25 extra requests before the first figure appears.
    static let actorNameBudget = 6

    init(
        preferences: ApifyPreferences = ApifyPreferences(),
        client: ApifyClient = ApifyClient(),
        tokenStore: any ApifyTokenStoring = ApifyTokenStore()
    ) {
        self.preferences = preferences
        self.client = client
        self.tokenStore = tokenStore
        resetIdleState()
    }

    // MARK: - Module state

    var isEnabled: Bool { preferences.isEnabled }

    // `state` and `tokenPresence` stay `private(set)` so no view can write them. These two
    // seams exist because `ApifyRuntime+Token` -- which owns the keychain half of the state
    // machine -- is a separate file, and `private(set)` does not reach across files.
    func setState(_ new: ApifyState) { state = new }
    func setTokenPresence(_ new: TokenPresence?) { tokenPresence = new }

    /// The percentage the menu bar may show; `nil` whenever there is nothing trustworthy,
    /// including a plan with no monthly cap, where a percentage does not exist.
    var menuBarPercent: Int? {
        guard state == .ready else { return nil }
        return usage?.percentUsed
    }

    func setEnabled(_ enabled: Bool) {
        preferences.isEnabled = enabled
        if !enabled {
            usage = nil
            lastUpdated = nil
            accountUsername = nil
        }
        resetIdleState()
    }

    // MARK: - Polling

    /// One poll. Returns the fresh usage on success and `nil` otherwise; never throws, so
    /// a caller cannot accidentally let an Apify failure escape into the Claude path.
    @discardableResult
    func refresh() async -> ApifyUsage? {
        #if DEBUG
            // A fixture-backed runtime holds its canned reading and never polls.
            if isFixtureBacked { return nil }
        #endif
        guard preferences.isEnabled else {
            usage = nil
            state = .disabled
            return nil
        }
        guard !isRefreshing else { return nil }
        isRefreshing = true
        defer { isRefreshing = false }

        // The keychain read is awaited, not called inline, and can take as long as the user
        // leaves the confidential-information dialog up. `isRefreshing` is already set, so
        // the next scheduler tick returns here rather than stacking another blocked read.
        if usage == nil { state = .waitingForKeychain }
        let token: String
        switch await lookupToken() {
        case .token(let value):
            token = value
        case .missing:
            usage = nil
            state = .needsToken
            return nil
        case .unavailable(let status):
            // The last good figure stays on screen: the keychain being unavailable says
            // nothing about whether the number is still roughly right.
            state = .keychainUnavailable(status)
            return nil
        }

        if usage == nil { state = .loading }

        do {
            let limits = try await client.limits(token: token)
            // Runs are fetched second and failure-tolerant: an error listing runs must not
            // blank a budget figure that was fetched successfully.
            let runs = preferences.needsRuns ? await loadRuns(token: token) : []
            let fresh = ApifyUsage(
                monthlyUsageUsd: limits.current.monthlyUsageUsd,
                maxMonthlyUsageUsd: limits.limits.maxMonthlyUsageUsd,
                cycleStartAt: limits.monthlyUsageCycle.startAt,
                cycleEndAt: limits.monthlyUsageCycle.endAt,
                capturedAt: Date(),
                runs: runs)
            usage = fresh
            lastUpdated = fresh.capturedAt
            state = .ready
            return fresh
        } catch let error as ApifyClient.ClientError {
            log.error("apify poll failed: \(String(describing: error), privacy: .public)")
            state = .failed(error)
            return nil
        } catch {
            log.error("apify poll failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(.transport(error.localizedDescription))
            return nil
        }
    }

    #if DEBUG
        /// Set by `loadFixture`; suppresses polling for the whole life of the runtime.
        private(set) var isFixtureBacked = false

        /// Loads a decoded fixture so the popover can be screenshotted without a token.
        func loadFixture(_ fixture: ApifyUsage) {
            isFixtureBacked = true
            usage = fixture
            lastUpdated = fixture.capturedAt
            state = .ready
        }
    #endif
}
