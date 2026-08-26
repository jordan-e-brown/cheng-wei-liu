import SwiftUI
import WidgetKit

struct FlashcardEntry: TimelineEntry {
    let date: Date
    let note: AnkiNote?
    let deckName: String?
}

struct FlashcardProvider: TimelineProvider {
    private let preferredDecks = ["Chinese Grammar (汉语 语法)", "Neri's Chinese Course"]

    func placeholder(in context: Context) -> FlashcardEntry {
        FlashcardEntry(
            date: Date(),
            note: AnkiNote(
                id: "placeholder",
                noteType: nil,
                tags: [],
                fields: [
                    AnkiField(name: "Hanzi", value: "认识"),
                    AnkiField(name: "Pinyin", value: "rènshi"),
                    AnkiField(name: "English", value: "to know; recognize")
                ]
            ),
            deckName: "Neri's Chinese Course"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FlashcardEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlashcardEntry>) -> Void) {
        let now = Date()
        let interval = AppGroupStore.refreshInterval
        let next = Calendar.current.date(byAdding: .minute, value: interval.minutes, to: now)
            ?? now.addingTimeInterval(TimeInterval(interval.minutes * 60))
        completion(Timeline(entries: [entry(for: now)], policy: .after(next)))
    }

    private func entry(for date: Date) -> FlashcardEntry {
        guard let export = AppGroupStore.loadDeckExport() else {
            return FlashcardEntry(date: date, note: nil, deckName: nil)
        }

        let selectedDecks = preferredDecks.compactMap { name in
            export.decks.first(where: { $0.name == name && !$0.notes.isEmpty })
        }
        let decks = selectedDecks.isEmpty ? export.decks.filter { !$0.notes.isEmpty } : selectedDecks
        guard !decks.isEmpty else {
            return FlashcardEntry(date: date, note: nil, deckName: nil)
        }

        let intervalSeconds = max(1, AppGroupStore.refreshInterval.minutes * 60)
        let slot = Int(date.timeIntervalSince1970) / intervalSeconds
        let nonnegativeSlot = slot == Int.min ? 0 : abs(slot)
        let deck = decks[nonnegativeSlot % decks.count]
        let cardSlot = nonnegativeSlot / max(1, decks.count)
        let note = deck.notes[cardSlot % deck.notes.count]
        return FlashcardEntry(date: date, note: note, deckName: deck.name)
    }
}

struct ChengWeiLiuWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlashcardEntry

    var body: some View {
        if let note = entry.note {
            VStack(alignment: family == .systemSmall ? .center : .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Brand.appChinese)
                            .font(.caption.bold())
                        if family != .systemSmall {
                            Text(Brand.appPinyin)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Brand.quickStudyChinese)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Text(note.hanzi)
                    .font(.system(size: family == .systemSmall ? 34 : 42, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)

                if let pinyin = note.pinyin {
                    Text(pinyin)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if family != .systemSmall, let meaning = note.meaning {
                    Text(meaning)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                Spacer(minLength: 2)

                if family != .systemSmall, let deck = entry.deckName {
                    Text(deck)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(deepLinkURL(noteID: note.id, deckName: entry.deckName))
        } else {
            VStack(spacing: 6) {
                Text(Brand.appChinese).font(.headline)
                Text(Brand.appPinyin).font(.caption).foregroundStyle(.secondary)
                Text("Import Anki data in 快学")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "chengweiliu://quick-study"))
        }
    }

    private func deepLinkURL(noteID: String, deckName: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "chengweiliu"
        components.host = "quick-study"
        var items = [URLQueryItem(name: "noteID", value: noteID)]
        if let deckName {
            items.append(URLQueryItem(name: "deck", value: deckName))
        }
        components.queryItems = items
        return components.url
    }
}

struct ChengWeiLiuWidget: Widget {
    let kind = "ChengWeiLiuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlashcardProvider()) { entry in
            ChengWeiLiuWidgetView(entry: entry)
        }
        .configurationDisplayName("成为流 · 快学")
        .description("Rotating cards from your imported Anki decks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ChengWeiLiuWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChengWeiLiuWidget()
    }
}
