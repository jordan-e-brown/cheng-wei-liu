import Foundation

enum AppRoute: Hashable {
    case quickStudy(deckName: String? = nil, noteID: String? = nil)
    case conversation
    case settings
}

enum AppDeepLink {
    static func route(from url: URL) -> AppRoute? {
        guard url.scheme == "chengweiliu" else { return nil }
        switch url.host {
        case "quick-study":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let deckName = components?.queryItems?.first(where: { $0.name == "deck" })?.value
            let noteID = components?.queryItems?.first(where: { $0.name == "noteID" })?.value
            return .quickStudy(deckName: deckName, noteID: noteID)
        case "conversation":
            return .conversation
        case "settings":
            return .settings
        default:
            return nil
        }
    }
}
