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

    private(set) var isRunning = false
    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    var readSource: DispatchSourceRead?
    var exitSource: DispatchSourceProcess?

    /// Raw bytes from the terminal, delivered on the main actor.
    var onData: ((Data) -> Void)?
    /// Child exit status, delivered once, on the main actor.
    var onExit: ((Int32) -> Void)?

    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "pty")

    init() {}

    deinit {
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
    func terminate() {
        guard isRunning else { return }
        isRunning = false
        readSource?.cancel()
        readSource = nil
        exitSource?.cancel()
        exitSource = nil
        let pid = childPID
        childPID = -1
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if pid > 0 { Self.reap(pid) }
    }

    /// Asks nicely, waits, then insists -- and blocks on the final `waitpid` so the child
    /// is genuinely reaped rather than left defunct.
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
        var offset = 0
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < bytes.count {
                let written = Darwin.write(masterFD, base + offset, bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if errno == EINTR || errno == EAGAIN {
                    usleep(2000)
                } else {
                    break
                }
            }
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
        readSource?.cancel()
        readSource = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        onExit?(code)
    }

    nonisolated static func exitCode(from status: Int32) -> Int32 {
        // Mirrors WIFEXITED / WEXITSTATUS, which are C macros unavailable to Swift.
        (status & 0x7F) == 0 ? (status >> 8) & 0xFF : -(status & 0x7F)
    }
}
