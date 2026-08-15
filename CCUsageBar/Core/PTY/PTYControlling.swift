import Foundation

/// What `UsageSession` needs from a child process.
///
/// The session is the interesting half of this app -- a state machine with timeouts,
/// retries and teardown paths -- and none of that should need a real `fork` to test. The
/// protocol is the seam: tests drive a fake that feeds canned screens and reports canned
/// exits, while production uses `PTYProcess`.
@MainActor
protocol PTYControlling: AnyObject {
    var isRunning: Bool { get }
    /// Raw bytes from the terminal.
    var onData: ((Data) -> Void)? { get set }
    /// Child exit status, delivered once.
    var onExit: ((Int32) -> Void)? { get set }

    func launch(spec: PTYLaunchSpec, rows: Int, columns: Int) throws
    func write(_ bytes: [UInt8])
    func setWindowSize(rows: Int, columns: Int)
    func terminate()
}

extension PTYProcess: PTYControlling {}
