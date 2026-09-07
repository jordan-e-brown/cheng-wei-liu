import Foundation
import Darwin
import CryptoKit

struct StudyEvent: Codable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    let deviceID: String
    let timestamp: String
    let type: String
    let source: String
    let noteID: String
    let noteGUID: String?
    let cardID: String?
    let deckName: String
    let sourceProfile: String?
    let rating: Int?
    let elapsedMilliseconds: Int?
}

struct ActivityExport: Codable {
    let schemaVersion: Int
    let exportedAt: String
    let events: [StudyEvent]
}

/// One atomic file per immutable event prevents app/widget read-modify-write loss.
/// The lock coordinates device identity and widget state across both processes.
struct StudyActivityStore {
    let root: URL

    func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = open(root.appendingPathComponent("study.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ImportFailure(message: "Cannot open study storage lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ImportFailure(message: "Cannot lock study storage.") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    func record(type: String, source: String = "app", note: AnkiNote, deckName: String, profile: String?, cardID: String? = nil, rating: Int? = nil, elapsed: Int? = nil) throws {
        try withLock {
            try recordUnlocked(type: type, source: source, note: note, deckName: deckName, profile: profile, cardID: cardID, rating: rating, elapsed: elapsed)
        }
    }

    func recordUnlocked(type: String, source: String, note: AnkiNote, deckName: String, profile: String?, cardID: String? = nil, rating: Int? = nil, elapsed: Int? = nil, deduplicationKey: String? = nil) throws {
        let identityURL = root.appendingPathComponent("device-id.txt")
        let deviceID: String
        if FileManager.default.fileExists(atPath: identityURL.path) { deviceID = try String(contentsOf: identityURL, encoding: .utf8) }
        else { deviceID = UUID().uuidString; try deviceID.write(to: identityURL, atomically: true, encoding: .utf8) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let eventID = deduplicationKey.map { SHA256.hash(data: Data((deviceID + $0).utf8)).map { String(format: "%02x", $0) }.joined() } ?? UUID().uuidString
        let event = StudyEvent(id: eventID, deviceID: deviceID, timestamp: formatter.string(from: Date()), type: type, source: source, noteID: note.id, noteGUID: note.guid, cardID: cardID, deckName: deckName, sourceProfile: profile, rating: rating, elapsedMilliseconds: elapsed)
        let directory = root.appendingPathComponent("study-events", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(event.id + ".json")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try JSONEncoder().encode(event).write(to: destination, options: .atomic)
        }
    }

    func events() throws -> [StudyEvent] {
        try withLock {
            let directory = root.appendingPathComponent("study-events", isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(StudyEvent.self, from: Data(contentsOf: $0)) }
                .sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
        }
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ActivityExport(schemaVersion: 1, exportedAt: ISO8601DateFormatter().string(from: Date()), events: events()))
    }
}
