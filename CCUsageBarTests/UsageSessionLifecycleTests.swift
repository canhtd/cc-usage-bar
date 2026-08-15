import Foundation
import Testing

@testable import CCUsageBar

/// R4: one `claude` process per query, never reused.
@Suite("Usage session lifecycle")
@MainActor
struct UsageSessionLifecycleTests {
    private let ready = SessionScreens.ready
    private let panel = SessionScreens.panel

    // MARK: - No session reuse

    /// The bug: one long-lived `claude` answered `/usage` from a cache it built at launch,
    /// so the menu bar sat on 35%/3% for half an hour while the CLI itself said 65%/6%.
    /// Every refresh must therefore be a process of its own, and the previous one must be
    /// gone before the next is launched -- two live Claude Code processes is a resource
    /// leak the user never asked for.
    @Test("Two refreshes launch two processes, the first stopped before the second starts")
    func everyFetchIsAFreshProcess() async throws {
        let factory = FakePTYFactory()
        let session = UsageSession(
            profileID: UUID(), configDirectory: nil, makeProcess: { factory.make() })

        try await capture(from: session, factory: factory, index: 0)
        try await capture(from: session, factory: factory, index: 1)

        #expect(factory.made.count == 2)
        #expect(factory.made[0] !== factory.made[1])
        #expect(factory.events.events == [
            "launch#0", "terminate#0", "launch#1", "terminate#1",
        ])
        #expect(factory.made.allSatisfy { !$0.isRunning })
    }

    /// Drives one whole `/usage` capture through the fake at `index`.
    private func capture(
        from session: UsageSession, factory: FakePTYFactory, index: Int
    ) async throws {
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { factory.made.count > index && factory.made[index].isRunning })
        let fake = factory.made[index]
        fake.emit(ready)
        #expect(await untilTrue { fake.writtenText.contains("/usage") })
        fake.emit(panel)
        _ = try await query.value
    }
}
