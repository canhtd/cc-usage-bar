import AppKit
import SwiftUI

/// A real settings window (F8).
///
/// An `LSUIElement` app has no windows of its own, so SwiftUI's `Settings` scene cannot be
/// opened reliably from a status-item menu. Hosting the same SwiftUI tabs in an
/// `NSWindowController` makes ⌘, and the menu item behave identically and predictably.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "CC Usage Bar Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("CCUsageBarSettings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Becoming a regular app while the window is open gives it a menu bar and lets it
    /// take focus; accessory is restored on close so the Dock stays clean.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
