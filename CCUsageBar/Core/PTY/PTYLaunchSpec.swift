import Foundation

/// The one and only subprocess this app is allowed to start.
///
/// Safety invariant S4: `/bin/zsh -l -c claude` inside a PTY, in a fresh empty temporary
/// directory, with the user's environment plus `TERM` and -- for a non-default profile --
/// `CLAUDE_CONFIG_DIR`. There is no other exec site in the app, and no code path that lets
/// a caller choose a different executable or argument list.
nonisolated struct PTYLaunchSpec: Sendable {
    static let executablePath = "/bin/zsh"
    static let arguments = ["-l", "-c", "claude"]

    /// A private, empty directory used as the child's cwd so Claude Code never sees a project.
    let workingDirectory: URL
    /// `CLAUDE_CONFIG_DIR` for profile support; `nil` means the user's default configuration.
    let configDirectory: URL?

    init(workingDirectory: URL, configDirectory: URL?) {
        self.workingDirectory = workingDirectory
        self.configDirectory = configDirectory
    }

    /// Creates a fresh empty scratch directory for one session.
    static func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCUsageBar", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The child environment: inherited, plus a terminal type Ink can render into.
    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        // The app is not a terminal session; drop markers that would confuse the CLI.
        environment.removeValue(forKey: "CLAUDE_CODE_CHILD_SESSION")
        if let configDirectory {
            environment["CLAUDE_CONFIG_DIR"] = configDirectory.path
        }
        return environment
    }
}

/// The bytes the app is permitted to write to the PTY. Nothing else is ever sent.
nonisolated enum PTYInput {
    /// The slash command being measured.
    static let usageCommand = Array("/usage".utf8)
    /// Submit / accept.
    static let enter = Array("\r".utf8)
    /// Dismiss the usage panel and return to the prompt.
    static let escape = Array("\u{1B}".utf8)
}
