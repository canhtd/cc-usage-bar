import Foundation

/// Apify wraps every v2 response in a `data` object.
nonisolated struct ApifyEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload
}

/// `GET /v2/users/me` -- used only by "Test connection".
nonisolated struct ApifyUser: Decodable, Sendable, Equatable {
    let username: String
}

/// `GET /v2/users/me/limits`.
nonisolated struct ApifyLimits: Decodable, Sendable, Equatable {
    struct Current: Decodable, Sendable, Equatable {
        let monthlyUsageUsd: Double
    }
    struct Limits: Decodable, Sendable, Equatable {
        /// Absent on plans without a hard cap, in which case there is no percentage.
        let maxMonthlyUsageUsd: Double?
    }
    struct Cycle: Decodable, Sendable, Equatable {
        let startAt: Date
        let endAt: Date
    }

    let current: Current
    let limits: Limits
    let monthlyUsageCycle: Cycle
}

/// One entry of `GET /v2/actor-runs`.
nonisolated struct ApifyRun: Decodable, Sendable, Equatable {
    let id: String
    let actId: String
    let status: String
    let startedAt: Date?
    /// Absent on a run that has not accrued cost yet.
    let usageTotalUsd: Double?
}

nonisolated struct ApifyRunPage: Decodable, Sendable {
    let items: [ApifyRun]
}

/// `GET /v2/acts/{id}`, fetched lazily to turn an actor id into a name.
nonisolated struct ApifyActor: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let title: String?

    var displayName: String { title ?? name }
}

/// A run as the UI shows it: the actor resolved to a name, cost never optional.
nonisolated struct ApifyRunSummary: Sendable, Equatable, Identifiable {
    var id: String
    var actorName: String
    var status: String
    var costUsd: Double
    var startedAt: Date?

    /// The one URL shape this app ever opens (A3/R-A3).
    var consoleURL: URL? {
        URL(string: "https://console.apify.com/actors/runs/\(id)")
    }
}

/// Everything the UI and the rules need from one Apify poll.
nonisolated struct ApifyUsage: Sendable, Equatable {
    var monthlyUsageUsd: Double
    /// `nil` on a plan with no monthly cap: there is a spend, but no percentage.
    var maxMonthlyUsageUsd: Double?
    var cycleStartAt: Date
    var cycleEndAt: Date
    var capturedAt: Date
    var runs: [ApifyRunSummary]

    /// Whole percent of the monthly budget, or `nil` when the plan has no cap.
    var percentUsed: Int? {
        guard let max = maxMonthlyUsageUsd, max > 0 else { return nil }
        return Int((monthlyUsageUsd / max * 100).rounded())
    }

    /// Whole days left in the billing cycle, never negative.
    func daysRemaining(now: Date = Date()) -> Int {
        max(0, Int((cycleEndAt.timeIntervalSince(now) / 86400).rounded(.up)))
    }

    /// Identity of the billing cycle, used in alert keys so a new cycle re-arms them.
    var cycleKey: String { String(Int(cycleStartAt.timeIntervalSince1970.rounded())) }
}
