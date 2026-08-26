import SwiftUI

struct ConversationHomeView: View {
    @State private var sessions: [ConversationSessionSummary] = []
    @State private var loading = false
    @State private var errorMessage: String?
    private let client = ConversationClient()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Brand.conversationChinese)
                        .font(.largeTitle.bold())
                    Text(Brand.conversationPinyin)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("A persistent language partner for natural Mandarin conversation. No Anki data enters this project.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))

                NavigationLink {
                    ConversationView(sessionID: nil, initialMessages: [])
                } label: {
                    Label("开始新的谈话", systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)
                }

                NavigationLink {
                    ConversationMemoryView()
                } label: {
                    Label("谈话记忆", systemImage: "brain.head.profile")
                }
            }

            Section("Recent conversations") {
                if loading {
                    ProgressView()
                } else if sessions.isEmpty {
                    Text("No conversations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            ConversationLoaderView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title)
                                    .lineLimit(2)
                                Text(formattedDate(session.updatedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Brand.conversationChinese)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Connection error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            sessions = try await client.sessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ConversationLoaderView: View {
    let session: ConversationSessionSummary
    @State private var messages: [ChatMessage]?
    @State private var error: String?
    private let client = ConversationClient()

    var body: some View {
        Group {
            if let messages {
                ConversationView(sessionID: session.id, initialMessages: messages)
            } else if let error {
                ContentUnavailableView(
                    "Could not load conversation",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard messages == nil else { return }
            do {
                messages = try await client.messages(sessionID: session.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
