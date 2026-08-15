import AppKit

/// Builds the right-click menu (F9): refresh, profile switching, settings, quit.
@MainActor
final class StatusMenuBuilder: NSObject {
    private let model: AppModel
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
    }

    func build() -> NSMenu {
        let menu = NSMenu()
        // Items carry their own `isEnabled`; with autoenabling on, AppKit overrides it by
        // validating selectors and the "Refresh Now" disable during a fetch never shows.
        menu.autoenablesItems = false
        menu.addItem(statusHeader())
        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !model.activeRuntime.isFetching
        menu.addItem(refresh)

        menu.addItem(profilesItem())
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit CC Usage Bar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    // MARK: - Items

    private func statusHeader() -> NSMenuItem {
        let runtime = model.activeRuntime
        let title: String
        if let updated = runtime.lastUpdated {
            title = "Updated \(RelativeTime.describe(updated))"
        } else {
            title = runtime.state.message ?? "No data yet"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func profilesItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for profile in model.preferences.profiles {
            let entry = NSMenuItem(
                title: profile.shortName, action: #selector(selectProfile(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = profile.id.uuidString
            entry.state = profile.id == model.preferences.activeProfileID ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func refresh() {
        model.refreshAll()
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else {
            return
        }
        model.selectProfile(id: id)
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
