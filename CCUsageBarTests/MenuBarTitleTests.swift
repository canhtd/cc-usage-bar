import Foundation
import Testing

@testable import CCUsageBar

/// F1: `47% · 25%`, coloured by band, dimmed with an em dash when unknown.
@Suite("Menu bar title")
struct MenuBarTitleTests {
    private func snapshot(session: Int?, week: Int?, extra: [UsageSection] = []) -> UsageSnapshot {
        var sections: [UsageSection] = []
        if let session { sections.append(UsageSection(title: "Current session", percentUsed: session)) }
        if let week {
            sections.append(UsageSection(title: "Current week (all models)", percentUsed: week))
        }
        sections.append(contentsOf: extra)
        return UsageSnapshot(sections: sections)
    }

    @Test("Both percentages are shown, session first")
    func bothPercentages() {
        #expect(MenuBarTitle.text(for: snapshot(session: 47, week: 25), state: .ready) == "47% · 25%")
    }

    @Test("A missing section keeps its slot")
    func missingSection() {
        #expect(MenuBarTitle.text(for: snapshot(session: 47, week: nil), state: .ready) == "47% · —")
    }

    @Test("With no familiar sections the first reported bar is shown")
    func unfamiliarSections() {
        let snapshot = snapshot(
            session: nil, week: nil,
            extra: [UsageSection(title: "Current month (Sonnet 9)", percentUsed: 64)])
        #expect(MenuBarTitle.text(for: snapshot, state: .ready) == "64%")
    }

    @Test("Unknown and error states show an em dash")
    func unknownStates() {
        #expect(MenuBarTitle.text(for: nil, state: .never) == "—")
        #expect(MenuBarTitle.text(for: snapshot(session: 47, week: 25), state: .loading) == "—")
        #expect(MenuBarTitle.text(for: snapshot(session: 47, week: 25), state: .needsSetup) == "—")
        #expect(MenuBarTitle.text(for: snapshot(session: 1, week: 1), state: .error(.timedOut)) == "—")
    }

    @Test("Colour bands are 0-69, 70-89, 90-100")
    func severityBands() {
        #expect(MenuBarTitle.severity(forPercent: 0) == .normal)
        #expect(MenuBarTitle.severity(forPercent: 69) == .normal)
        #expect(MenuBarTitle.severity(forPercent: 70) == .warning)
        #expect(MenuBarTitle.severity(forPercent: 89) == .warning)
        #expect(MenuBarTitle.severity(forPercent: 90) == .critical)
        #expect(MenuBarTitle.severity(forPercent: 100) == .critical)
        #expect(MenuBarTitle.severity(forPercent: nil) == .unknown)
    }

    @Test("The worst displayed number drives the colour")
    func severityUsesWorst() {
        #expect(MenuBarTitle.severity(for: snapshot(session: 12, week: 91), state: .ready) == .critical)
        #expect(MenuBarTitle.severity(for: snapshot(session: 75, week: 10), state: .ready) == .warning)
        #expect(MenuBarTitle.severity(for: snapshot(session: 10, week: 10), state: .ready) == .normal)
        #expect(MenuBarTitle.severity(for: nil, state: .never) == .unknown)
    }

    @Test("Rate-limited data is still shown, not blanked")
    func rateLimitedStillShows() {
        #expect(
            MenuBarTitle.text(for: snapshot(session: 100, week: 98), state: .rateLimited)
                == "100% · 98%")
    }

    // MARK: - Apify suffix (A4)

    @Test("the Apify suffix is absent entirely while the module is off")
    func apifySuffixHiddenWhenDisabled() {
        #expect(MenuBarTitle.apifySuffix(percent: 52, isEnabled: false) == nil)
    }

    @Test("an enabled module shows its percentage, or a dash when there is not one")
    func apifySuffix() {
        #expect(MenuBarTitle.apifySuffix(percent: 52, isEnabled: true) == " · A 52%")
        #expect(MenuBarTitle.apifySuffix(percent: nil, isEnabled: true) == " · A —")
    }

    @Test("the Apify figure uses the same severity bands as the Claude one")
    func apifySeverityBands() {
        #expect(MenuBarTitle.severity(forPercent: 69) == .normal)
        #expect(MenuBarTitle.severity(forPercent: 70) == .warning)
        #expect(MenuBarTitle.severity(forPercent: 90) == .critical)
        #expect(MenuBarTitle.severity(forPercent: nil) == .unknown)
    }
}
