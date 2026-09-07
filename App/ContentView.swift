import SwiftUI

struct ContentView: View {
    @Binding var pendingRoute: AppRoute?
    @State private var path: [AppRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .quickStudy(let deckName, let noteID):
                        QuickStudyView(initialDeckName: deckName, initialNoteID: noteID)
                    case .conversation:
                        ConversationHomeView()
                    case .settings:
                        AppSettingsView()
                    }
                }
        }
        .onAppear { consumePendingRoute() }
        .onChange(of: pendingRoute) { _, _ in consumePendingRoute() }
    }

    private func consumePendingRoute() {
        guard let route = pendingRoute else { return }
        path = [route]
        pendingRoute = nil
    }
}

private struct HomeView: View {
    @State private var importedDeckCount = AppGroupStore.loadDeckExport()?.decks.count ?? 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Brand.appChinese)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(Brand.appPinyin)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 18)

                NavigationLink(value: AppRoute.quickStudy()) {
                    ProjectCard(
                        title: Brand.quickStudyChinese,
                        subtitle: Brand.quickStudyPinyin,
                        detail: importedDeckCount > 0 ? "\(importedDeckCount) imported deck\(importedDeckCount == 1 ? "" : "s")" : "Anki-based self study",
                        symbol: "rectangle.stack.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quick-study")

                NavigationLink(value: AppRoute.conversation) {
                    ProjectCard(
                        title: Brand.conversationChinese,
                        subtitle: Brand.conversationPinyin,
                        detail: "Persistent Mandarin language partner",
                        symbol: "bubble.left.and.bubble.right.fill"
                    )
                }
                .buttonStyle(.plain)

                Text("快学 and 汉语谈话 keep independent learning state. Conversation memory never reads your Anki decks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .navigationTitle(Brand.appChinese)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
        .onAppear {
            importedDeckCount = AppGroupStore.loadDeckExport()?.decks.count ?? 0
        }
    }
}

private struct ProjectCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
