import SwiftUI

@main
struct ChengWeiLiuApp: App {
    @State private var pendingRoute: AppRoute?
    @StateObject private var imports = ImportController()

    var body: some Scene {
        WindowGroup {
            ContentView(pendingRoute: $pendingRoute)
                .environmentObject(imports)
                .alert(imports.failed ? "Import failed" : "Import complete", isPresented: Binding(get: { imports.message != nil }, set: { if !$0 { imports.message = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(imports.message ?? "") }
                .onOpenURL { url in
                    if url.isFileURL {
                        imports.importURL(url)
                        pendingRoute = .quickStudy()
                    } else {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           components.queryItems?.contains(where: { $0.name == "source" && $0.value == "widget" }) == true,
                           case .quickStudy(let deckName, let noteID) = AppDeepLink.route(from: url),
                           let deck = imports.deckExport?.decks.first(where: { $0.name == deckName }),
                           let note = deck.notes.first(where: { $0.id == noteID }) {
                            do { try AppGroupStore.activityStore().record(type: "opened", source: "widget", note: note, deckName: deck.name, profile: imports.deckExport?.sourceProfile) }
                            catch { imports.failed = true; imports.message = error.localizedDescription }
                        }
                        pendingRoute = AppDeepLink.route(from: url)
                    }
                }
        }
    }
}
