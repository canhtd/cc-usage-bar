import Foundation

/// Fetching and naming recent Apify runs (A2/A4).
extension ApifyRuntime {
    /// Recent runs with actor names resolved. Keeps the previous list on failure, so a
    /// runs error never blanks a budget figure that was fetched successfully.
    func loadRuns(token: String) async -> [ApifyRunSummary] {
        guard let runs = try? await client.runs(token: token) else {
            return usage?.runs ?? []
        }
        await resolveActorNames(for: runs, token: token)
        return runs.map { run in
            ApifyRunSummary(
                id: run.id,
                actorName: actorNames[run.actId] ?? run.actId,
                status: run.status,
                costUsd: run.usageTotalUsd ?? 0,
                startedAt: run.startedAt)
        }
    }

    /// Looks up the names this poll actually needs, concurrently and under a budget.
    ///
    /// "Only when needed" (A2) means the runs the popover shows plus any run that will
    /// raise an alert; the rest fall back to the actor id and pick up a real name on a
    /// later poll, once the budget covers them. Serially these lookups added a round trip
    /// each to every refresh, so they run as a group.
    private func resolveActorNames(for runs: [ApifyRun], token: String) async {
        let wanted = neededActorIDs(in: runs)
        guard !wanted.isEmpty else { return }

        let client = self.client
        let resolved = await withTaskGroup(of: (String, String)?.self) { group in
            for id in wanted {
                group.addTask {
                    guard let actor = try? await client.actor(token: token, id: id) else {
                        return nil
                    }
                    return (id, actor.displayName)
                }
            }
            var names: [String: String] = [:]
            for await pair in group {
                if let pair { names[pair.0] = pair.1 }
            }
            return names
        }
        for (id, name) in resolved { actorNames[id] = name }
    }

    /// Uncached actor ids worth a request this poll, in run order, capped.
    private func neededActorIDs(in runs: [ApifyRun]) -> [String] {
        let shown = Set(runs.prefix(Self.shownRunCount).map(\.id))
        let minimum = preferences.runCostUsd
        var seen = Set<String>()
        var wanted: [String] = []
        for run in runs {
            let isNeeded = shown.contains(run.id)
                || (preferences.notifyRun && minimum > 0 && (run.usageTotalUsd ?? 0) >= minimum)
            guard isNeeded, actorNames[run.actId] == nil, seen.insert(run.actId).inserted else {
                continue
            }
            wanted.append(run.actId)
            if wanted.count == Self.actorNameBudget { break }
        }
        return wanted
    }
}
