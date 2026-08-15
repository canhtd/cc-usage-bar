import AppKit

/// The application menu, present so that ⌘, and ⌘Q work whenever a window is key.
///
/// An accessory app has no menu bar of its own until one of its windows becomes key;
/// building this once at launch is what makes the standard shortcuts behave normally.
@MainActor
enum MainMenuBuilder {
    static func build(target: AnyObject, settings: Selector) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(
            title: "About CC Usage Bar",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: settings, keyEquivalent: ",")
        settingsItem.target = target
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        appMenu.addItem(
            NSMenuItem(
                title: "Hide CC Usage Bar", action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"))
        appMenu.addItem(
            NSMenuItem(
                title: "Quit CC Usage Bar", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }
}
