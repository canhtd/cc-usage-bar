import AppKit
import Foundation

/// Fires the periodic refresh, and one extra refresh after the Mac wakes from sleep.
///
/// A timer that slept through a four-hour nap would otherwise show stale percentages until
/// its next tick, which is exactly when the user glances at the menu bar (F3).
///
/// Teardown is explicit via `invalidate()` rather than `deinit`: the scheduler's state is
/// main-actor isolated, and a nonisolated deinit cannot legally touch it.
@MainActor
final class RefreshScheduler {
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire() }
        }
    }

    func update(interval: RefreshInterval) {
        timer?.invalidate()
        timer = nil
        guard let seconds = interval.seconds else { return }
        // Weak capture: the run loop retains the timer, and a strong self here would
        // keep the scheduler alive forever.
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire() }
        }
        timer.tolerance = seconds * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
}
