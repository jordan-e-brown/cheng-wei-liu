import Foundation

struct DeckImportResult: Sendable {
    let export: DeckExport
    let format: String
    let warnings: [String]
    var noteCount: Int { export.decks.reduce(0) { $0 + $1.notes.count } }
}

struct ImportFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum DeckImporter {
    static let maximumBytes = 50 * 1024 * 1024

    static func decode(_ data: Data) throws -> DeckImportResult {
        guard data.count <= maximumBytes else { throw ImportFailure(message: "JSON exceeds the 50 MB import limit. Export fewer decks at a time.") }
        var data = data
        if data.starts(with: [0xef, 0xbb, 0xbf]) { data.removeFirst(3) }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportFailure(message: "Expected a JSON object from the desktop exporter or CrowdAnki.")
        }
        let result: DeckImportResult
        if root["schemaVersion"] != nil {
            do {
                let export = try JSONDecoder().decode(DeckExport.self, from: data)
                guard [1, 2].contains(export.schemaVersion) else { throw ImportFailure(message: "Unsupported schemaVersion \(export.schemaVersion). Update the app or export schema 1 or 2.") }
                result = DeckImportResult(export: export, format: "AnkiConnect JSON", warnings: [])
            } catch let error as DecodingError {
                let context: DecodingError.Context
                switch error {
                case .keyNotFound(_, let c), .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c): context = c
                @unknown default: throw error
                }
                throw ImportFailure(message: "Invalid Anki JSON at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)")
            }
        } else if root["__type__"] as? String == "Deck" || root["note_models"] != nil {
            var decks: [Deck] = []
            try crowdDeck(root, parent: "", models: [:], depth: 0, decks: &decks)
            result = DeckImportResult(export: DeckExport(schemaVersion: 2, exportedAt: nil, decks: decks), format: "CrowdAnki JSON", warnings: ["Text fields imported. External audio/images and Anki templates are not included. CrowdAnki GUIDs support activity tags; graded scheduler sync requires an AnkiConnect export with card IDs."])
        } else {
            throw ImportFailure(message: "Unrecognized JSON. Choose anki-widget.json from the desktop exporter, or CrowdAnki's deck JSON. Anki .apkg/.colpkg packages must be exported as JSON for this version.")
        }
        try validate(result.export)
        return result
    }

    static func validate(_ export: DeckExport) throws {
        guard !export.decks.isEmpty else { throw ImportFailure(message: "No decks found. Your current import has been kept.") }
        var names = Set<String>()
        var total = 0
        for deck in export.decks {
            guard !deck.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, names.insert(deck.name).inserted else {
                throw ImportFailure(message: "Deck names must be nonempty and unique: \(deck.name).")
            }
            var ids = Set<String>()
            for note in deck.notes {
                guard !note.id.isEmpty, ids.insert(note.id).inserted else { throw ImportFailure(message: "Missing or duplicate note ID in \(deck.name): \(note.id).") }
                guard !note.fields.isEmpty, note.fields.contains(where: { !AnkiNote.stripHTML($0.value).isEmpty }) else { throw ImportFailure(message: "Note \(note.id) in \(deck.name) has no readable text fields.") }
                guard Set(note.fields.map { $0.name.lowercased() }).count == note.fields.count,
                      note.fields.allSatisfy({ !$0.name.isEmpty }) else { throw ImportFailure(message: "Note \(note.id) has missing or duplicate field names.") }
                if let cards = note.cardIDs, Set(cards).count != cards.count || cards.contains(where: { Int64($0).map { $0 <= 0 } ?? true }) {
                    throw ImportFailure(message: "Note \(note.id) has invalid card IDs.")
                }
            }
            total += deck.notes.count
        }
        guard total > 0 else { throw ImportFailure(message: "The file contains zero notes. Your current import has been kept.") }
    }

    private static func crowdDeck(_ node: [String: Any], parent: String, models inherited: [String: [String: Any]], depth: Int, decks: inout [Deck]) throws {
        guard depth < 64, let name = node["name"] as? String, !name.isEmpty else { throw ImportFailure(message: "CrowdAnki deck name is missing or nesting exceeds 64 levels.") }
        let fullName = parent.isEmpty ? name : parent + "::" + name
        var models = inherited
        if let list = node["note_models"] as? [[String: Any]] {
            for model in list {
                guard let uuid = model["crowdanki_uuid"] as? String else { throw ImportFailure(message: "CrowdAnki model is missing crowdanki_uuid.") }
                models[uuid] = model
            }
        }
        guard let rawNotes = node["notes"] as? [[String: Any]] else { throw ImportFailure(message: "CrowdAnki deck \(fullName) is missing its notes array.") }
        let notes = try rawNotes.map { raw -> AnkiNote in
            guard let guid = raw["guid"] as? String, !guid.isEmpty,
                  let modelID = raw["note_model_uuid"] as? String, let model = models[modelID],
                  let fields = model["flds"] as? [[String: Any]], let values = raw["fields"] as? [String], fields.count == values.count else {
                throw ImportFailure(message: "CrowdAnki note in \(fullName) has a missing GUID, model, or mismatched field count. Transfer the complete deck JSON with note_models.")
            }
            let ordered = fields.sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
            let named = try zip(ordered, values).map { field, value -> AnkiField in
                guard let name = field["name"] as? String else { throw ImportFailure(message: "CrowdAnki model field has no name.") }
                return AnkiField(name: name, value: value)
            }
            return AnkiNote(id: "guid:" + guid, noteType: model["name"] as? String, tags: raw["tags"] as? [String] ?? [], fields: named, guid: guid)
        }
        decks.append(Deck(name: fullName, notes: notes))
        if let children = node["children"] {
            guard let children = children as? [[String: Any]] else { throw ImportFailure(message: "Invalid CrowdAnki children array.") }
            for child in children { try crowdDeck(child, parent: fullName, models: models, depth: depth + 1, decks: &decks) }
        }
    }

    /// Coordinates File Provider/iCloud materialization while the security scope stays open.
    static func read(url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let size = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= maximumBytes else { throw ImportFailure(message: "JSON exceeds the 50 MB import limit.") }
                return try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ImportFailure(message: "The file provider could not open this file. Download it in Files and try again.") }
        return try result.get()
    }
}
