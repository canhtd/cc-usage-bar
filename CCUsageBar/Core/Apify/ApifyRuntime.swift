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
    let tokenStore: ApifyTokenStore
    /// actor id -> display name. Names change too rarely to be worth expiring.
    var actorNames: [String: String] = [:]
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "apify")

    /// How many runs the popover shows.
    static let shownRunCount = 3
    /// Actor-name lookups allowed per poll. A page of 25 runs from 25 different actors
    /// would otherwise mean 25 extra requests before the first figure appears.
    static let actorNameBudget = 6

    init(
        preferences: ApifyPreferences = ApifyPreferences(),
        client: ApifyClient = ApifyClient(),
        tokenStore: ApifyTokenStore = ApifyTokenStore()
    ) {
        self.preferences = preferences
        self.client = client
        self.tokenStore = tokenStore
        resetIdleState()
    }

    // MARK: - Module state

    var isEnabled: Bool { preferences.isEnabled }

    /// Whether a token is stored. Only meaningful while the module is on -- reading it
    /// while off would touch the keychain, which a disabled module must never do.
    var hasToken: Bool { preferences.isEnabled && tokenStore.hasToken }

    /// The percentage the menu bar may show; `nil` whenever there is nothing trustworthy,
    /// including a plan with no monthly cap, where a percentage does not exist.
    var menuBarPercent: Int? {
        guard state == .ready else { return nil }
        return usage?.percentUsed
    }

    /// Recomputes the state the module sits in when it is not mid-request.
    ///
    /// The keychain is only consulted once the module is known to be enabled, so a user who
    /// never turns Apify on is never a reason for this app to open the keychain at launch.
    func resetIdleState() {
        guard preferences.isEnabled else {
            state = .disabled
            return
        }
        switch lookupToken() {
        case .token: state = .loading
        case .missing: state = .needsToken
        case .unavailable(let status): state = .keychainUnavailable(status)
        }
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

    /// The three answers the keychain can give, kept apart so a failure is never mistaken
    /// for an empty slot.
    enum TokenLookup {
        case token(String)
        case missing
        case unavailable(OSStatus)
    }

    func lookupToken() -> TokenLookup {
        do {
            guard let token = try tokenStore.read(), !token.isEmpty else { return .missing }
            return .token(token)
        } catch ApifyTokenStore.StoreError.keychain(let status) {
            log.error("keychain read failed: \(status, privacy: .public)")
            return .unavailable(status)
        } catch {
            log.error("keychain item is unreadable")
            return .unavailable(errSecInvalidData)
        }
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
        let token: String
        switch lookupToken() {
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

        isRefreshing = true
        defer { isRefreshing = false }
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
