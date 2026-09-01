import Foundation

extension ProjectDocument {
    @discardableResult
    mutating func migrateToCurrentSchema() -> Bool {
        var changed = schemaVersion < 3
        if schemaVersion < 3 { schemaVersion = 3 }
        var nextID = lyrics.credits.map(\.id).max() ?? 0
        for index in lyrics.credits.indices where lyrics.credits[index].id == 0 {
            nextID += 1
            lyrics.credits[index].id = nextID
            changed = true
        }
        syncCreditCues()
        return changed
    }

    mutating func syncCreditCues() {
        let ids = Set(lyrics.credits.map(\.id))
        timeline.removeAll { $0.type == "credit" && ($0.creditID == nil || !ids.contains($0.creditID!)) }
        let existing = Set(timeline.compactMap { $0.type == "credit" ? $0.creditID : nil })
        var insertAt = 0
        for credit in lyrics.credits where !existing.contains(credit.id) {
            timeline.insert(.credit(id: credit.id, timeMS: 0), at: insertAt)
            insertAt += 1
        }
        sortCreditCues()
    }

    mutating func sortCreditCues() {
        let credits = timeline.filter { $0.type == "credit" }
            .sorted {
                ($0.timeMS ?? 0, $0.creditID ?? 0) < ($1.timeMS ?? 0, $1.creditID ?? 0)
            }
        let rest = timeline.filter { $0.type != "credit" }
        timeline = credits + rest
    }

    mutating func addCredit(label: String, value: String) {
        let id = (lyrics.credits.map(\.id).max() ?? 0) + 1
        lyrics.credits.append(Credit(id: id, label: label, value: value))
        syncCreditCues()
    }

    mutating func removeCredit(id: UInt64) {
        lyrics.credits.removeAll { $0.id == id }
        syncCreditCues()
    }

    mutating func setCreditTime(id: UInt64, milliseconds: UInt64) {
        syncCreditCues()
        if let index = timeline.firstIndex(where: { $0.type == "credit" && $0.creditID == id }) {
            timeline[index].timeMS = milliseconds
        }
        sortCreditCues()
    }

    mutating func mergeCredits() {
        guard lyrics.credits.count >= 2 else { return }
        let merged = lyrics.credits.map(\.displayText).filter { !$0.isEmpty }.joined(separator: " / ")
        let id = lyrics.credits[0].id
        lyrics.credits = [Credit(id: id, label: "", value: merged)]
        syncCreditCues()
        setCreditTime(id: id, milliseconds: 0)
    }

    func creditTime(id: UInt64) -> UInt64? {
        timeline.first { $0.type == "credit" && $0.creditID == id }?.timeMS
    }

    var creditCues: [(id: UInt64, timeMS: UInt64, text: String)] {
        lyrics.credits.compactMap { credit in
            guard let time = creditTime(id: credit.id) else { return nil }
            return (credit.id, time, credit.displayText)
        }
    }

    var creditIntroTooShort: Bool {
        let times = lyrics.credits.compactMap { creditTime(id: $0.id) }
        guard times.count >= 2, times.allSatisfy({ $0 == 0 }) else { return false }
        let firstLyric = lyrics.lines.flatMap(\.segments)
            .compactMap { $0.timing.finalPoint?.timeMS ?? $0.timing.gemini?.timeMS }
            .min() ?? 0
        return firstLyric > 0 && firstLyric < 500 + 1_500 * UInt64(times.count)
    }
}
