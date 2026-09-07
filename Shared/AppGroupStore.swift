import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum SharedConfig {
    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.example.chengweiliu"
    }

    static let deckFilename = "anki-widget.json"
    static let refreshKey = "widget.refresh.index"
}

enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case minutes15 = 0
    case minutes30
    case hour1
    case hours2
    case hours3
    case hours6
    case hours12

    var id: Int { rawValue }

    var minutes: Int {
        switch self {
        case .minutes15: 15
        case .minutes30: 30
        case .hour1: 60
        case .hours2: 120
        case .hours3: 180
        case .hours6: 360
        case .hours12: 720
        }
    }

    var label: String {
        switch self {
        case .minutes15: "15 min"
        case .minutes30: "30 min"
        case .hour1: "1 hr"
        case .hours2: "2 hr"
        case .hours3: "3 hr"
        case .hours6: "6 hr"
        case .hours12: "12 hr"
        }
    }
}

enum AppGroupStore {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroupID)
    }

    static func loadDeckExport(from directory: URL? = nil) -> DeckExport? {
        guard let url = (directory ?? containerURL)?.appendingPathComponent(SharedConfig.deckFilename),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DeckExport.self, from: data)
    }

    @discardableResult
    static func saveDeckExport(data: Data, to directory: URL? = nil) throws -> DeckImportResult {
        let result = try DeckImporter.decode(data)
        guard let root = directory ?? containerURL else { throw StoreError.appGroupUnavailable }
        // Validate the entire input before replacing the last good snapshot.
        try StudyActivityStore(root: root).withLock {
            try JSONEncoder().encode(result.export).write(to: root.appendingPathComponent(SharedConfig.deckFilename), options: .atomic)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return result
    }

    static func activityStore() throws -> StudyActivityStore {
        guard let root = containerURL else { throw StoreError.appGroupUnavailable }
        return StudyActivityStore(root: root)
    }

    static func widgetState(in directory: URL? = nil) -> WidgetStudyState {
        guard let url = (directory ?? containerURL)?.appendingPathComponent("widget-state.json"),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WidgetStudyState.self, from: data) else { return .init() }
        return state
    }

    static func widgetAction(_ action: String, token: String, in directory: URL? = nil, at date: Date = Date(), interval: RefreshInterval? = nil) throws {
        guard ["revealed", "skipped"].contains(action) else { throw ImportFailure(message: "Unknown widget action.") }
        let store = try directory.map { StudyActivityStore(root: $0) } ?? activityStore()
        try store.withLock {
            guard let export = loadDeckExport(from: directory) else { throw ImportFailure(message: "Import your Anki JSON first.") }
            var state = widgetState(in: directory)
            guard let card = FlashcardSchedule.card(export: export, at: date, interval: interval ?? refreshInterval, state: state), card.token == token else { return }
            if action == "revealed", state.revealedToken == token { return }
            try store.recordUnlocked(type: action, source: "widget", note: card.note, deckName: card.deckName, profile: export.sourceProfile, deduplicationKey: token + "|" + action)
            if action == "skipped" { state.offset += 1; state.revealedToken = nil }
            else { state.revealedToken = token }
            try JSONEncoder().encode(state).write(to: store.root.appendingPathComponent("widget-state.json"), options: .atomic)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static var refreshInterval: RefreshInterval {
        get {
            let defaults = UserDefaults(suiteName: SharedConfig.appGroupID)
            let raw = defaults?.object(forKey: SharedConfig.refreshKey) as? Int
                ?? RefreshInterval.minutes30.rawValue
            return RefreshInterval(rawValue: raw) ?? .minutes30
        }
        set {
            let defaults = UserDefaults(suiteName: SharedConfig.appGroupID)
            defaults?.set(newValue.rawValue, forKey: SharedConfig.refreshKey)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    enum StoreError: LocalizedError {
        case appGroupUnavailable

        var errorDescription: String? {
            "The App Group container is unavailable. Confirm the App Group capability matches APP_GROUP_ID in Config/Base.xcconfig."
        }
    }
}
