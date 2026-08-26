import SwiftUI

struct ConversationView: View {
    @State private var sessionID: String?
    @State private var messages: [ChatMessage]
    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    private let client = ConversationClient()

    init(sessionID: String?, initialMessages: [ChatMessage]) {
        _sessionID = State(initialValue: sessionID)
        _messages = State(initialValue: initialMessages)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 5) {
                                Text("用汉语开始吧。")
                                    .font(.title3)
                                Text("Yòng Hànyǔ kāishǐ ba.")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if sending {
                            HStack {
                                ProgressView()
                                Text("正在想…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: sending) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("说点什么…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding()
        }
        .navigationTitle(Brand.conversationChinese)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sessionID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("结束") {
                        Task {
                            if let sessionID { try? await client.close(sessionID: sessionID) }
                            dismiss()
                        }
                    }
                }
            }
        }
        .alert("Conversation error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }

        draft = ""
        sending = true
        let localMessage = ChatMessage(role: .user, content: text)
        messages.append(localMessage)
        defer { sending = false }

        do {
            let response = try await client.send(sessionID: sessionID, message: text)
            sessionID = response.sessionID
            messages.append(ChatMessage(role: .assistant, content: response.reply))
        } catch {
            if messages.last?.id == localMessage.id {
                messages.removeLast()
            }
            draft = text
            errorMessage = error.localizedDescription
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            Text(message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 42) }
        }
    }
}
