import SwiftUI

struct ConversationMemoryView: View {
    @State private var memory: String?
    @State private var errorMessage: String?
    @State private var confirmingReset = false
    private let client = ConversationClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("谈话记忆")
                        .font(.title.bold())
                    Text("Tánhuà Jìyì")
                        .foregroundStyle(.secondary)
                }

                if let memory {
                    Text(memory)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView()
                }

                Text("This memory belongs only to 汉语谈话. It is not derived from your 快学 decks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Clear conversation memory", role: .destructive) {
                    confirmingReset = true
                }
                .buttonStyle(.bordered)
                .disabled(memory == nil)
            }
            .padding()
        }
        .navigationTitle("谈话记忆")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Clear 汉语谈话 memory?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Clear memory", role: .destructive) {
                Task { await reset() }
            }
        } message: {
            Text("Conversation transcripts remain, but the cross-session learner memory is reset.")
        }
        .alert("Memory error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func load() async {
        do {
            memory = try await client.memory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reset() async {
        do {
            try await client.resetMemory()
            memory = try await client.memory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
