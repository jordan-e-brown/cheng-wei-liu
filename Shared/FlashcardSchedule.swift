import Foundation
import CryptoKit

struct WidgetStudyState: Codable {
    var offset = 0
    var revealedToken: String? = nil
}

struct ScheduledFlashcard {
    let date: Date
    let note: AnkiNote
    let deckName: String
    let token: String
    let revealed: Bool
}

enum FlashcardSchedule {
    static let preferredDecks = ["Chinese Grammar (汉语 语法)", "Neri's Chinese Course"]

    static func card(export: DeckExport, at date: Date, interval: RefreshInterval, state: WidgetStudyState = .init()) -> ScheduledFlashcard? {
        let available = export.decks.filter { !$0.notes.isEmpty }
        // Include subdecks and every imported deck; preferences only affect ordering.
        let decks = available.sorted {
            let l = preferredDecks.firstIndex(of: $0.name) ?? Int.max
            let r = preferredDecks.firstIndex(of: $1.name) ?? Int.max
            return l == r ? $0.name < $1.name : l < r
        }
        guard !decks.isEmpty else { return nil }
        let slot = max(0, Int(date.timeIntervalSince1970 / Double(interval.minutes * 60))) + state.offset
        let deck = decks[slot % decks.count]
        let note = deck.notes[(slot / decks.count) % deck.notes.count]
        let content = note.fields.map { $0.name + "=" + $0.value }.joined(separator: "\u{1f}")
        let fingerprint = SHA256.hash(data: Data((content + (export.exportedAt ?? "") + (export.sourceProfile ?? "")).utf8)).map { String(format: "%02x", $0) }.joined()
        let token = "\(slot)|\(deck.name)|\(note.id)|\(fingerprint)"
        return ScheduledFlashcard(date: date, note: note, deckName: deck.name, token: token, revealed: state.revealedToken == token)
    }

    static func timeline(export: DeckExport, from date: Date, interval: RefreshInterval, state: WidgetStudyState = .init()) -> [ScheduledFlashcard] {
        let seconds = Double(interval.minutes * 60)
        let boundary = (floor(date.timeIntervalSince1970 / seconds) + 1) * seconds
        // Supply a full day ahead, bounded to 96 future entries at 15 minutes.
        let count = max(2, 24 * 60 / interval.minutes)
        let dates = [date] + (0..<count).map { Date(timeIntervalSince1970: boundary + Double($0) * seconds) }
        return dates.compactMap { card(export: export, at: $0, interval: interval, state: state) }
    }
}
