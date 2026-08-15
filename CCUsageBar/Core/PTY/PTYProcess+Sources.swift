import Darwin
import Foundation

/// Decides which side gets to reap the child.
///
/// Both the exit source and `terminate()` want to call `waitpid`. Whichever loses would be
/// operating on a pid that is no longer ours -- the number is recycled quickly on a busy
/// machine, so a late `kill(-pid, …)` could signal an unrelated process group.
nonisolated final class ReapToken: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// Returns `true` to exactly one caller, ever.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// The dispatch sources that pump the PTY: one for readable bytes, one for child exit.
///
/// These live in an extension so that every handler can be built inside a `nonisolated`
/// helper. `setEventHandler` takes a plain `@convention(block) () -> Void`, so a closure
/// written inline in a `@MainActor` type would inherit main-actor isolation and trap the
/// moment dispatch invoked it on a global queue.
extension PTYProcess {
    func startReading(fd: Int32) {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        Self.attachReadHandler(to: source, fd: fd, owner: self)
        Self.attachCloseOnCancel(to: source, fd: fd)
        source.resume()
        readSource = source
    }

    nonisolated fileprivate static func attachReadHandler(
        to source: DispatchSourceRead, fd: Int32, owner: PTYProcess
    ) {
        source.setEventHandler { [weak owner] in
            var buffer = [UInt8](repeating: 0, count: 16384)
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard count > 0, let owner else { return }
            let data = Data(buffer[0..<count])
            Task { @MainActor in owner.onData?(data) }
        }
    }

    /// Closing the descriptor here, rather than in `terminate()`, is what makes teardown
    /// safe: dispatch runs the cancel handler only after the event handler has returned,
    /// so the number can never be recycled while a `read(2)` is still in flight on it.
    nonisolated fileprivate static func attachCloseOnCancel(
        to source: DispatchSourceRead, fd: Int32
    ) {
        source.setCancelHandler { close(fd) }
    }

    func startWatchingExit(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid, eventMask: .exit, queue: DispatchQueue.global(qos: .utility))
        Self.attachExitHandler(to: source, pid: pid, owner: self, token: reapToken)
        source.resume()
        exitSource = source
    }

    nonisolated fileprivate static func attachExitHandler(
        to source: DispatchSourceProcess, pid: pid_t, owner: PTYProcess, token: ReapToken
    ) {
        source.setEventHandler { [weak owner] in
            // If `terminate()` already claimed the child, this pid is not ours to wait on.
            guard token.claim() else { return }
            var status: Int32 = 0
            let reaped = waitpid(pid, &status, 0)
            // Without checking the return, a failed wait leaves `status` at 0 and a child
            // that died with 127 ("claude: command not found") looks like a clean exit.
            let code = reaped == pid ? exitCode(from: status) : PTYProcess.unknownExitCode
            guard let owner else { return }
            Task { @MainActor in owner.handleExit(code) }
        }
    }
}
