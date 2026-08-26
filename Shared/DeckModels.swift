import Foundation

struct DeckExport: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: String?
    let decks: [Deck]
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

    private static func stripHTML(_ input: String) -> String {
        input
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AnkiField: Codable, Sendable {
    let name: String
    let value: String
}
