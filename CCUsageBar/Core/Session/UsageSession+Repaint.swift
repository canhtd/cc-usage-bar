import Foundation
import OSLog

/// Getting the terminal into a state where the `/usage` answer is unambiguous.
///
/// The capture poll in `UsageSession+Query.swift` decides purely from screen content: it
/// waits for a usage panel to appear and settle. That is only sound if no usage panel is
/// on the screen when the command is typed, which is what this file is responsible for.
extension UsageSession {
    /// Clears the recorded screen and makes Ink repaint all of it.
    ///
    /// The session is always a freshly launched process, so the only thing on screen is
    /// the launch splash -- there is no previous answer to dismiss. What is still needed
    /// is the full repaint: the interpreter has accumulated the splash animation, and
    /// judging "has a panel appeared?" against that is only reliable once the grid holds
    /// one complete frame.
    ///
    /// Returns `false` only if the query was superseded while waiting.
    func prepareScreen(for id: Int) async -> Bool {
        interpreter.reset()
        forceFullRepaint()
        return await waitForRepaint(for: id)
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
