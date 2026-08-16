import CoreGraphics
import Testing

@testable import CCUsageBar

/// The popover's height rules. The dead space under the last section, and the arrow that
/// slid away from the menu bar, both came from a cap that ignored whether the Apify block
/// was there at all.
@Suite("Popover layout")
struct PopoverLayoutTests {
    @Test("The Apify block gets its own headroom")
    func apifyRaisesTheCap() {
        let withApify = PopoverLayout.maxContentHeight(showRawOutput: false, apifyEnabled: true)
        let withoutApify = PopoverLayout.maxContentHeight(showRawOutput: false, apifyEnabled: false)
        #expect(withApify > withoutApify)
    }

    @Test("The raw disclosure uses one height, whether or not Apify is on")
    func rawOutputWins() {
        let enabled = PopoverLayout.maxContentHeight(showRawOutput: true, apifyEnabled: true)
        let disabled = PopoverLayout.maxContentHeight(showRawOutput: true, apifyEnabled: false)
        #expect(enabled == disabled)
    }

    @Test("Every cap leaves room for a usable popover")
    func capsAreSane() {
        for showRawOutput in [true, false] {
            for apifyEnabled in [true, false] {
                let height = PopoverLayout.maxContentHeight(
                    showRawOutput: showRawOutput, apifyEnabled: apifyEnabled)
                #expect(height >= 300)
                // Comfortably inside the shortest Mac display the app supports, so the
                // popover never has to be squeezed by AppKit after it is anchored.
                #expect(height <= 700)
            }
        }
    }

    @Test("The panel is a fixed-width column")
    func widthIsFixed() {
        #expect(PopoverLayout.width == 380)
    }
}
