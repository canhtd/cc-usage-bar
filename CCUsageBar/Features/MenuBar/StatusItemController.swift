import AppKit
import SwiftUI

/// Owns the `NSStatusItem`: its title, its popover, and its right-click menu.
///
/// The title is re-rendered from an observation-tracking loop rather than a timer, so it
/// updates the instant a fetch lands and costs nothing while idle.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let openSettings: () -> Void
    private var menuBuilder: StatusMenuBuilder?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model, openSettings: openSettings))
        popover.contentSize = NSSize(width: 380, height: 540)

        menuBuilder = StatusMenuBuilder(model: model, openSettings: openSettings)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        render()
        observeModel()
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem.button else { return }
        let runtime = model.activeRuntime
        let severity = MenuBarTitle.severity(for: runtime.snapshot, state: runtime.state)
        let symbol = MenuBarTitle.symbolName(for: severity)

        var configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        configuration = configuration.applying(.init(paletteColors: [color(for: severity)]))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Claude Code usage")?
            .withSymbolConfiguration(configuration)

        switch model.preferences.menuBarDisplay {
        case .iconOnly:
            button.attributedTitle = NSAttributedString(string: "")
        case .percentages:
            let text = MenuBarTitle.text(for: runtime.snapshot, state: runtime.state)
            button.attributedTitle = NSAttributedString(
                string: " \(text)",
                attributes: [
                    .foregroundColor: color(for: severity),
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                ])
        }
        button.toolTip = tooltip(for: runtime)
    }

    private func color(for severity: MenuBarTitle.Severity) -> NSColor {
        switch severity {
        case .normal: return .labelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .unknown: return .disabledControlTextColor
        }
    }

    private func tooltip(for runtime: ProfileRuntime) -> String {
        var lines = ["Claude Code usage — \(runtime.profile.shortName)"]
        for section in runtime.snapshot?.sections ?? [] {
            lines.append("\(section.title): \(section.percentUsed)%")
        }
        if let message = runtime.state.message { lines.append(message) }
        return lines.joined(separator: "\n")
    }

    /// Re-renders whenever anything the title depends on changes, then re-arms itself.
    private func observeModel() {
        withObservationTracking {
            let runtime = model.activeRuntime
            _ = runtime.snapshot
            _ = runtime.state
            _ = model.preferences.menuBarDisplay
            _ = model.preferences.activeProfileID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.render()
                self?.observeModel()
            }
        }
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// The status item's drawn view, exposed for build-verification captures.
    var buttonView: NSView? { statusItem.button }

    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        guard let menu = menuBuilder?.build() else { return }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
