import Foundation

struct DeckExport: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: String?
    let decks: [Deck]
    var sourceProfile: String? = nil
}

struct Deck: Codable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let notes: [AnkiNote]
}

struct AnkiNote: Codable, Identifiable, Sendable {
    let id: String
    let noteType: String?
    let tags: [String]
    let fields: [AnkiField]
    var guid: String? = nil
    var cardIDs: [String]? = nil

    enum CodingKeys: String, CodingKey { case id, noteType, tags, fields, guid, cardIDs }

    init(id: String, noteType: String?, tags: [String], fields: [AnkiField], guid: String? = nil, cardIDs: [String]? = nil) {
        self.id = id; self.noteType = noteType; self.tags = tags; self.fields = fields
        self.guid = guid; self.cardIDs = cardIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? c.decode(String.self, forKey: .id) { id = string }
        else { id = String(try c.decode(Int64.self, forKey: .id)) }
        noteType = try c.decodeIfPresent(String.self, forKey: .noteType)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        fields = try c.decode([AnkiField].self, forKey: .fields)
        guid = try c.decodeIfPresent(String.self, forKey: .guid)
        if let strings = try? c.decode([String].self, forKey: .cardIDs) { cardIDs = strings }
        else { cardIDs = try c.decodeIfPresent([Int64].self, forKey: .cardIDs)?.map(String.init) }
    }

    var hanzi: String {
        field(namedLike: ["hanzi", "chinese", "simplified", "expression", "character", "characters", "word", "front"]) ?? firstNonemptyField ?? "—"
    }

    var pinyin: String? {
        field(namedLike: ["pinyin", "reading", "pronunciation", "romanization"])
    }

    var meaning: String? {
        field(namedLike: ["english", "meaning", "definition", "translation", "back"])
    }

    var example: String? {
        field(namedLike: ["example", "sentence", "context", "usage"])
    }

    private var firstNonemptyField: String? {
        fields.lazy.map(\.value).map(Self.stripHTML).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func field(namedLike candidates: [String]) -> String? {
        for candidate in candidates {
            if let match = fields.first(where: { $0.name.lowercased() == candidate }) {
                let cleaned = Self.stripHTML(match.value)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    static func stripHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{\\{c[0-9]+::(.*?)(?:::[^}]*?)?\\}\\}", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AnkiField: Codable, Sendable {
    let name: String
    let value: String
}
