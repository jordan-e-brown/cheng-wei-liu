import SwiftUI
import UniformTypeIdentifiers

struct QuickStudyView: View {
    let initialDeckName: String?
    let initialNoteID: String?
    @EnvironmentObject private var imports: ImportController
    @State private var importing = false
    @State private var exporting = false
    @State private var activityDocument: ActivityDocument?
    @State private var eventCount = 0
    @State private var error: String?
    @State private var replacingWithSample = false

    init(initialDeckName: String? = nil, initialNoteID: String? = nil) {
        self.initialDeckName = initialDeckName; self.initialNoteID = initialNoteID
    }

    var body: some View {
        Group {
            if let export = imports.deckExport, let target = deepLinkDeck(in: export) {
                DeckCardsView(deck: target, initialNoteID: initialNoteID, profile: export.sourceProfile)
                    .id(target.name + (initialNoteID ?? "") + (export.exportedAt ?? ""))
            } else { deckList }
        }
        .navigationTitle(Brand.quickStudyChinese)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): imports.importURL(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .fileExporter(isPresented: $exporting, document: activityDocument, contentType: .json, defaultFilename: "chengweiliu-activity") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
        .alert("Study activity", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Replace imported decks with the sample? Study history is kept.", isPresented: $replacingWithSample, titleVisibility: .visible) {
            Button("Load sample", role: .destructive) { imports.loadSample() }
        }
        .onAppear { refreshCount() }
    }

    private var deckList: some View {
        List {
            Section {
                Text("快学 · Kuài Xué").font(.title.bold())
                Text("Import decks, practice recall, and send your study activity back to Anki Desktop.").foregroundStyle(.secondary)
            }
            if let export = imports.deckExport {
                Section("Decks · \(export.decks.reduce(0) { $0 + $1.notes.count }) notes") {
                    ForEach(export.decks.sorted { $0.name < $1.name }) { deck in
                        NavigationLink {
                            DeckCardsView(deck: deck, initialNoteID: nil, profile: export.sourceProfile)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(deck.name)
                                Text("\(deck.notes.count) notes").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("deck-" + deck.name)
                    }
                }
            } else {
                ContentUnavailableView("No Anki data imported", systemImage: "square.and.arrow.down", description: Text("Choose AnkiConnect or CrowdAnki JSON from Files, iCloud Drive, or AirDrop."))
            }
            Section("Import") {
                Button(imports.deckExport == nil ? "Import Anki JSON" : "Replace imported Anki JSON") { importing = true }
                    .disabled(imports.isImporting)
                Button("Try sample decks") {
                    if imports.deckExport == nil { imports.loadSample() } else { replacingWithSample = true }
                }.disabled(imports.isImporting)
                if imports.isImporting { ProgressView("Validating and importing…") }
                Text("Import replaces the deck snapshot and keeps study history. JSON imports text fields; external media and card templates are not rendered.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Activity → Anki Desktop") {
                Text("\(eventCount) saved interactions").accessibilityIdentifier("activity-count")
                Button("Export study activity") {
                    do {
                        activityDocument = ActivityDocument(data: try AppGroupStore.activityStore().exportData())
                        exporting = true
                    } catch { self.error = error.localizedDescription }
                }
                Text("Export keeps your history on this device. The desktop bridge skips previously processed events. Reviews of notes without one known card ID are saved as practice only.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func refreshCount() {
        do { eventCount = try AppGroupStore.activityStore().events().count }
        catch { self.error = error.localizedDescription }
    }

    private func deepLinkDeck(in export: DeckExport) -> Deck? {
        guard initialDeckName != nil || initialNoteID != nil else { return nil }
        if let name = initialDeckName, let deck = export.decks.first(where: { $0.name == name }),
           initialNoteID == nil || deck.notes.contains(where: { $0.id == initialNoteID }) { return deck }
        return export.decks.first { deck in deck.notes.contains { $0.id == initialNoteID } }
    }
}

private struct DeckCardsView: View {
    let deck: Deck
    let initialNoteID: String?
    let profile: String?
    @State private var index: Int
    @State private var showingAnswer = false
    @State private var startedAt = Date()
    @State private var error: String?
    @State private var rated = false

    init(deck: Deck, initialNoteID: String?, profile: String?) {
        self.deck = deck; self.initialNoteID = initialNoteID; self.profile = profile
        _index = State(initialValue: initialNoteID.flatMap { id in deck.notes.firstIndex { $0.id == id } } ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if deck.notes.isEmpty { ContentUnavailableView("Empty deck", systemImage: "rectangle.stack") }
                else {
                    let note = deck.notes[index]
                    Text(note.hanzi).font(.system(size: 48, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.55).multilineTextAlignment(.center).textSelection(.enabled).padding(.top, 30)
                    if showingAnswer {
                        if let pinyin = note.pinyin { Text(pinyin).font(.title3).foregroundStyle(.secondary) }
                        if let meaning = note.meaning { Text(meaning).font(.title3) }
                        if let example = note.example { Text(example).foregroundStyle(.secondary) }
                        HStack {
                            ForEach(Array(["Again", "Hard", "Good", "Easy"].enumerated()), id: \.offset) { rating, title in
                                Button(title) { rate(rating + 1) }.buttonStyle(.bordered).disabled(rated)
                            }
                        }
                        Text(rated ? "Rating saved. Continue to the next note." : "Rate your recall after revealing the answer.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Show answer") {
                            if record("revealed") { showingAnswer = true }
                        }.buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Button("Previous") { move(-1) }.buttonStyle(.bordered)
                        Spacer()
                        Text("\(index + 1) / \(deck.notes.count)").font(.caption.monospacedDigit())
                        Spacer()
                        Button("Next") { move(1) }.buttonStyle(.borderedProminent)
                    }
                }
            }.multilineTextAlignment(.center).padding()
        }
        .navigationTitle(deck.name).navigationBarTitleDisplayMode(.inline)
        .onAppear { if !deck.notes.isEmpty { _ = record("opened"); startedAt = Date() } }
        .alert("Could not save activity", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func move(_ delta: Int) {
        if !rated && !record("skipped") { return }
        index = (index + delta + deck.notes.count) % deck.notes.count
        showingAnswer = false; rated = false; startedAt = Date()
        _ = record("opened")
    }

    private func rate(_ rating: Int) {
        guard !rated else { return }
        if record("review", rating: rating) { rated = true }
    }

    private func record(_ type: String, rating: Int? = nil) -> Bool {
        let note = deck.notes[index]
        do {
            let cardID = note.cardIDs?.count == 1 ? note.cardIDs?.first : nil
            try AppGroupStore.activityStore().record(type: type, note: note, deckName: deck.name, profile: profile, cardID: cardID, rating: rating, elapsed: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)))
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
