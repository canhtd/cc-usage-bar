import Foundation
import OSLog

/// The per-query half of the session state machine: waiting for the prompt to be usable,
/// typing `/usage`, forcing a full repaint, and polling the screen until it settles.
extension UsageSession {
    // MARK: - Readiness

    /// Waits for the prompt to stop changing before typing into it.
    ///
    /// The caret appears within a second of launch, but Claude Code is still connecting;
    /// keystrokes sent to an Ink input that has not finished mounting are simply dropped,
    /// which is exactly what a 30-second timeout with a perfectly healthy CLI looks like.
    func waitForPromptToSettle(for id: Int) {
        guard readyTask == nil else { return }
        readyTask = Task { [weak self] in
            while true {
                guard let self, self.queryID == id, self.phase == .waitingForPrompt else { return }
                let quiet = Date().timeIntervalSince(self.lastDataAt)
                let warm = Date().timeIntervalSince(self.launchedAt)
                if quiet >= Timing.promptIdle || warm >= Timing.maxWarmup { break }
                try? await Task.sleep(for: Timing.pollInterval)
                if Task.isCancelled { return }
            }
            guard let self, self.queryID == id, self.phase == .waitingForPrompt else { return }
            self.readyTask = nil
            self.setPhase(.idle)
            if self.queryIsPending { self.submitUsageCommand(for: id) }
        }
    }

    // MARK: - Submitting

    /// Clears the input, gets the previous answer off the screen, then types the command.
    ///
    /// The repaint and the check that the old panel is really gone live in
    /// `UsageSession+Repaint.swift`; without that check the capture poll below cannot tell
    /// the previous answer from this one.
    func submitUsageCommand(for id: Int) {
        queryIsPending = false
        submitAttempts += 1
        setPhase(.waitingForResult)
        let attempt = submitAttempts
        Task { [weak self] in
            guard let self, self.queryID == id else { return }
            self.process?.write(PTYInput.escape)
            try? await Task.sleep(for: Timing.escapeDelay)
            guard self.queryID == id, self.phase == .waitingForResult else { return }
            guard await self.clearPreviousPanel(for: id) else { return }
            self.process?.write(PTYInput.usageCommand)
            try? await Task.sleep(for: Timing.submitDelay)
            guard self.queryID == id, self.phase == .waitingForResult else { return }
            self.process?.write(PTYInput.enter)
            self.log.debug("submitted /usage (attempt \(attempt, privacy: .public))")
            self.startCapture(for: id)
        }
    }

    // MARK: - Capturing

    /// Polls the rendered screen until the usage panel has appeared and stopped changing.
    ///
    /// Polling rather than reacting to bytes: once Ink finishes painting, the PTY goes
    /// silent, so any check that only runs on arriving data can miss the final frame.
    func startCapture(for id: Int) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            var lastText = ""
            var stableSince = Date()
            let submittedAt = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: Timing.pollInterval)
                guard let self, self.queryID == id else { return }
                guard self.phase == .waitingForResult || self.phase == .capturing else { return }

                let text = self.interpreter.screen.text
                if text != lastText {
                    lastText = text
                    stableSince = Date()
                }
                if ScreenSignals.hasUsagePanel(text) {
                    if self.phase == .waitingForResult { self.setPhase(.capturing) }
                    if Date().timeIntervalSince(stableSince) >= Timing.settle.seconds {
                        self.completeCapture(text: text)
                        return
                    }
                } else if Date().timeIntervalSince(submittedAt) >= Timing.resubmitAfter {
                    guard self.submitAttempts < Timing.maxSubmitAttempts else { return }
                    self.log.debug("no usage panel yet; re-sending /usage")
                    self.submitUsageCommand(for: id)
                    return
                }
            }
        }
    }

    private func completeCapture(text: String) {
        let snapshot = UsageParser.parse(screenText: text)
        guard !snapshot.isEmpty else { return fail(.noUsageSections) }
        let capture = UsageCapture(
            snapshot: snapshot,
            screenText: text,
            screenRows: interpreter.screen.trimmedRows,
            isRateLimited: ScreenSignals.isRateLimited(text))
        process?.write(PTYInput.escape)  // dismiss the panel so the session can be reused
        setPhase(.idle)
        finish(.success(capture))
        scheduleIdleTeardown()
    }

    private func scheduleIdleTeardown() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Timing.idleTeardown)
            guard !Task.isCancelled, let self, self.continuation == nil else { return }
            self.log.debug("tearing down idle session")
            self.stop()
        }
    }

    // MARK: - Completion

    func startTimeout(for id: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Timing.queryTimeout)
            guard !Task.isCancelled, let self, self.queryID == id else { return }
            self.fail(.timedOut)
        }
    }

    func fail(_ error: UsageSessionError) {
        guard continuation != nil else { return }
        log.error(
            "session failed in phase \(self.phase.rawValue, privacy: .public): \(error.message, privacy: .public)"
        )
        // The screen at the moment of failure is the only useful diagnostic there is.
        log.debug("screen at failure:\n\(self.interpreter.screen.text, privacy: .public)")
        finish(.failure(error))
        stop()
    }

    /// Resumes the pending continuation exactly once and clears query bookkeeping.
    func finish(_ result: Result<UsageCapture, Error>) {
        timeoutTask?.cancel()
        captureTask?.cancel()
        captureTask = nil
        guard let continuation else { return }
        self.continuation = nil
        queryIsPending = false
        continuation.resume(with: result)
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`, for comparing against `Date` arithmetic.
    fileprivate var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
