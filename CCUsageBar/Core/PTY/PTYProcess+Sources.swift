import Darwin
import Foundation

/// The dispatch sources that pump the PTY: one for readable bytes, one for child exit.
///
/// These live in an extension so that every handler can be built inside a `nonisolated`
/// helper. `setEventHandler` takes a plain `@convention(block) () -> Void`, so a closure
/// written inline in a `@MainActor` type would inherit main-actor isolation and trap the
/// moment dispatch invoked it on a global queue.
extension PTYProcess {
    // Dispatch source handlers must run off the main actor. `setEventHandler` takes a
    // plain `@convention(block) () -> Void`, so a closure written inline in this
    // main-actor-isolated type would inherit main-actor isolation and trap the moment
    // dispatch invoked it on a global queue. Building them in `nonisolated` helpers is
    // what keeps the isolation honest.

    func startReading(fd: Int32) {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        Self.attachReadHandler(to: source, fd: fd, owner: self)
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

    func startWatchingExit(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(
            identifier: pid, eventMask: .exit, queue: DispatchQueue.global(qos: .utility))
        Self.attachExitHandler(to: source, pid: pid, owner: self)
        source.resume()
        exitSource = source
    }

    nonisolated fileprivate static func attachExitHandler(
        to source: DispatchSourceProcess, pid: pid_t, owner: PTYProcess
    ) {
        source.setEventHandler { [weak owner] in
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
            let code = exitCode(from: status)
            guard let owner else { return }
            Task { @MainActor in owner.handleExit(code) }
        }
    }
}
