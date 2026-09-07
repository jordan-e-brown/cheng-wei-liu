import XCTest
@testable import ChengWeiLiu

final class ImportPipelineTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func sample() throws -> Data {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "anki-widget", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func data(_ json: String) -> Data { Data(json.utf8) }
    private func crowd() -> Data {
        data("""
        {"__type__":"Deck","name":"Chinese","notes":[],"note_models":[
          {"crowdanki_uuid":"model-1","name":"Mandarin","flds":[{"name":"English","ord":1},{"name":"Hanzi","ord":0}]}],
         "children":[{"name":"Grammar","notes":[{"guid":"abc123","note_model_uuid":"model-1","fields":["虽然","although"],"tags":[]}],"children":[]}]}
        """)
    }

    func testSampleFileProviderImportPersistsWidgetReadableSnapshot() throws {
        let url = root.appendingPathComponent("anki-widget.json")
        try sample().write(to: url)
        let result = try AppGroupStore.saveDeckExport(data: DeckImporter.read(url: url), to: root)
        XCTAssertEqual(result.noteCount, 2)
        let disk = try Data(contentsOf: root.appendingPathComponent(SharedConfig.deckFilename))
        let snapshot = try JSONDecoder().decode(DeckExport.self, from: disk)
        let cards = FlashcardSchedule.timeline(export: snapshot, from: Date(timeIntervalSince1970: 1_800), interval: .minutes30)
        XCTAssertEqual(cards.count, 49)
        XCTAssertEqual(Set(cards.map(\.deckName)).count, 2)
        XCTAssertTrue(cards.allSatisfy { !$0.note.hanzi.isEmpty })
    }

