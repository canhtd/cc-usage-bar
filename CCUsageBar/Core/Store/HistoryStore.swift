import Foundation
import OSLog

/// Appends usage snapshots to a JSON Lines file and serves them back for charting.
///
/// JSON Lines keeps appends O(1) and makes a partially written tail recoverable: a corrupt
/// last line costs one sample, not the whole history.
@MainActor
@Observable
final class HistoryStore {
    private(set) var samples: [HistorySample] = []
    private let file: HistoryFile
    private let log = Logger(subsystem: "com.danny.ccusagebar", category: "history")

    init(url: URL = AppSupport.file("history.jsonl")) {
        file = HistoryFile(url: url)
    }

    /// Loads history and drops anything past the retention window (R5: pruned on launch).
    func loadAndPrune() async {
        let loaded = await file.load()
        let kept = HistoryRetention.prune(loaded)
        samples = kept
        if kept.count != loaded.count {
            await file.rewrite(kept)
            log.debug("pruned \(loaded.count - kept.count) expired samples")
        }
    }

    /// Records every section of a successful fetch.
    func record(_ snapshot: UsageSnapshot, profileID: UUID) async {
        let new = snapshot.sections.map {
            HistorySample(timestamp: snapshot.capturedAt, profileID: profileID, section: $0)
        }
        guard !new.isEmpty else { return }
        samples.append(contentsOf: new)
        await file.append(new)
    }

    /// Records one Apify poll (A2), filed under the fixed Apify pseudo-profile.
    func recordApify(_ usage: ApifyUsage) async {
        let sample = HistorySample(apify: usage)
        samples.append(sample)
        await file.append([sample])
    }

    /// Apify spend readings inside a window, as the spike rule wants them.
    func apifySamples(since: Date) -> [ApifySample] {
        HistoryRetention.apifySamples(samples, since: since)
    }

    /// Apify samples for charting, oldest first.
    func apifySeries(since: Date) -> [HistorySample] {
        HistoryRetention.series(
            samples, profileID: HistorySample.apifyProfileID,
            sectionKey: HistorySample.apifySectionKey, since: since)
    }

    func series(profileID: UUID, sectionKey: String, since: Date) -> [HistorySample] {
        HistoryRetention.series(
            samples, profileID: profileID, sectionKey: sectionKey, since: since)
    }

    /// Distinct sections seen for a profile, in first-seen order.
    func sectionTitles(profileID: UUID) -> [(key: String, title: String)] {
        var seen: [String: String] = [:]
        var order: [String] = []
        for sample in samples where sample.profileID == profileID {
            if seen[sample.sectionKey] == nil { order.append(sample.sectionKey) }
            seen[sample.sectionKey] = sample.sectionTitle
        }
        return order.compactMap { key in seen[key].map { (key, $0) } }
    }
}

/// File-system half of the history store, off the main actor.
private actor HistoryFile {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL) {
        self.url = url
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [HistorySample] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(HistorySample.self, from: data)
        }
    }

    func append(_ new: [HistorySample]) {
        let lines = new.compactMap { sample -> String? in
            guard let data = try? encoder.encode(sample) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        guard !lines.isEmpty else { return }
        let payload = Data((lines.joined(separator: "\n") + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        } else {
            try? payload.write(to: url, options: .atomic)
        }
    }

    func rewrite(_ all: [HistorySample]) {
        let lines = all.compactMap { sample -> String? in
            guard let data = try? encoder.encode(sample) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        let payload = Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
        try? payload.write(to: url, options: .atomic)
    }
}
