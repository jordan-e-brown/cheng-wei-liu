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

    static func loadDeckExport() -> DeckExport? {
        guard let url = containerURL?.appendingPathComponent(SharedConfig.deckFilename),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DeckExport.self, from: data)
    }

    static func saveDeckExport(data: Data) throws {
        guard let url = containerURL?.appendingPathComponent(SharedConfig.deckFilename) else {
            throw StoreError.appGroupUnavailable
        }
        _ = try JSONDecoder().decode(DeckExport.self, from: data)
        try data.write(to: url, options: .atomic)
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
