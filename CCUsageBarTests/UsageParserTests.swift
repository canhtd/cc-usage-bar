import Foundation
import Testing

@testable import CCUsageBar

/// R3: the parser runs against a screen captured from the real CLI on this machine, plus
/// synthetic screens for the shapes that capture does not happen to contain.
@Suite("Usage parser")
struct UsageParserTests {
    @Test("Real captured PTY output parses into three sections")
    func realCapture() throws {
        let data = try FixtureLoader.data(named: "usage-session-week-model.bin")
        let screen = FixtureLoader.renderScreen(from: data)
        let snapshot = UsageParser.parse(screenText: screen)

        #expect(snapshot.sections.map(\.title) == [
            "Current session", "Current week (all models)", "Current week (Fable)",
        ])
        #expect(snapshot.sessionSection?.percentUsed == 48)
        #expect(snapshot.weekAllModelsSection?.percentUsed == 25)
        #expect(snapshot.sections[2].percentUsed == 22)
        #expect(snapshot.sessionSection?.resetsText == "Resets 1:09pm (Asia/Saigon)")
        #expect(snapshot.weekAllModelsSection?.resetsText == "Resets Aug 19 at 2:59am (Asia/Saigon)")
        #expect(snapshot.weekAllModelsSection?.note?.contains("promo") == true)
    }

    /// Claude Code 2.1.233 dropped the per-model week section and added a "What's
    /// contributing to your limits usage?" block whose lines also start with a percentage.
    /// Only the two real bars may come out of it.
    @Test("A capture from Claude Code 2.1.233 parses into its two sections")
    func capture_2_1_233() throws {
        let data = try FixtureLoader.data(named: "usage-2-1-233.bin")
        let screen = FixtureLoader.renderScreen(from: data)
        let snapshot = UsageParser.parse(screenText: screen)

        #expect(snapshot.sections.map(\.title) == [
            "Current session", "Current week (all models)",
        ])
        #expect(snapshot.sessionSection?.percentUsed == 65)
        #expect(snapshot.weekAllModelsSection?.percentUsed == 6)
        #expect(snapshot.sessionSection?.resetsText == "Resets 9:40pm (Asia/Saigon)")
        #expect(snapshot.weekAllModelsSection?.resetsText
            == "Resets Aug 19 at 3am (Asia/Saigon)")
        #expect(snapshot.weekAllModelsSection?.note?.contains("promo") == true)
        #expect(!screen.contains("\u{FFFD}"))
    }

    @Test("Real captured output survives being chunked at awkward boundaries")
    func realCaptureChunking() throws {
        let data = try FixtureLoader.data(named: "usage-session-week-model.bin")
        let reference = UsageParser.parse(screenText: FixtureLoader.renderScreen(from: data))
        for chunk in [1, 3, 7, 64, 4096] {
            let screen = FixtureLoader.renderScreen(from: data, chunkSize: chunk)
            let snapshot = UsageParser.parse(screenText: screen)
            #expect(snapshot.sections == reference.sections, "chunk size \(chunk)")
        }
    }

    @Test("No mojibake reaches the parsed titles or the rendered screen")
    func noMojibake() throws {
        let data = try FixtureLoader.data(named: "usage-session-week-model.bin")
        let screen = FixtureLoader.renderScreen(from: data)
        #expect(!screen.contains("â"))
        #expect(!screen.contains("\u{FFFD}"))
        #expect(screen.contains("█"))
    }

    @Test("An unknown future section is still reported with its title and percentage")
    func unknownSection() {
        let screen = """
              Current session
              ████████                                           12% used
              Resets 9:15am (America/New_York)

              Current month (Sonnet 9)
              ██████████████████████████                         64% used
              Resets Dec 1 at 12am (America/New_York)
            """
        let snapshot = UsageParser.parse(screenText: screen)
        #expect(snapshot.sections.count == 2)
        #expect(snapshot.sections[1].title == "Current month (Sonnet 9)")
        #expect(snapshot.sections[1].percentUsed == 64)
    }

    @Test("Ink repaint duplicates collapse to the last rendering")
    func duplicateSections() {
        let screen = """
            Current session
            ███  40% used
            Resets 1:00pm (UTC)

            Current session
            █████  55% used
            Resets 1:00pm (UTC)
            """
        let snapshot = UsageParser.parse(screenText: screen)
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].percentUsed == 55)
    }

    @Test("Percentages are read without a bar and clamped to 0...100")
    func edgeCasePercentages() {
        let snapshot = UsageParser.parse(
            screenText: "Current session\n0% used\n\nCurrent week (all models)\n100% used")
        #expect(snapshot.sections.map(\.percentUsed) == [0, 100])
    }

    @Test("Prose containing a percentage is not mistaken for a bar")
    func prosePercentagesIgnored() {
        let screen = """
            Current session
            ████  48% used
            Resets 1:09pm (UTC)

            What's contributing to your limits usage?
            100% of your usage came from subagent-heavy sessions
            44% of your usage was at >150k context
            """
        let snapshot = UsageParser.parse(screenText: screen)
        #expect(snapshot.sections.map(\.title) == ["Current session"])
    }

    @Test("A section with no reset line still parses")
    func missingResetLine() {
        let snapshot = UsageParser.parse(screenText: "Current session\n█  7% used")
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].resetsText == nil)
        #expect(snapshot.sections[0].resetsAt == nil)
    }

    @Test("An empty or unrelated screen yields no sections")
    func emptyScreen() {
        #expect(UsageParser.parse(screenText: "").isEmpty)
        #expect(UsageParser.parse(screenText: "Welcome back\n❯ ").isEmpty)
    }
}
