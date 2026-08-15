import Darwin
import Foundation
import OSLog

/// A child process attached to a pseudo-terminal.
///
/// Claude Code is an interactive Ink application: without a TTY it refuses to draw, so a
/// plain `Process` with pipes cannot work. `forkpty` gives the child its own session and
/// controlling terminal; between fork and exec the child touches nothing but `chdir` and
/// `execve`, both async-signal-safe, which is what makes forking a Cocoa process safe here.
@MainActor
final class PTYProcess {
    enum LaunchError: Error, Sendable {
        case forkFailed(Int32)
    }

    /// Reported when the child is gone but its status could not be collected.
    nonisolated static let unknownExitCode: Int32 = -1
    /// Give up on a blocked terminal rather than spinning on `EAGAIN` forever.
    private static let writeDeadline: TimeInterval = 0.5

    private(set) var isRunning = false
    /// Set to -1 the moment teardown starts. The descriptor itself is closed by the read
    /// source's cancel handler, never here -- see `terminate()`.
    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    var readSource: DispatchSourceRead?
    var exitSource: DispatchSourceProcess?
    /// Whoever claims this reaps the child; the other side must not call `waitpid` or
    /// signal the pid, because by then the number may belong to somebody else.
    nonisolated let reapToken = ReapToken()

    /// Raw bytes from the terminal, delivered on the main actor.
    var onData: ((Data) -> Void)?
    /// Child exit status, delivered once, on the main actor.
    var onExit: ((Int32) -> Void)?

    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "pty")

    init() {}

    deinit {
        // Cancelling the read source runs its cancel handler, which closes the descriptor.
        readSource?.cancel()
        exitSource?.cancel()
    }

    // MARK: - Lifecycle

    func launch(spec: PTYLaunchSpec, rows: Int, columns: Int) throws {
        precondition(!isRunning, "PTYProcess is single-use per launch")
        let argv = CStringArray([PTYLaunchSpec.executablePath] + PTYLaunchSpec.arguments)
        let envp = CStringArray(spec.environment.map { "\($0.key)=\($0.value)" })
        let cwd = CStringArray([spec.workingDirectory.path])
        defer {
            argv.deallocate()
            envp.deallocate()
            cwd.deallocate()
        }

        var size = winsize(
            ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        var fd: Int32 = -1
        let pid = forkpty(&fd, nil, nil, &size)
        if pid < 0 { throw LaunchError.forkFailed(errno) }
        if pid == 0 {
            // Child. Async-signal-safe calls only.
            if chdir(cwd.pointer[0]) != 0 { _exit(126) }
            _ = execve(argv.pointer[0], argv.pointer, envp.pointer)
            _exit(127)
        }

        masterFD = fd
        childPID = pid
        isRunning = true
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        startReading(fd: fd)
        startWatchingExit(pid: pid)
        log.debug("launched pty child \(pid, privacy: .public)")
    }

    /// Signals the child's whole process group and reaps it, leaving no zombie.
    ///
    /// The group matters: `zsh -l -c claude` may leave the Node process as a sibling, and
    /// signalling only the direct child would strand it.
    ///
    /// The descriptor is *not* closed here. `cancel()` is asynchronous, so the read handler
    /// may still be inside `read(2)`; closing underneath it would let the number be reused
    /// by the next `open` -- history.jsonl, say -- and have the handler consume bytes from
    /// it. The cancel handler owns the close, and it runs only once no handler is active.
    func terminate() {
        guard isRunning else { return }
        isRunning = false
        let pid = childPID
        childPID = -1
        masterFD = -1  // stop further writes immediately
        exitSource?.cancel()
        exitSource = nil
        readSource?.cancel()  // its cancel handler closes the descriptor
        readSource = nil
        if pid > 0, reapToken.claim() { Self.reap(pid) }
    }

    /// Asks nicely, waits, then insists -- and blocks on the final `waitpid` so the child
    /// is genuinely reaped rather than left defunct.
    ///
    /// Only ever called by whoever won `reapToken`, so the pid is still ours to signal.
    nonisolated private static func reap(_ pid: pid_t) {
        DispatchQueue.global(qos: .utility).async {
            kill(-pid, SIGTERM)
            kill(pid, SIGTERM)
            var status: Int32 = 0
            for _ in 0..<20 {
                if waitpid(pid, &status, WNOHANG) != 0 { return }
                usleep(50_000)
            }
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0)
        }
    }

    // MARK: - I/O

    func write(_ bytes: [UInt8]) {
        guard isRunning, masterFD >= 0, !bytes.isEmpty else { return }
        let deadline = Date().addingTimeInterval(Self.writeDeadline)
        var offset = 0
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < bytes.count {
                // errno is only meaningful after a failing call; clear it so a stale value
                // from somewhere else cannot be read as EAGAIN and spin this loop.
                errno = 0
                let written = Darwin.write(masterFD, base + offset, bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if written == 0 {
                    break  // no progress and no error: the terminal is not taking bytes
                } else if errno == EINTR || errno == EAGAIN {
                    if Date() >= deadline { break }
                    usleep(2000)
                } else {
                    break
                }
            }
        }
        if offset < bytes.count {
            log.error("short write to pty: \(offset, privacy: .public)/\(bytes.count, privacy: .public)")
        }
    }

    /// Changes the terminal size, which delivers SIGWINCH and forces Ink to repaint in full.
    func setWindowSize(rows: Int, columns: Int) {
        guard isRunning, masterFD >= 0 else { return }
        var size = winsize(
            ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = withUnsafeMutablePointer(to: &size) { ioctl(masterFD, TIOCSWINSZ, $0) }
    }

    func handleExit(_ code: Int32) {
        exitSource?.cancel()
        exitSource = nil
        guard isRunning else { return }
        isRunning = false
        childPID = -1
        masterFD = -1
        readSource?.cancel()  // its cancel handler closes the descriptor
        readSource = nil
        onExit?(code)
    }

    nonisolated static func exitCode(from status: Int32) -> Int32 {
        // Mirrors WIFEXITED / WEXITSTATUS, which are C macros unavailable to Swift.
        (status & 0x7F) == 0 ? (status >> 8) & 0xFF : -(status & 0x7F)
    }
}
