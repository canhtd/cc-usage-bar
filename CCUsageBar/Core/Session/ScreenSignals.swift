import Foundation

/// Pure predicates over the rendered terminal screen.
///
/// Keeping the "what is Claude Code showing me right now?" decisions in one pure type
/// means the session state machine has no string matching of its own, and every signal
/// can be unit-tested against captured screens.
nonisolated enum ScreenSignals {
    /// The input caret is on screen, so a slash command can be typed.
    static func isPromptReady(_ screen: String) -> Bool {
        screen.contains("\u{276F}")  // the ❯ prompt caret
            || screen.contains("for shortcuts")
            || screen.contains("bypass permissions on")
    }

    /// The first-run directory trust dialog, which a bare Return accepts.
    static func isTrustPrompt(_ screen: String) -> Bool {
        let markers = [
            "Quick safety check",
            "Do you trust the files in this folder",
            "trust the files in this",
            "Yes, proceed",
        ]
        return markers.contains { screen.localizedCaseInsensitiveContains($0) }
    }

    /// Onboarding or login screens: the user has to finish setup in a real terminal first.
    ///
    /// Every marker here has to be unique to setup. "Let's get started" was tried and
    /// removed: Claude Code also prints it in the ordinary launch splash, so a healthy
    /// logged-in session intermittently reported itself as needing setup depending on
    /// which frame of the intro animation happened to be on screen when a chunk arrived.
    /// The theme picker is still covered by "Choose the text style".
    static func needsSetup(_ screen: String) -> Bool { setupMarker(in: screen) != nil }

    /// The marker that made `needsSetup` true, so a wrong match is diagnosable from the
    /// log rather than from a screen dump the logger truncates.
    static func setupMarker(in screen: String) -> String? {
        let markers = [
            "Select login method",
            "Choose the text style",
            "Log in with your Claude account",
            "Sign in to Claude",
            "Please run /login",
            "Invalid API key",
            "You are not logged in",
        ]
        return markers.first { screen.localizedCaseInsensitiveContains($0) }
    }

    /// The login shell could not find the `claude` executable.
    static func isCommandNotFound(_ screen: String) -> Bool {
        let markers = ["command not found: claude", "claude: command not found"]
        return markers.contains { screen.localizedCaseInsensitiveContains($0) }
    }

    /// The `/usage` panel has painted at least one bar.
    static func hasUsagePanel(_ screen: String) -> Bool {
        screen.firstMatch(of: #/\d{1,3}\s*%\s+used/#) != nil
    }

    /// Claude Code is reporting that a limit has already been reached.
    ///
    /// A bare "rate limit" was tried and removed: it matches ordinary prose anywhere on
    /// the screen -- release notes, a tip, the user's own transcript -- and flipping the
    /// popover into the rate-limited state on that basis is worse than missing a wording.
    static func isRateLimited(_ screen: String) -> Bool {
        let markers = [
            "usage limit reached",
            "You've reached your usage limit",
            "You have reached your usage limit",
            "Approaching usage limit",
            "rate limit reached",
            "rate limited",
        ]
        return markers.contains { screen.localizedCaseInsensitiveContains($0) }
    }
}
