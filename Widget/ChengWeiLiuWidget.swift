import SwiftUI
import WidgetKit

struct FlashcardEntry: TimelineEntry {
    let date: Date
    let note: AnkiNote?
    let deckName: String?
    var token: String = ""
    var revealed: Bool = false
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
        if context.isPreview { completion(placeholder(in: context)) }
        else { completion(entry(for: Date())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlashcardEntry>) -> Void) {
        let now = Date()
        guard let export = AppGroupStore.loadDeckExport() else {
            completion(Timeline(entries: [entry(for: now)], policy: .after(now.addingTimeInterval(1800))))
            return
        }
        let entries = FlashcardSchedule.timeline(export: export, from: now, interval: AppGroupStore.refreshInterval, state: AppGroupStore.widgetState()).map(Self.entry)
        completion(Timeline(entries: entries.isEmpty ? [entry(for: now)] : entries, policy: .atEnd))
    }

    static func entry(_ card: ScheduledFlashcard) -> FlashcardEntry {
        FlashcardEntry(date: card.date, note: card.note, deckName: card.deckName, token: card.token, revealed: card.revealed)
    }

    private func entry(for date: Date) -> FlashcardEntry {
        guard let export = AppGroupStore.loadDeckExport(),
              let card = FlashcardSchedule.card(export: export, at: date, interval: AppGroupStore.refreshInterval, state: AppGroupStore.widgetState()) else {
            return FlashcardEntry(date: date, note: nil, deckName: nil)
        }
        return Self.entry(card)
    }
}

struct ChengWeiLiuWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FlashcardEntry

    var body: some View {
        if let note = entry.note {
            VStack(alignment: family == .systemSmall ? .center : .leading, spacing: family == .systemSmall ? 3 : 6) {
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

                Spacer(minLength: family == .systemSmall ? 0 : 4)

                Text(note.hanzi)
                    .font(.system(size: family == .systemSmall ? 28 : 42, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(family == .systemSmall && entry.revealed ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)

                if entry.revealed, let pinyin = note.pinyin {
                    Text(pinyin)
                        .font(family == .systemSmall ? .caption2 : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if entry.revealed, let meaning = note.meaning {
                    Text(meaning)
                        .font(family == .systemSmall ? .caption2 : .subheadline)
                        .lineLimit(2)
                }

                if family == .systemLarge, entry.revealed, let example = note.example {
                    Text(example).font(.body).lineLimit(4)
                }

                HStack {
                    if !entry.revealed {
                        Button(intent: WidgetStudyIntent(action: "revealed", token: entry.token)) {
                            Text("Reveal").font(.caption)
                        }.buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                    Button(intent: WidgetStudyIntent(action: "skipped", token: entry.token)) {
                        Image(systemName: "arrow.right").font(.caption)
                    }.buttonStyle(.bordered).accessibilityLabel("Next card")
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
        var items = [URLQueryItem(name: "noteID", value: noteID), URLQueryItem(name: "source", value: "widget")]
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
