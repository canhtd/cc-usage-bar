import Foundation
import Testing

@testable import CCUsageBar

/// Runtime behaviour that the safety story depends on: no requests while disabled, and a
/// keychain failure that is reported rather than disguised.
@MainActor
@Suite("Apify runtime")
struct ApifyRuntimeTests {
    /// Preferences on a throwaway suite, so a test never touches the user's settings.
    private func makePreferences(enabled: Bool) -> ApifyPreferences {
        let name = "com.danny.ccusagebar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let preferences = ApifyPreferences(defaults: defaults)
        preferences.isEnabled = enabled
        return preferences
    }

    /// A keychain item under a throwaway service, deleted by the caller.
    private func makeStore() -> ApifyTokenStore {
        ApifyTokenStore(service: "com.danny.ccusagebar.apify.test.\(UUID().uuidString)")
    }

    @Test("a disabled module makes no request at all, not even Test connection")
    func disabledModuleMakesNoRequest() async throws {
        let store = makeStore()
        try store.save("test-token-not-a-real-credential")
        defer { try? store.delete() }

        let (client, recorder) = ApifyStubProtocol.makeClient()
        let runtime = ApifyRuntime(
            preferences: makePreferences(enabled: false), client: client, tokenStore: store)

        #expect(runtime.state == .disabled)
        let polled = await runtime.refresh()
        #expect(polled == nil)
        let result = await runtime.testConnection()
        #expect(result == .failure(.moduleDisabled))
        #expect(recorder.count == 0, "a disabled module reached the network")
    }

    @Test("enabling with a stored token polls and reports the budget")
    func enabledModulePolls() async throws {
        let store = makeStore()
        try store.save("test-token-not-a-real-credential")
        defer { try? store.delete() }

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
            preferences: makePreferences(enabled: true), client: client, tokenStore: store)
        let usage = try #require(await runtime.refresh())
        #expect(usage.percentUsed == 50)
        #expect(runtime.state == .ready)
        #expect(runtime.menuBarPercent == 50)
    }

    @Test("no stored token means needsToken, and still no request")
    func missingTokenDoesNotPoll() async {
        let store = makeStore()
        let (client, recorder) = ApifyStubProtocol.makeClient()
        let runtime = ApifyRuntime(
            preferences: makePreferences(enabled: true), client: client, tokenStore: store)

        #expect(runtime.state == .needsToken)
        let polled = await runtime.refresh()
        #expect(polled == nil)
        #expect(runtime.state == .needsToken)
        #expect(recorder.count == 0)
    }

    @Test("a keychain failure is reported as itself, not as \"you have no token\"")
    func keychainFailureIsDistinct() throws {
        // errSecItemNotFound is the only status that means "no token"; everything else has
        // to keep `hasToken` true so the UI offers Remove rather than a setup prompt.
        #expect(ApifyState.keychainUnavailable(errSecInteractionNotAllowed) != .needsToken)
        let message = try #require(
            ApifyState.keychainUnavailable(errSecInteractionNotAllowed).message)
        #expect(message.contains("Keychain unavailable"))
        #expect(ApifyState.keychainUnavailable(errSecInteractionNotAllowed).needsSettings == false)
    }

    @Test("a non-UTF8 keychain payload throws instead of reporting an empty slot")
    func nonUTF8PayloadThrows() throws {
        let store = makeStore()
        defer { try? store.delete() }
        // 0xFF is not valid UTF-8 in any position.
        try store.saveRawForTesting(Data([0xFF, 0xFE, 0xFF]))
        #expect(throws: ApifyTokenStore.StoreError.invalidData) { _ = try store.read() }
        #expect(store.hasToken, "an unreadable item must not look like an empty one")
    }

    @Test("the round trip still works, and delete clears it")
    func tokenRoundTrip() throws {
        let store = makeStore()
        defer { try? store.delete() }
        try store.save("  test-token-not-a-real-credential  ")
        #expect(try store.read() == "test-token-not-a-real-credential")
        try store.delete()
        #expect(try store.read() == nil)
        #expect(store.hasToken == false)
    }

    @Test("actor-name lookups are capped, so one poll cannot fan out to a request per run")
    func actorNameBudgetIsRespected() async throws {
        let store = makeStore()
        try store.save("test-token-not-a-real-credential")
        defer { try? store.delete() }

        let (client, recorder) = ApifyStubProtocol.makeClient()
        recorder.enqueue(.json(#"{"data":{"current":{"monthlyUsageUsd":250},"limits":{"maxMonthlyUsageUsd":500},"monthlyUsageCycle":{"startAt":"2026-08-01T00:00:00.000Z","endAt":"2026-09-01T00:00:00.000Z"}}}"#))
        // Ten runs from ten different actors, every one of them above the alert threshold,
        // so all ten "need" a name and the budget is the only thing holding them back.
        recorder.enqueue(.json(#"{"data": {"items": [{"id": "run-0", "actId": "act-0", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-1", "actId": "act-1", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-2", "actId": "act-2", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-3", "actId": "act-3", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-4", "actId": "act-4", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-5", "actId": "act-5", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-6", "actId": "act-6", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-7", "actId": "act-7", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-8", "actId": "act-8", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}, {"id": "run-9", "actId": "act-9", "status": "SUCCEEDED", "startedAt": "2026-08-15T09:00:00.000Z", "usageTotalUsd": 12.5}]}}"#))
        for index in 0..<12 {
            recorder.enqueue(
                .json(#"{"data":{"id":"act","name":"a\#(index)","title":"Actor \#(index)"}}"#))
        }

        let runtime = ApifyRuntime(
            preferences: makePreferences(enabled: true), client: client, tokenStore: store)
        let usage = try #require(await runtime.refresh())

        let actorLookups = recorder.urls.filter { $0.path.hasPrefix("/v2/acts/") }
        #expect(actorLookups.count == ApifyRuntime.actorNameBudget, "made \(actorLookups.count)")
        #expect(usage.runs.count == 10, "every run is still listed, named or not")
        // The ones that missed out fall back to the actor id and get a name on a later poll.
        #expect(usage.runs.contains { $0.actorName.hasPrefix("act-") })
    }
}
