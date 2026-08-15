import Foundation
import OSLog

/// What the Apify module is currently doing, as the UI needs to describe it.
nonisolated enum ApifyState: Equatable, Sendable {
    case disabled
    case needsToken
    case loading
    case ready
    case failed(ApifyClient.ClientError)

    var isLoading: Bool { self == .loading }

    var message: String? {
        switch self {
        case .disabled, .ready: return nil
        case .needsToken: return ApifyClient.ClientError.noToken.message
        case .loading: return "Loading Apify usage…"
        case .failed(let error): return error.message
        }
    }

    /// Whether the message should send the user to Settings rather than just inform them.
    var needsSettings: Bool {
        switch self {
        case .needsToken: return true
        case .failed(let error): return error == .unauthorized
        default: return false
        }
    }
}

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
    /// Filled in by "Test connection"; shown next to the token field.
    var accountUsername: String?

    let client: ApifyClient
    let tokenStore: ApifyTokenStore
    /// actor id -> display name. Names never change often enough to be worth expiring.
    private var actorNames: [String: String] = [:]
    private var isRefreshing = false
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "apify")

    /// How many runs the popover shows, and therefore how many names are worth resolving.
    static let shownRunCount = 3

    init(
        preferences: ApifyPreferences = ApifyPreferences(),
        client: ApifyClient = ApifyClient(),
        tokenStore: ApifyTokenStore = ApifyTokenStore()
    ) {
        self.preferences = preferences
        self.client = client
        self.tokenStore = tokenStore
        state = Self.idleState(isEnabled: preferences.isEnabled, hasToken: tokenStore.hasToken)
    }

    private static func idleState(isEnabled: Bool, hasToken: Bool) -> ApifyState {
        guard isEnabled else { return .disabled }
        return hasToken ? .loading : .needsToken
    }

    // MARK: - Module state

    var isEnabled: Bool { preferences.isEnabled }
    var hasToken: Bool { tokenStore.hasToken }

    /// The percentage the menu bar may show; `nil` whenever there is nothing trustworthy,
    /// including a plan with no monthly cap, where a percentage does not exist.
    var menuBarPercent: Int? {
        guard state == .ready else { return nil }
        return usage?.percentUsed
    }

    /// Recomputes the state the module sits in when it is not mid-request.
    func resetIdleState() {
        state = Self.idleState(isEnabled: preferences.isEnabled, hasToken: hasToken)
    }

    func setEnabled(_ enabled: Bool) {
        preferences.isEnabled = enabled
        if !enabled {
            usage = nil
            lastUpdated = nil
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
        let token = (try? tokenStore.read()) ?? nil
        guard let token, !token.isEmpty else {
            usage = nil
            state = .needsToken
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

    /// Recent runs with actor names resolved. Keeps the previous list on failure.
    private func loadRuns(token: String) async -> [ApifyRunSummary] {
        guard let runs = try? await client.runs(token: token) else {
            log.debug("could not list runs; keeping the previous list")
            return usage?.runs ?? []
        }
        let shown = Set(runs.prefix(Self.shownRunCount).map(\.id))
        let minimum = preferences.runCostUsd
        var summaries: [ApifyRunSummary] = []
        for run in runs {
            let cost = run.usageTotalUsd ?? 0
            // "Lazily, only when needed" (A2): a run nobody will see and nobody will alert
            // on does not justify a request. It falls back to the cached name or the id.
            let needsName = shown.contains(run.id)
                || (preferences.notifyRun && minimum > 0 && cost >= minimum)
            let name = needsName
                ? await actorName(for: run.actId, token: token)
                : (actorNames[run.actId] ?? run.actId)
            summaries.append(
                ApifyRunSummary(
                    id: run.id, actorName: name, status: run.status, costUsd: cost,
                    startedAt: run.startedAt))
        }
        return summaries
    }

    private func actorName(for id: String, token: String) async -> String {
        if let cached = actorNames[id] { return cached }
        guard let actor = try? await client.actor(token: token, id: id) else { return id }
        actorNames[id] = actor.displayName
        return actor.displayName
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
