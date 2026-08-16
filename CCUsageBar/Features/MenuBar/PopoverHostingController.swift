import AppKit
import SwiftUI

/// Hosts `PopoverView` and reports every height SwiftUI settles on.
///
/// `NSPopover` sizes its window from this controller's `preferredContentSize`, but it does
/// not move the window when that size changes: AppKit keeps the bottom-left corner, so a
/// popover that shrinks after it is shown leaves its arrow stranded below the menu bar.
/// The callback lets `StatusItemController` re-anchor it.
final class PopoverHostingController: NSHostingController<PopoverView> {
    /// Called after SwiftUI changes the size this controller wants to be.
    var onSizeChange: (() -> Void)?

    override var preferredContentSize: NSSize {
        didSet {
            guard preferredContentSize != oldValue else { return }
            onSizeChange?()
        }
    }
}
