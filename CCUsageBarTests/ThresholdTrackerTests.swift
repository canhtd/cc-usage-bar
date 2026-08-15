import Foundation
import Testing

@testable import CCUsageBar

/// F4: each threshold fires once per section, per profile, per reset window.
@Suite("Threshold tracker")
struct ThresholdTrackerTests {
    private let profileA = UUID()
    private let profileB = UUID()
    private let window = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ percent: Int, resetsAt: Date? = nil, title: String = "Current session")
        -> UsageSnapshot
    {
        UsageSnapshot(sections: [
            UsageSection(title: title, percentUsed: percent, resetsText: "Resets 1pm", resetsAt: resetsAt)
        ])
    }

    private func evaluate(
        _ tracker: inout ThresholdTracker, _ snapshot: UsageSnapshot, profile: UUID? = nil
    ) -> [ThresholdEvent] {
        tracker.evaluate(
            snapshot: snapshot, profileID: profile ?? profileA, profileName: "Default",
            thresholds: [80, 95], isEnabled: { _ in true })
    }

    @Test("Below every threshold nothing fires")
    func belowThresholds() {
        var tracker = ThresholdTracker()
        #expect(evaluate(&tracker, snapshot(79, resetsAt: window)).isEmpty)
    }

    @Test("A threshold fires exactly once per window")
    func firesOncePerWindow() {
        var tracker = ThresholdTracker()
        let first = evaluate(&tracker, snapshot(81, resetsAt: window))
        #expect(first.map(\.threshold) == [80])
        #expect(evaluate(&tracker, snapshot(85, resetsAt: window)).isEmpty)
        #expect(evaluate(&tracker, snapshot(96, resetsAt: window)).map(\.threshold) == [95])
        #expect(evaluate(&tracker, snapshot(99, resetsAt: window)).isEmpty)
    }

    @Test("A jump past several thresholds reports the most severe first")
    func multipleCrossingsAtOnce() {
        var tracker = ThresholdTracker()
        #expect(evaluate(&tracker, snapshot(97, resetsAt: window)).map(\.threshold) == [95, 80])
    }

    @Test("A new reset window re-arms the alerts")
    func newWindowRearms() {
        var tracker = ThresholdTracker()
        _ = evaluate(&tracker, snapshot(81, resetsAt: window))
        let next = window.addingTimeInterval(7 * 24 * 3600)
        #expect(evaluate(&tracker, snapshot(82, resetsAt: next)).map(\.threshold) == [80])
        // Rolling the window must not let the set grow without bound.
        #expect(tracker.fired.count == 1)
    }

    @Test("Profiles are tracked independently")
    func profilesAreIndependent() {
        var tracker = ThresholdTracker()
        _ = evaluate(&tracker, snapshot(81, resetsAt: window))
        #expect(evaluate(&tracker, snapshot(81, resetsAt: window), profile: profileB).count == 1)
    }

    @Test("Sections are tracked independently")
    func sectionsAreIndependent() {
        var tracker = ThresholdTracker()
        _ = evaluate(&tracker, snapshot(81, resetsAt: window))
        let week = snapshot(81, resetsAt: window, title: "Current week (all models)")
        #expect(evaluate(&tracker, week).count == 1)
    }

    @Test("A disabled section never fires")
    func disabledSection() {
        var tracker = ThresholdTracker()
        let events = tracker.evaluate(
            snapshot: snapshot(99, resetsAt: window), profileID: profileA, profileName: "Default",
            thresholds: [80], isEnabled: { _ in false })
        #expect(events.isEmpty)
    }

    @Test("The fired set survives a round trip through JSON")
    func codableRoundTrip() throws {
        var tracker = ThresholdTracker()
        _ = evaluate(&tracker, snapshot(96, resetsAt: window))
        let data = try JSONEncoder().encode(tracker)
        var restored = try JSONDecoder().decode(ThresholdTracker.self, from: data)
        #expect(restored == tracker)
        #expect(evaluate(&restored, snapshot(96, resetsAt: window)).isEmpty)
    }
}
