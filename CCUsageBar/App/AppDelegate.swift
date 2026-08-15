import AppKit
import OSLog

/// Wires the app together and guarantees no child process outlives it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "delegate")

    /// Hidden switches used by the build's verification pass to capture screenshots.
    /// They only ever open UI the user can open themselves; nothing else changes.
    private static let showPopoverArgument = "--show-popover"
    private static let showSettingsArgument = "--show-settings"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test bundle is hosted inside this app. Skipping setup keeps the tests
        // hermetic: no status item, no timers, and above all no Claude Code subprocess.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
            ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil
        else { return }
        let model = AppModel()
        self.model = model
        statusItem = StatusItemController(model: model) { [weak self] in self?.openSettings() }
        NSApp.mainMenu = MainMenuBuilder.build(target: self, settings: #selector(openSettingsMenu))
        model.start()
        if CommandLine.arguments.contains(Self.showPopoverArgument) {
            presentForCapture { [weak self] in self?.statusItem?.togglePopover() }
        }
        if CommandLine.arguments.contains(Self.showSettingsArgument) {
            presentForCapture { [weak self] in self?.openSettings() }
        }
        #if DEBUG
            if let directory = DebugCapture.outputDirectory {
                presentForCapture { [weak self] in
                    guard let self, let model = self.model else { return }
                    Task {
                        await DebugCapture.captureAll(
                            model: model, statusButton: self.statusItem?.buttonView,
                            into: directory)
                    }
                }
            }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stopAll()
    }

    /// A menu-bar app should stay alive after its settings window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Settings

    func openSettings() {
        if settingsWindow == nil, let model {
            settingsWindow = SettingsWindowController(model: model)
        }
        settingsWindow?.show()
    }

    @objc private func openSettingsMenu() {
        openSettings()
    }

    // MARK: - Verification helper

    /// Runs `present` once real data has arrived, so a screenshot shows real content.
    /// Harmless in normal use: without the launch argument this is never called.
    private func presentForCapture(_ present: @escaping () -> Void) {
        Task { [weak self] in
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline, self?.model?.activeRuntime.snapshot == nil {
                try? await Task.sleep(for: .milliseconds(500))
            }
            try? await Task.sleep(for: .milliseconds(700))
            present()
        }
    }
}
