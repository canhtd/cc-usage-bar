import Foundation

/// Everything the UI knows about one profile, plus the PTY session that feeds it.
///
/// One runtime owns exactly one session, which is what keeps F7's promise that profiles
/// never share a Claude Code process, and makes "never overlap two fetches for the same
/// profile" a single boolean rather than a lock.
@MainActor
@Observable
final class ProfileRuntime {
    var profile: Profile
    private(set) var state: UsageState = .never
    private(set) var snapshot: UsageSnapshot?
    private(set) var rawRows: [[ANSICell]] = []
    private(set) var lastUpdated: Date?
    private(set) var isFetching = false

    private let session: UsageSession

    init(profile: Profile) {
        self.profile = profile
        session = UsageSession(profileID: profile.id, configDirectory: profile.configDirectory)
    }

    /// Applies an edited profile. A changed config directory needs a fresh session.
    func apply(_ updated: Profile) {
        let configChanged = updated.configDirectoryPath != profile.configDirectoryPath
        profile = updated
        if configChanged {
            session.stop()
            snapshot = nil
            state = .never
        }
    }

    /// Runs one `/usage` capture. Concurrent calls for the same profile are dropped (F3).
    @discardableResult
    func refresh() async -> UsageSnapshot? {
        guard !isFetching else { return snapshot }
        isFetching = true
        state = .loading
        defer { isFetching = false }
        do {
            return try await capture(confirmingNeedsSetup: true)
        } catch let error as UsageSessionError {
            state = error == .needsSetup ? .needsSetup : .error(error)
        } catch {
            state = .error(.launchFailed(error.localizedDescription))
        }
        return nil
    }

    /// Captures once and publishes the result.
    ///
    /// A `needsSetup` verdict is confirmed against a second, fresh session before it
    /// reaches the menu bar. Claude Code's launch splash is an animation, and a frame of
    /// it can carry onboarding wording while the account is perfectly fine; a wrong
    /// "needs setup" is worse than one extra launch. Real onboarding is still on screen
    /// for the retry, so the verdict survives when it is true.
    private func capture(confirmingNeedsSetup: Bool) async throws -> UsageSnapshot {
        do {
            let capture = try await session.fetch()
            snapshot = capture.snapshot
            rawRows = capture.screenRows
            lastUpdated = capture.snapshot.capturedAt
            state = capture.isRateLimited ? .rateLimited : .ready
            return capture.snapshot
        } catch UsageSessionError.needsSetup where confirmingNeedsSetup {
            session.stop()
            return try await capture(confirmingNeedsSetup: false)
        }
    }

    func stop() {
        session.stop()
    }
}
