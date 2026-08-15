import Foundation
import Testing

@testable import CCUsageBar

/// R4: the session state machine, driven through a fake terminal so no process is forked.
@Suite("Usage session")
@MainActor
struct UsageSessionTests {
    private func makeSession() -> (UsageSession, FakePTYProcess) {
        let fake = FakePTYProcess()
        let session = UsageSession(
            profileID: UUID(), configDirectory: nil, makeProcess: { fake })
        return (session, fake)
    }

    private let ready = SessionScreens.ready
    private let panel = SessionScreens.panel

    // MARK: - B-1

    /// The bug: `stop()` tore everything down without resuming the pending continuation,
    /// so `ProfileRuntime.isFetching` stayed latched and the profile never refreshed again.
    /// Reached in practice by editing or deleting a profile while a fetch is running.
    @Test("Stopping during a fetch resumes the caller with .cancelled")
    func stopDuringFetchCancels() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        session.stop()

        let result = await query.result
        guard case .failure(let error) = result else {
            Issue.record("fetch should not have succeeded")
            return
        }
        #expect(error as? UsageSessionError == .cancelled)
        #expect(fake.terminateCount == 1)
    }

    @Test("A second fetch while one is in flight reports busy, not a timeout")
    func concurrentFetchIsBusy() async throws {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        do {
            _ = try await session.fetch()
            Issue.record("the second fetch should have been rejected")
        } catch {
            #expect(error as? UsageSessionError == .busy)
        }
        session.stop()
        _ = await query.result
    }

    // MARK: - Exit handling

    @Test("Exit status 127 is reported as a missing executable")
    func exit127MeansNotInstalled() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        fake.exit(code: 127)

        let result = await query.result
        guard case .failure(let error) = result else {
            Issue.record("fetch should not have succeeded")
            return
        }
        #expect(error as? UsageSessionError == .claudeNotFound)
    }

    @Test("Any other exit status is reported with its code")
    func otherExitIsReported() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        fake.exit(code: 3)

        let result = await query.result
        guard case .failure(let error) = result else {
            Issue.record("fetch should not have succeeded")
            return
        }
        #expect(error as? UsageSessionError == .processExited(3))
    }

    /// m-11: an exit with nobody waiting still has to release the session's temp directory.
    @Test("An exit with no query in flight still tears the session down")
    func idleExitCleansUp() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })
        session.stop()
        _ = await query.result

        // A late exit callback from the child that was just terminated.
        fake.exit(code: 0)
        #expect(session.scratchDirectory == nil)
        #expect(session.phase == .stopped)
    }

    // MARK: - Startup screens

    @Test("A login screen is reported as needing setup")
    func onboardingNeedsSetup() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        fake.emit("Welcome to Claude Code\r\nSelect login method\r\n")

        let result = await query.result
        guard case .failure(let error) = result else {
            Issue.record("fetch should not have succeeded")
            return
        }
        #expect(error as? UsageSessionError == .needsSetup)
    }

    @Test("The shell reporting a missing command is recognised")
    func commandNotFound() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        fake.emit("zsh:1: command not found: claude\r\n")

        let result = await query.result
        guard case .failure(let error) = result else {
            Issue.record("fetch should not have succeeded")
            return
        }
        #expect(error as? UsageSessionError == .claudeNotFound)
    }

    @Test("The trust prompt is accepted with a bare Return")
    func trustPromptIsAccepted() async {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        fake.emit("Quick safety check\r\nDo you trust the files in this folder?\r\n")

        #expect(await untilTrue { fake.didWriteEnter })
        #expect(session.phase == .waitingForPrompt)
        session.stop()
        _ = await query.result
    }

    // MARK: - Happy path

    @Test("A prompt, a submitted command and a settled panel produce a snapshot")
    func capturesAPanel() async throws {
        let (session, fake) = makeSession()
        let query = Task { try await session.fetch() }
        #expect(await untilTrue { fake.isRunning })

        fake.emit(ready)
        // Waiting for the command rather than for a duration: the screen is reset just
        // before it is typed, so a panel emitted early would be wiped.
        #expect(await untilTrue { fake.writtenText.contains("/usage") })
        #expect(!fake.windowSizes.isEmpty)  // SIGWINCH nudge for a full repaint
        fake.emit(panel)

        let capture = try await query.value
        #expect(capture.snapshot.sections.map(\.title) == ["Current session"])
        #expect(capture.snapshot.sessionSection?.percentUsed == 48)
        // A capture is the end of the process's life, not the start of an idle session.
        #expect(session.phase == .stopped)
        #expect(fake.terminateCount == 1)
    }
}
