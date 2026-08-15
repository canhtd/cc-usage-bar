import Foundation

/// Where a session is in the launch-and-query cycle.
///
/// The machine only ever moves forward through a query; any failure resets it to
/// `.stopped` and tears the child down, so a wedged CLI can never leave a half-state.
nonisolated enum UsageSessionPhase: String, Sendable, Equatable {
    case stopped
    case waitingForBanner
    case waitingForPrompt
    case waitingForResult
    case capturing
    case idle
}

/// One completed `/usage` capture.
nonisolated struct UsageCapture: Sendable {
    var snapshot: UsageSnapshot
    /// The plain rendered screen, used as the raw fallback view and for diagnostics.
    var screenText: String
    /// The rendered screen with colour, for the "Show raw output" disclosure.
    var screenRows: [[ANSICell]]
    var isRateLimited: Bool
}

/// Failures a caller can present to the user without further interpretation.
nonisolated enum UsageSessionError: Error, Sendable, Equatable {
    case needsSetup
    case claudeNotFound
    case timedOut
    case busy
    case cancelled
    case processExited(Int32)
    case launchFailed(String)
    case noUsageSections

    var message: String {
        switch self {
        case .needsSetup:
            return "Claude Code needs setup. Run `claude` in Terminal once and log in."
        case .claudeNotFound:
            return "`claude` was not found on your login shell PATH. Install Claude Code, then try again."
        case .timedOut:
            return "Claude Code did not answer in time. Try refreshing again."
        case .busy:
            return "A refresh is already running for this profile."
        case .cancelled:
            return "The refresh was cancelled."
        case .processExited(let code):
            return "Claude Code exited unexpectedly (status \(code))."
        case .launchFailed(let reason):
            return "Could not start Claude Code: \(reason)"
        case .noUsageSections:
            return "No usage information was found in the output of /usage."
        }
    }
}