    func testCrowdAnkiNestedDeckAndOrderedFieldMapping() throws {
        let result = try DeckImporter.decode(crowd())
        XCTAssertEqual(result.noteCount, 1)
        XCTAssertEqual(result.export.decks[1].name, "Chinese::Grammar")
        let note = result.export.decks[1].notes[0]
        XCTAssertEqual(note.hanzi, "虽然")
        XCTAssertEqual(note.meaning, "although")
        XCTAssertEqual(note.id, "guid:abc123")
        XCTAssertEqual(note.guid, "abc123")
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testInvalidImportKeepsLastGoodSnapshotAndHistory() throws {
        try AppGroupStore.saveDeckExport(data: sample(), to: root)
        let url = root.appendingPathComponent(SharedConfig.deckFilename)
        let before = try Data(contentsOf: url)
        let note = try DeckImporter.decode(sample()).export.decks[0].notes[0]
        let ledger = StudyActivityStore(root: root)
        try ledger.record(type: "review", note: note, deckName: "Chinese", profile: nil, rating: 3)
        for bad in ["{}", "{", "{\"schemaVersion\":99,\"decks\":[]}", "{\"schemaVersion\":1,\"decks\":[]}"] {
            XCTAssertThrowsError(try AppGroupStore.saveDeckExport(data: data(bad), to: root))
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
        try AppGroupStore.saveDeckExport(data: crowd(), to: root)
        XCTAssertEqual(try ledger.events().count, 1)
    }

    func testNumericIDsAndOptionalTags() throws {
        let result = try DeckImporter.decode(data("""
        {"schemaVersion":2,"sourceProfile":"User 1","decks":[{"name":"Deck","notes":[{"id":1234567890123,"cardIDs":[1234567890124],"fields":[{"name":"Hanzi","value":"你好"}]}]}]}
        """))
        XCTAssertEqual(result.export.decks[0].notes[0].id, "1234567890123")
        XCTAssertEqual(result.export.decks[0].notes[0].cardIDs, ["1234567890124"])
        XCTAssertEqual(result.export.sourceProfile, "User 1")
    }

    func testBOMAndHTMLCloze() throws {
        let result = try DeckImporter.decode(Data([0xef, 0xbb, 0xbf]) + sample())
        XCTAssertEqual(result.noteCount, 2)
        XCTAssertEqual(AnkiNote.stripHTML("<b>{{c1::你好::greeting}}</b>&nbsp;[sound:hello.mp3]"), "你好")
    }

    func testMissingCrowdModelAndMismatchedFieldsFail() throws {
        let raw = String(decoding: crowd(), as: UTF8.self)
        XCTAssertThrowsError(try DeckImporter.decode(data(raw.replacingOccurrences(of: "\"note_model_uuid\":\"model-1\"", with: "\"note_model_uuid\":\"missing\""))))
        XCTAssertThrowsError(try DeckImporter.decode(data(raw.replacingOccurrences(of: "\"虽然\",\"although\"", with: "\"虽然\""))))
    }

    func testDuplicateNotesRejected() throws {
        let decoded = try DeckImporter.decode(sample()).export
        let deck = decoded.decks[0]
        let duplicate = DeckExport(schemaVersion: 2, exportedAt: nil, decks: [Deck(name: deck.name, notes: deck.notes + deck.notes)])
        XCTAssertThrowsError(try DeckImporter.decode(JSONEncoder().encode(duplicate)))
    }

    func testTimelineCoversAllDecksAndUsesIntervalBoundaries() throws {
        let export = try DeckImporter.decode(sample()).export
        let third = Deck(name: "Other", notes: export.decks[0].notes)
        let all = DeckExport(schemaVersion: 2, exportedAt: nil, decks: export.decks + [third])
        for interval in RefreshInterval.allCases {
            let entries = FlashcardSchedule.timeline(export: all, from: Date(timeIntervalSince1970: 101), interval: interval)
            XCTAssertEqual(entries[1].date.timeIntervalSince1970, Double(interval.minutes * 60))
            XCTAssertEqual(Set(entries.prefix(3).map(\.deckName)).count, 3)
            XCTAssertTrue(zip(entries, entries.dropFirst()).allSatisfy { $0.date < $1.date })
        }
    }

    func testEmptyDeckAndRecallState() throws {
        let empty = DeckExport(schemaVersion: 1, exportedAt: nil, decks: [])
        XCTAssertNil(FlashcardSchedule.card(export: empty, at: Date(), interval: .hour1))
        let export = try DeckImporter.decode(sample()).export
        let now = Date(timeIntervalSince1970: 1800)
        let initial = try XCTUnwrap(FlashcardSchedule.card(export: export, at: now, interval: .minutes30))
        let revealed = FlashcardSchedule.card(export: export, at: now, interval: .minutes30, state: WidgetStudyState(offset: 0, revealedToken: initial.token))
        XCTAssertEqual(revealed?.revealed, true)
        let next = FlashcardSchedule.card(export: export, at: now, interval: .minutes30, state: WidgetStudyState(offset: 1, revealedToken: initial.token))
        XCTAssertNotEqual(next?.note.id, initial.note.id)
        XCTAssertEqual(next?.revealed, false)
    }

    func testConcurrentAppAndWidgetEventsSurviveReopenAndRepeatedExports() throws {
        let note = try DeckImporter.decode(sample()).export.decks[0].notes[0]
        let ledger = StudyActivityStore(root: root)
        let errors = NSLock()
        var failures: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            do { try ledger.record(type: "revealed", source: index % 2 == 0 ? "widget" : "app", note: note, deckName: "Deck", profile: nil) }
            catch { errors.lock(); failures.append(error); errors.unlock() }
        }
        XCTAssertTrue(failures.isEmpty)
        let reopened = StudyActivityStore(root: root)
        let events = try reopened.events()
        XCTAssertEqual(events.count, 100)
        XCTAssertEqual(Set(events.map(\.id)).count, 100)
        XCTAssertEqual(Set(events.map(\.deviceID)).count, 1)
        for _ in 0..<2 {
            let payload = try JSONDecoder().decode(ActivityExport.self, from: reopened.exportData())
            XCTAssertEqual(payload.events.count, 100)
        }
        XCTAssertEqual(try reopened.events().count, 100)
    }

    func testDamagedEventIsReportedRatherThanSilentlyDropped() throws {
        let ledger = StudyActivityStore(root: root)
        let directory = root.appendingPathComponent("study-events")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data("broken").write(to: directory.appendingPathComponent("broken.json"))
        XCTAssertThrowsError(try ledger.exportData())
    }

    func testLargeImportToWidgetBacktest() throws {
        let notes = (0..<20_000).map { AnkiNote(id: String($0 + 1), noteType: nil, tags: [], fields: [AnkiField(name: "Hanzi", value: "你好 \($0)")]) }
        let payload = DeckExport(schemaVersion: 2, exportedAt: nil, decks: [Deck(name: "Large", notes: notes)])
        let result = try AppGroupStore.saveDeckExport(data: JSONEncoder().encode(payload), to: root)
        XCTAssertEqual(result.noteCount, 20_000)
        let entries = FlashcardSchedule.timeline(export: result.export, from: Date(timeIntervalSince1970: 0), interval: .minutes15)
        XCTAssertEqual(entries.count, 97)
        XCTAssertEqual(Set(entries.map { $0.note.id }).count, 97)
    }

    func testWidgetActionsPersistOnceAndRejectStaleTokens() throws {
        let imported = try AppGroupStore.saveDeckExport(data: sample(), to: root)
        let now = Date(timeIntervalSince1970: 1800)
        let card = try XCTUnwrap(FlashcardSchedule.card(export: imported.export, at: now, interval: .minutes30))
        for _ in 0..<2 { try AppGroupStore.widgetAction("revealed", token: card.token, in: root, at: now, interval: .minutes30) }
        XCTAssertEqual(try StudyActivityStore(root: root).events().count, 1)
        XCTAssertEqual(AppGroupStore.widgetState(in: root).revealedToken, card.token)
        try AppGroupStore.widgetAction("skipped", token: card.token, in: root, at: now, interval: .minutes30)
        try AppGroupStore.widgetAction("skipped", token: card.token, in: root, at: now, interval: .minutes30)
        XCTAssertEqual(try StudyActivityStore(root: root).events().count, 2)
        XCTAssertEqual(AppGroupStore.widgetState(in: root).offset, 1)
        XCTAssertThrowsError(try AppGroupStore.widgetAction("unknown", token: card.token, in: root))
    }

    func testWidgetEventSurvivesStateWriteRetryWithoutDuplication() throws {
        let imported = try AppGroupStore.saveDeckExport(data: sample(), to: root)
        let now = Date(timeIntervalSince1970: 1800)
        let card = try XCTUnwrap(FlashcardSchedule.card(export: imported.export, at: now, interval: .minutes30))
        try AppGroupStore.widgetAction("revealed", token: card.token, in: root, at: now, interval: .minutes30)
        // Simulate a crash after the event committed but before the state committed.
        try FileManager.default.removeItem(at: root.appendingPathComponent("widget-state.json"))
        try AppGroupStore.widgetAction("revealed", token: card.token, in: root, at: now, interval: .minutes30)
        XCTAssertEqual(try StudyActivityStore(root: root).events().count, 1)
    }

    func testSwiftActivityContractFixture() throws {
        let note = AnkiNote(id: "101", noteType: "Chinese", tags: [], fields: [AnkiField(name: "Hanzi", value: "你好")], cardIDs: ["201"])
        let export = DeckExport(schemaVersion: 2, exportedAt: "2026-09-07T00:00:00Z", decks: [Deck(name: "中文", notes: [note])], sourceProfile: "User 1")
        try AppGroupStore.saveDeckExport(data: JSONEncoder().encode(export), to: root)
        let snapshot = try XCTUnwrap(AppGroupStore.loadDeckExport(from: root))
        let card = try XCTUnwrap(FlashcardSchedule.card(export: snapshot, at: Date(), interval: .minutes30))
        let ledger = StudyActivityStore(root: root)
        try ledger.record(type: "revealed", source: "widget", note: card.note, deckName: card.deckName, profile: "User 1")
        try ledger.record(type: "review", note: card.note, deckName: card.deckName, profile: "User 1", cardID: "201", rating: 3, elapsed: 1250)
        let activity = try ledger.exportData()
        XCTAssertEqual(try JSONDecoder().decode(ActivityExport.self, from: activity).events.count, 2)
        #if targetEnvironment(simulator)
        // Deliberate simulator test artifact for the Python contract backtest.
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        try activity.write(to: documents.appendingPathComponent("backtest-activity.json"), options: .atomic)
        #endif
    }

    func testWidgetDeepLinkRoundTripsUnicodeAndPunctuation() throws {
        var url = URLComponents()
        url.scheme = "chengweiliu"; url.host = "quick-study"
        url.queryItems = [URLQueryItem(name: "deck", value: "Neri's 中文 & Grammar"), URLQueryItem(name: "noteID", value: "guid:a+b/#")]
        XCTAssertEqual(AppDeepLink.route(from: try XCTUnwrap(url.url)), .quickStudy(deckName: "Neri's 中文 & Grammar", noteID: "guid:a+b/#"))
    }
}
