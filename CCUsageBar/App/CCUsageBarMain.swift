import AppKit

/// AppKit entry point.
///
/// The app is deliberately not a SwiftUI `App`: an `LSUIElement` menu-bar app has no
/// window scene, and a placeholder `Settings` scene is exactly the empty-window bug this
/// rewrite set out to fix. SwiftUI is still used for every view, hosted from AppKit.
@main
enum CCUsageBarMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        // `delegate` is kept alive for the whole run loop by this local binding;
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) {}
    }
}
