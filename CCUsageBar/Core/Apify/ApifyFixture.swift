#if DEBUG

    import Foundation

    /// Canned Apify responses, so the popover and the settings tab can be screenshotted on
    /// a machine that has no Apify token.
    ///
    /// Debug builds only: a shipping binary must not carry fabricated usage figures that
    /// could be mistaken for a real reading. The payloads are the real wire shapes, kept
    /// deliberately noisy -- extra fields the app ignores, four-decimal dollar amounts,
    /// fractional-second timestamps -- because the same JSON backs the decoding tests, and
    /// a fixture that is tidier than reality tests nothing.
    nonisolated enum ApifyFixture {
        /// Hidden launch argument that loads this fixture instead of polling.
        static let argument = "--apify-fixture"

        static let limitsJSON = """
            {
              "data": {
                "monthlyUsageCycle": {
                  "startAt": "2026-08-01T00:00:00.000Z",
                  "endAt": "2026-09-01T00:00:00.000Z"
                },
                "current": {
                  "monthlyUsageUsd": 261.4832,
                  "monthlyActorComputeUnits": 812.5,
                  "monthlyExternalDataTransferGbytes": 4.25
                },
                "limits": {
                  "maxMonthlyUsageUsd": 500,
                  "maxMonthlyActorComputeUnits": 2000,
                  "maxActorMemoryGbytes": 32
                }
              }
            }
            """

        static let runsJSON = """
            {
              "data": {
                "total": 3,
                "count": 3,
                "desc": true,
                "items": [
                  {
                    "id": "HG7ML7M8z78YcAPEB",
                    "actId": "moJRLRc85AitArpNN",
                    "status": "RUNNING",
                    "startedAt": "2026-08-15T09:12:44.123Z",
                    "usageTotalUsd": 6.4213
                  },
                  {
                    "id": "pTn2xW1gQ0sRvKdLe",
                    "actId": "aYG0l9s7dTfGqUjPn",
                    "status": "SUCCEEDED",
                    "startedAt": "2026-08-15T07:40:02.000Z",
                    "finishedAt": "2026-08-15T08:02:19.000Z",
                    "usageTotalUsd": 1.8047
                  },
                  {
                    "id": "kQ4bV8zNmH1cYtRoW",
                    "actId": "moJRLRc85AitArpNN",
                    "status": "FAILED",
                    "startedAt": "2026-08-14T22:05:11.500Z",
                    "usageTotalUsd": 0.2109
                  }
                ]
              }
            }
            """

        /// Actor ids resolved to names, standing in for the lazy `GET /v2/acts/{id}` calls.
        static let actorNames = [
            "moJRLRc85AitArpNN": "Website Content Crawler",
            "aYG0l9s7dTfGqUjPn": "Google Maps Scraper",
        ]

        static func decodeLimits() throws -> ApifyLimits {
            try ApifyClient.decoder.decode(
                ApifyEnvelope<ApifyLimits>.self, from: Data(limitsJSON.utf8)
            ).data
        }

        static func decodeRuns() throws -> [ApifyRun] {
            try ApifyClient.decoder.decode(
                ApifyEnvelope<ApifyRunPage>.self, from: Data(runsJSON.utf8)
            ).data.items
        }

        /// The fixture as the UI consumes it.
        static func usage(now: Date = Date()) throws -> ApifyUsage {
            let limits = try decodeLimits()
            let runs = try decodeRuns().map { run in
                ApifyRunSummary(
                    id: run.id, actorName: actorNames[run.actId] ?? run.actId,
                    status: run.status, costUsd: run.usageTotalUsd ?? 0, startedAt: run.startedAt)
            }
            return ApifyUsage(
                monthlyUsageUsd: limits.current.monthlyUsageUsd,
                maxMonthlyUsageUsd: limits.limits.maxMonthlyUsageUsd,
                cycleStartAt: limits.monthlyUsageCycle.startAt,
                cycleEndAt: limits.monthlyUsageCycle.endAt,
                capturedAt: now,
                runs: runs)
        }
    }

#endif
