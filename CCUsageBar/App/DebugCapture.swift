import AppKit
import OSLog
import SwiftUI

/// Renders the app's real views to PNG files, for build verification.
///
/// Enabled only by the hidden `--capture-ui <directory>` launch argument. It exists
/// because `screencapture` sees nothing while the Mac is at the lock screen, and because
/// rendering the live views proves more than a desktop photograph would: the images come
/// from the same SwiftUI views, bound to the same model, holding the same real data.
///
/// Each view is hosted in a real off-screen window rather than run through `ImageRenderer`:
/// the renderer does not draw `ScrollView` contents or AppKit-backed controls, so its
/// output is missing exactly the parts worth showing.
@MainActor
enum DebugCapture {
    static let argument = "--capture-ui"

    /// The directory named after `--capture-ui`, if the argument was passed.
    static var outputDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument),
            arguments.index(after: index) < arguments.endIndex
        else { return nil }
        let url = URL(fileURLWithPath: arguments[arguments.index(after: index)], isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let log = Logger(subsystem: "com.danny.ccusagebar", category: "capture")
    private static let settingsSize = CGSize(width: 560, height: 440)

    /// Writes every view a reviewer needs to see.
    static func captureAll(model: AppModel, statusButton: NSView?, into directory: URL) async {
        if let statusButton = statusButton as? NSStatusBarButton {
            writeStatusItem(statusButton, named: "menu-bar-item", in: directory)
        }
        await hosted(
            PopoverView(model: model, openSettings: {}),
            size: CGSize(width: 380, height: 540), named: "popover", in: directory)
        await hosted(
            RawOutputView(rows: model.activeRuntime.rawRows).padding(14),
            size: CGSize(width: 420, height: 240), named: "popover-raw-output", in: directory)
        await hosted(
            SettingsView(model: model).padding(14), size: CGSize(width: 590, height: 500),
            named: "settings-window", in: directory)
        await hosted(
            GeneralSettingsView(model: model), size: settingsSize, named: "settings-general",
            in: directory)
        await hosted(
            NotificationSettingsView(model: model), size: settingsSize,
            named: "settings-notifications", in: directory)
        await hosted(
            ProfilesSettingsView(model: model), size: settingsSize, named: "settings-profiles",
            in: directory)
        await hosted(
            HistorySettingsView(model: model), size: settingsSize, named: "settings-history",
            in: directory)
        await hosted(
            AboutView(), size: settingsSize, named: "settings-about", in: directory)
        log.info("wrote UI captures to \(directory.path, privacy: .public)")
    }

    // MARK: - Renderers

    /// Hosts `content` in an off-screen window, lets AppKit lay it out and draw, then
    /// snapshots it through the normal drawing path.
    static func hosted<Content: View>(
        _ content: Content, size: CGSize, named name: String, in directory: URL
    ) async {
        let hosting = NSHostingView(
            rootView: content.frame(
                width: size.width, height: size.height, alignment: .top))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()

        // Give SwiftUI a couple of run-loop turns to resolve layout and load charts.
        try? await Task.sleep(for: .milliseconds(500))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        writeOnScreen(hosting, named: name, in: directory, background: .windowBackgroundColor)
        window.orderOut(nil)
    }

    /// Draws the status item's own image and attributed title -- the exact objects the
    /// menu bar is displaying. `cacheDisplay` on an `NSStatusBarButton` yields an empty
    /// bitmap, because the menu bar draws it through a private, out-of-process path.
    static func writeStatusItem(_ button: NSStatusBarButton, named name: String, in directory: URL) {
        let padding: CGFloat = 10
        let size = NSSize(width: max(button.bounds.width, 40) + padding * 2, height: 26)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        var x = padding
        if let image = button.image {
            let height: CGFloat = 15
            let width = image.size.width / max(image.size.height, 1) * height
            image.draw(in: NSRect(x: x, y: (size.height - height) / 2, width: width, height: height))
            x += width
        }
        let title = button.attributedTitle
        title.draw(at: NSPoint(x: x, y: (size.height - title.size().height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
        log.info("captured \(name, privacy: .public).png")
    }

    /// Captures a view exactly as drawn, composited on a solid backdrop.
    static func writeOnScreen(
        _ view: NSView, named name: String, in directory: URL,
        background: NSColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    ) {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
            let rep = view.bitmapImageRepForCachingDisplay(in: bounds)
        else { return }
        view.cacheDisplay(in: bounds, to: rep)

        let canvas = NSImage(size: bounds.size)
        canvas.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        rep.draw(in: NSRect(origin: .zero, size: bounds.size))
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation, let flat = NSBitmapImageRep(data: tiff),
            let data = flat.representation(using: .png, properties: [:])
        else { return }
        let url = directory.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            log.info("captured \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("could not write \(name, privacy: .public)")
        }
    }
}
