import SwiftUI

@main
struct ChengWeiLiuApp: App {
    @State private var pendingRoute: AppRoute?

    var body: some Scene {
        WindowGroup {
            ContentView(pendingRoute: $pendingRoute)
                .onOpenURL { url in
                    pendingRoute = AppDeepLink.route(from: url)
                }
        }
    }
}
