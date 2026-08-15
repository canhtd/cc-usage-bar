import Foundation
import OSLog

/// Getting the terminal into a state where the next `/usage` answer is unambiguous.
///
/// The capture poll in `UsageSession+Query.swift` decides purely from screen content: it
/// waits for a usage panel to appear and settle. That is only sound if the previous
/// answer is off the screen first, which is what this file is responsible for.
extension UsageSession {
    /// Repaints the screen and confirms the previous answer is no longer on it.
    ///
    /// `completeCapture` presses ESC to dismiss the panel, and the next query presses ESC
    /// again before repainting, but neither guarantees Claude Code has *processed* the key
    /// by the time SIGWINCH arrives -- and a repaint that wins that race draws the old
    /// panel straight back onto the blank screen. Content-based detection then reads last
    /// query's numbers as this query's answer, which is how the same session reported
    /// alternating percentages. Checking costs one repaint; being wrong costs a wrong
    /// number in the menu bar, so the check stays.
    ///
    /// Returns `false` only if the query was superseded while waiting.
    func clearPreviousPanel(for id: Int) async -> Bool {
        for _ in 0..<Timing.maxPanelClearAttempts {
            interpreter.reset()
            forceFullRepaint()
            guard await waitForRepaint(for: id) else { return false }
            guard ScreenSignals.hasUsagePanel(interpreter.screen.text) else { return true }
            log.debug("previous usage panel survived the repaint; dismissing again")
            process?.write(PTYInput.escape)
            try? await Task.sleep(for: Timing.escapeDelay)
            guard queryID == id, phase == .waitingForResult else { return false }
        }
        // Out of attempts: submit anyway. A stale panel is still better handled by the
        // capture poll, which re-sends `/usage` when the screen does not change.
        return true
    }

    /// Resizes the terminal by one row and back, delivering SIGWINCH so Ink repaints
    /// everything rather than only the cells it thinks are dirty.
    func forceFullRepaint() {
        process?.setWindowSize(rows: Timing.ptyRows + 1, columns: Timing.ptyColumns)
        process?.setWindowSize(rows: Timing.ptyRows, columns: Timing.ptyColumns)
    }

    /// Waits for the repaint to arrive and stop, so the screen being judged is complete.
    private func waitForRepaint(for id: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(Timing.repaintTimeout)
        while Date() < deadline {
            try? await Task.sleep(for: Timing.pollInterval)
            guard queryID == id, phase == .waitingForResult else { return false }
            if Date().timeIntervalSince(lastDataAt) >= Timing.repaintIdle { return true }
        }
        return true
    }
}
