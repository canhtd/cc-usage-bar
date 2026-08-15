import Foundation

@testable import CCUsageBar

/// Locates the committed fixtures.
///
/// The test bundle is tried first, on purpose. The test host is a signed app, so reading
/// the source tree under `~/Documents` trips the Documents privacy prompt; if nobody can
/// answer it -- an unattended machine, a locked screen, CI -- `open(2)` blocks and the
/// whole test run hangs with no diagnostic. The bundle copy lives in DerivedData, which
/// no privacy policy guards. `#filePath` stays as the fallback for the case where the
/// fixture has not been copied into the bundle.
enum FixtureLoader {
    static func data(named name: String) throws -> Data {
        if let bundleURL = Bundle(for: BundleAnchor.self)
            .url(forResource: (name as NSString).deletingPathExtension,
                 withExtension: (name as NSString).pathExtension) {
            return try Data(contentsOf: bundleURL)
        }
        let sourceRelative = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
            .appending(path: name)
        guard FileManager.default.fileExists(atPath: sourceRelative.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return try Data(contentsOf: sourceRelative)
    }

    /// Replays raw PTY bytes through the real decoder and terminal, as the app does.
    static func renderScreen(from data: Data, chunkSize: Int = 137) -> String {
        let decoder = UTF8StreamDecoder()
        let interpreter = ANSIInterpreter(rows: 40, columns: 120)
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            interpreter.feed(decoder.decode(data.subdata(in: offset..<end)))
            offset = end
        }
        interpreter.feed(decoder.flush())
        return interpreter.screen.text
    }
}

private final class BundleAnchor {}
