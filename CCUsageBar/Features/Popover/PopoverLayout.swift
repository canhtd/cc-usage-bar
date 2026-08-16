import CoreGraphics

/// Sizing rules for the left-click popover, pure so the numbers are testable without
/// AppKit.
///
/// They live outside the view because `StatusItemController` needs the same width to ask
/// the hosting controller how tall the popover wants to be *before* AppKit anchors it
/// under the status item. A popover that is resized after it is shown keeps its
/// bottom-left corner, so a late shrink drags the arrow down away from the menu bar --
/// which is exactly what happened when the Apify section was switched off and the content
/// stopped filling the hard-coded height.
nonisolated enum PopoverLayout {
    /// The popover is a fixed-width panel; only its height reacts to the content.
    static let width: CGFloat = 380

    /// How tall the scrolling section may grow before it starts scrolling.
    ///
    /// Sized so the sections Claude Code reports today fit without scrolling; more
    /// sections, or the raw disclosure, scroll as usual. The Apify block adds a budget
    /// bar, a sparkline and up to three runs, so it needs its own headroom -- a
    /// recent-runs list that is always below the fold is not shown at all. The section
    /// only ever *hugs* its content, so a smaller cap never leaves dead space.
    static func maxContentHeight(showRawOutput: Bool, apifyEnabled: Bool) -> CGFloat {
        if showRawOutput { return 520 }
        return apifyEnabled ? 620 : 420
    }
}
