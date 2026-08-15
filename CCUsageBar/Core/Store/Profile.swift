import Foundation

/// A named Claude Code configuration.
///
/// The default profile runs plain `claude`. Any other profile sets `CLAUDE_CONFIG_DIR` to
/// a directory the user picks with an open panel -- a folder path, never a secret typed
/// into a text field, and never a file this app reads itself.
nonisolated struct Profile: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    /// Absolute path used as `CLAUDE_CONFIG_DIR`; `nil` uses Claude Code's own default.
    var configDirectoryPath: String?

    init(id: UUID = UUID(), name: String, configDirectoryPath: String? = nil) {
        self.id = id
        self.name = name
        self.configDirectoryPath = configDirectoryPath
    }

    var configDirectory: URL? {
        configDirectoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// A short label for the menu when the user keeps several profiles.
    var shortName: String { name.isEmpty ? "Untitled" : name }

    /// A fixed identity so the default profile survives preference migrations.
    static let defaultID = UUID(uuidString: "0DEFA017-0000-4000-8000-000000000001")!
    static var defaultProfile: Profile { Profile(id: defaultID, name: "Default") }
}
