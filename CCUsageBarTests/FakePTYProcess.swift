import Foundation

@testable import CCUsageBar

/// A `PTYControlling` that never forks.
///
/// Lets the session state machine be driven frame by frame: the test writes screens the
/// way Claude Code would, and reads back exactly which bytes the session typed.
@MainActor
final class FakePTYProcess: PTYControlling {
    private(set) var isRunning = false
    var onData: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?

    /// Everything the session has written to the terminal, in order.
    private(set) var written: [UInt8] = []
    private(set) var windowSizes: [(rows: Int, columns: Int)] = []
    private(set) var terminateCount = 0
    var launchError: (any Error)?

    func launch(spec: PTYLaunchSpec, rows: Int, columns: Int) throws {
        if let launchError { throw launchError }
        isRunning = true
    }

    func write(_ bytes: [UInt8]) { written.append(contentsOf: bytes) }

    func setWindowSize(rows: Int, columns: Int) {
        windowSizes.append((rows, columns))
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    // MARK: - Driving the session

    /// Delivers text as if the child had painted it.
    func emit(_ text: String) {
        onData?(Data(text.utf8))
    }

    /// Reports the child exiting with `code`.
    func exit(code: Int32) {
        isRunning = false
        onExit?(code)
    }

    var writtenText: String { String(decoding: written, as: UTF8.self) }
    var didWriteEnter: Bool { written.contains(0x0D) }
    var didWriteEscape: Bool { written.contains(0x1B) }
}
