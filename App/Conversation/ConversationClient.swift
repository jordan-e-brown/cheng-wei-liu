import Foundation

actor ConversationClient {
    enum ClientError: LocalizedError {
        case invalidBaseURL
        case badResponse(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                "The 汉语谈话 backend URL is invalid."
            case .badResponse(let status, let detail):
                if let detail, !detail.isEmpty {
                    "The conversation server returned HTTP \(status): \(detail)"
                } else {
                    "The conversation server returned HTTP \(status)."
                }
            }
        }
    }

    private func baseURL() throws -> URL {
        let raw = UserDefaults.standard.string(forKey: "conversationBackendURL") ?? "http://127.0.0.1:8000"
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            throw ClientError.invalidBaseURL
        }
        return url
    }

    private func request(path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let url = try baseURL().appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = KeychainStore.string(for: "conversationBackendToken"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badResponse(-1, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            var detail: String?
            if let object = try? JSONSerialization.jsonObject(with: data),
               let dictionary = object as? [String: Any] {
                detail = dictionary["detail"] as? String
            }
            throw ClientError.badResponse(http.statusCode, detail)
        }
        return data
    }

    func health() async throws -> HealthResponse {
        let payload = try await data(for: request(path: "v1/health"))
        return try JSONDecoder().decode(HealthResponse.self, from: payload)
    }

    func send(sessionID: String?, message: String) async throws -> ChatResponse {
        let body = try JSONEncoder().encode(ChatRequest(sessionID: sessionID, message: message))
        let payload = try await data(for: request(path: "v1/chat", method: "POST", body: body))
        return try JSONDecoder().decode(ChatResponse.self, from: payload)
    }

    func sessions() async throws -> [ConversationSessionSummary] {
        let payload = try await data(for: request(path: "v1/sessions"))
        return try JSONDecoder().decode(SessionListResponse.self, from: payload).sessions
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        let payload = try await data(for: request(path: "v1/sessions/\(sessionID)"))
        let response = try JSONDecoder().decode(SessionMessagesResponse.self, from: payload)
        let formatter = ISO8601DateFormatter()
        return response.messages.compactMap { item in
            guard let role = ChatMessage.Role(rawValue: item.role) else { return nil }
            return ChatMessage(role: role, content: item.content, createdAt: formatter.date(from: item.createdAt) ?? Date())
        }
    }

    func close(sessionID: String) async throws {
        _ = try await data(for: request(path: "v1/sessions/\(sessionID)/close", method: "POST"))
    }

    func memory() async throws -> String {
        let payload = try await data(for: request(path: "v1/memory"))
        return try JSONDecoder().decode(MemoryResponse.self, from: payload).memory
    }

    func resetMemory() async throws {
        _ = try await data(for: request(path: "v1/memory", method: "DELETE"))
    }
}
