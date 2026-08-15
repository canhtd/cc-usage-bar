import Foundation

/// The only directory this app writes to, besides the per-session temporary cwd.
///
/// Safety invariant S3: nothing here reads the Claude configuration folder or any
/// secret store; this directory and the per-session temp dir are the only writes.
nonisolated enum AppSupport {
    static let folderName = "CCUsageBar"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func file(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }
}
