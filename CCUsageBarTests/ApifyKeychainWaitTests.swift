import Foundation
import Testing

@testable import CCUsageBar

/// A token store that does not answer until the test lets it -- the keychain dialog, in a
/// test. `read()` is where the real store blocks for as long as the user takes to answer
/// "CCUsageBar wants to use your confidential information".
nonisolated final class BlockingTokenStore: ApifyTokenStoring {
    private let gate = Gate()
    private let token: String

    init(token: String = "test-token-not-a-real-credential") {
        self.token = token
    }

    func read() async throws -> String? {
        await gate.wait()
        return token
    }

    func save(_ token: String) async throws {}
    func delete() async throws {}

    /// Lets every pending read through, as answering the dialog would.
    func answer() async { await gate.open() }

    private actor Gate {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func open() {
            isOpen = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }
}

/// The bug: `ApifyTokenStore.read()` ran inline on the main actor, so the keychain dialog
/// that macOS shows after every reinstall froze the entire app -- menu bar, popover, and
/// the Claude refresh with it -- until somebody answered it (observed: six minutes).
@MainActor
@Suite("Apify keychain wait")
struct ApifyKeychainWaitTests {
    private func makePreferences() -> ApifyPreferences {
        let name = "com.danny.ccusagebar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = ApifyPreferences(defaults: defaults)
        preferences.isEnabled = true
        return preferences
    }

    @Test("A keychain read that has not come back leaves the Claude refresh running")
    func pendingKeychainReadDoesNotStallClaude() async throws {
        let store = BlockingTokenStore()
        let (client, recorder) = ApifyStubProtocol.makeClient()
        recorder.enqueue(
            .json(
                #"""
                {"data":{"current":{"monthlyUsageUsd":250},
                "limits":{"maxMonthlyUsageUsd":500},
                "monthlyUsageCycle":{"startAt":"2026-08-01T00:00:00.000Z",
                "endAt":"2026-09-01T00:00:00.000Z"}}}
                """#))
        recorder.enqueue(.json(#"{"data":{"items":[]}}"#))

        let runtime = ApifyRuntime(
            preferences: makePreferences(), client: client, tokenStore: store)
        let poll = Task { await runtime.refresh() }
        #expect(await untilTrue { runtime.isRefreshing })
        // Neutral while the dialog is up: waiting is not a failure, and no request went out.
        #expect(runtime.state == .waitingForKeychain)
        #expect(recorder.count == 0)

        // Meanwhile a whole `/usage` capture runs to completion on the same main actor.
        let factory = FakePTYFactory()
        let session = UsageSession(
            profileID: UUID(), configDirectory: nil, makeProcess: { factory.make() })
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { factory.made.first?.isRunning == true })
        let fake = try #require(factory.made.first)
        fake.emit(SessionScreens.ready)
        #expect(await untilTrue { fake.writtenText.contains("/usage") })
        fake.emit(SessionScreens.panel)
        let capture = try await query.value
        #expect(capture.snapshot.sessionSection?.percentUsed == 48)
        #expect(runtime.isRefreshing, "the Apify poll should still be waiting on the keychain")

        // Answering the dialog lets the poll finish as usual.
        await store.answer()
        let usage = try #require(await poll.value)
        #expect(usage.percentUsed == 50)
        #expect(runtime.state == .ready)
    }
}
