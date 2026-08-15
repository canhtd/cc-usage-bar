import Foundation
import OSLog

/// Drives one Claude Code PTY session and turns it into `/usage` snapshots.
///
/// State machine (R4): `stopped -> waitingForBanner -> waitingForPrompt -> idle`, then per
/// query `idle -> waitingForResult -> capturing -> idle`. Every query carries an id so a
/// late repaint from an abandoned query can never resume the wrong continuation, and any
/// failure tears the child down rather than leaving a half-initialised session behind.
///
/// Startup is driven by incoming bytes; the capture half (in `UsageSession+Query.swift`)
/// polls the rendered screen instead, because the terminal simply goes quiet once Ink has
/// finished painting and an edge-triggered check would wait for a chunk that never comes.
@MainActor
final class UsageSession {
    enum Timing {
        static let ptyRows = 60
        static let ptyColumns = 120
        static let queryTimeout: Duration = .seconds(30)
        /// The parsed sections must stop changing for this long before a capture is
        /// trusted. Spec R4 calls for 1.5s.
        static let settle: Duration = .milliseconds(1500)
        static let pollInterval: Duration = .milliseconds(200)
        static let escapeDelay: Duration = .milliseconds(250)
        static let submitDelay: Duration = .milliseconds(600)
        /// The prompt must be quiet this long before typing, so keystrokes are not
        /// swallowed by an Ink input that has not finished mounting.
        static let promptIdle: TimeInterval = 1.0
        /// ... but never wait longer than this for quiet.
        static let maxWarmup: TimeInterval = 8.0
        /// Re-send `/usage` if no panel has appeared by now.
        static let resubmitAfter: TimeInterval = 8.0
        static let maxSubmitAttempts = 3
        /// How often to re-dismiss a previous answer that survived the repaint.
        static let maxPanelClearAttempts = 3
        /// The repaint must be quiet this long before its content is judged.
        static let repaintIdle: TimeInterval = 0.4
        /// ... but never wait longer than this for the repaint.
        static let repaintTimeout: TimeInterval = 3.0
        /// A live session pins a Node process in memory; release it when unused.
        static let idleTeardown: Duration = .seconds(900)
    }

    let profileID: UUID
    let configDirectory: URL?
    private(set) var phase: UsageSessionPhase = .stopped

    var process: (any PTYControlling)?
    /// How a child is made. Injected so the state machine can be tested without forking.
    private let makeProcess: @MainActor () -> any PTYControlling
    var decoder = UTF8StreamDecoder()
    var interpreter = ANSIInterpreter(rows: Timing.ptyRows + 1, columns: Timing.ptyColumns)
    var scratchDirectory: URL?

    var queryID = 0
    var continuation: CheckedContinuation<UsageCapture, Error>?
    var queryIsPending = false
    var submitAttempts = 0
    var didAcceptTrust = false
    var launchedAt = Date.distantPast
    var lastDataAt = Date.distantPast
    var readyTask: Task<Void, Never>?
    var captureTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
    var idleTask: Task<Void, Never>?

    let log = Logger(subsystem: "com.danny.ccusagebar", category: "session")

    init(
        profileID: UUID,
        configDirectory: URL?,
        makeProcess: @escaping @MainActor () -> any PTYControlling = { PTYProcess() }
    ) {
        self.profileID = profileID
        self.configDirectory = configDirectory
        self.makeProcess = makeProcess
    }

    // MARK: - Public API

    /// Runs `/usage` once, launching or reusing the child process as needed.
    func fetch() async throws -> UsageCapture {
        guard continuation == nil else { throw UsageSessionError.busy }
        queryID += 1
        let id = queryID
        idleTask?.cancel()
        submitAttempts = 0
        if process?.isRunning != true {
            do {
                try start()
            } catch {
                throw UsageSessionError.launchFailed(String(describing: error))
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.queryIsPending = true
            self.startTimeout(for: id)
            if self.phase == .idle { self.submitUsageCommand(for: id) }
        }
    }

    /// Kills the child and forgets all session state.
    func stop() {
        timeoutTask?.cancel()
        captureTask?.cancel()
        readyTask?.cancel()
        idleTask?.cancel()
        readyTask = nil
        captureTask = nil
        // A fetch in flight has to be resumed here, or its caller waits forever and
        // `ProfileRuntime.isFetching` stays latched -- no refresh until the app restarts.
        // Reached whenever a profile's folder changes or the profile is deleted mid-fetch.
        finish(.failure(UsageSessionError.cancelled))
        process?.terminate()
        process = nil
        phase = .stopped
        didAcceptTrust = false
        queryIsPending = false
        decoder = UTF8StreamDecoder()
        interpreter.reset()
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
    }

    // MARK: - Launching

    private func start() throws {
        stop()
        let scratch = try PTYLaunchSpec.makeScratchDirectory()
        scratchDirectory = scratch
        let spec = PTYLaunchSpec(workingDirectory: scratch, configDirectory: configDirectory)
        let process = makeProcess()
        process.onData = { [weak self] data in self?.receive(data) }
        process.onExit = { [weak self] code in self?.handleExit(code) }
        try process.launch(spec: spec, rows: Timing.ptyRows, columns: Timing.ptyColumns)
        self.process = process
        launchedAt = Date()
        lastDataAt = Date()
        phase = .waitingForBanner
    }

    // MARK: - Stream handling

    /// Startup only. Once a query is in flight the capture task owns the screen.
    ///
    /// Rendering `screen.text` and running the signal scans costs a full grid walk, and
    /// this runs on the main actor for every chunk Ink emits -- so it is done only in the
    /// phases that act on the result. A `claude` that dies later is caught by the exit
    /// handler, and onboarding screens only ever appear before the prompt.
    private func receive(_ data: Data) {
        interpreter.feed(decoder.decode(data))
        lastDataAt = Date()

        switch phase {
        case .waitingForBanner, .waitingForPrompt:
            let screen = interpreter.screen.text
            if ScreenSignals.isCommandNotFound(screen) { return fail(.claudeNotFound) }
            if let marker = ScreenSignals.setupMarker(in: screen) {
                log.debug("needs-setup marker matched: \(marker, privacy: .public)")
                return fail(.needsSetup)
            }
            advanceStartup(screen: screen)
        case .stopped, .idle, .waitingForResult, .capturing:
            break
        }
    }

    private func advanceStartup(screen: String) {
        if !didAcceptTrust, ScreenSignals.isTrustPrompt(screen) {
            didAcceptTrust = true
            phase = .waitingForPrompt
            process?.write(PTYInput.enter)
            return
        }
        guard ScreenSignals.isPromptReady(screen) else { return }
        phase = .waitingForPrompt
        waitForPromptToSettle(for: queryID)
    }

    private func handleExit(_ code: Int32) {
        process = nil
        if continuation != nil {
            fail(code == 127 ? .claudeNotFound : .processExited(code))
        } else {
            // No query to report to, but the scratch directory and decoder state still
            // have to go; leaving them behind leaks a temp directory per dead session.
            stop()
        }
    }

    func setPhase(_ newPhase: UsageSessionPhase) { phase = newPhase }
}
