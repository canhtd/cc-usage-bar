import Foundation

@testable import CCUsageBar

/// A `PTYControlling` that never forks.
///
/// Lets the session state machine be driven frame by frame: the test writes screens the
/// way Claude Code would, and reads back exactly which bytes the session typed.
@MainActor
final class FakePTYProcess: PTYControlling {
    /// Shared with the factory so launch/teardown *order* across processes is observable.
    let events: PTYEventLog
    let index: Int

    init(events: PTYEventLog = PTYEventLog(), index: Int = 0) {
        self.events = events
        self.index = index
    }

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
        events.record("launch#\(index)")
    }

    func write(_ bytes: [UInt8]) { written.append(contentsOf: bytes) }

    func setWindowSize(rows: Int, columns: Int) {
        windowSizes.append((rows, columns))
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
        events.record("terminate#\(index)")
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

/// Records what every fake terminal did, in the order it happened.
@MainActor
final class PTYEventLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

/// Vends one fresh fake per launch, so "no session reuse" is testable.
@MainActor
final class FakePTYFactory {
    let events = PTYEventLog()
    private(set) var made: [FakePTYProcess] = []

    func make() -> any PTYControlling {
        let fake = FakePTYProcess(events: events, index: made.count)
        made.append(fake)
        return fake
    }
}
