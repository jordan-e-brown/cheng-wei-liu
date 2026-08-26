import SwiftUI

struct AppSettingsView: View {
    @State private var refreshIndex = Double(AppGroupStore.refreshInterval.rawValue)
    @AppStorage("conversationBackendURL") private var backendURL = "http://127.0.0.1:8000"
    @State private var backendToken = KeychainStore.string(for: "conversationBackendToken") ?? ""
    @State private var healthStatus: String?
    @State private var checkingHealth = false

    private var selectedInterval: RefreshInterval {
        RefreshInterval(rawValue: Int(refreshIndex.rounded())) ?? .minutes30
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Brand.appChinese)
                        .font(.title.bold())
                    Text(Brand.appPinyin)
                        .foregroundStyle(.secondary)
                }
            }

            Section("快学 · Widget rotation") {
                Text(selectedInterval.label)
                    .font(.headline.monospacedDigit())

                Slider(value: $refreshIndex, in: 0...6, step: 1) {
                    Text("Refresh interval")
                } minimumValueLabel: {
                    Text("15m")
                } maximumValueLabel: {
                    Text("12h")
                }
                .onChange(of: refreshIndex) { _, newValue in
                    if let interval = RefreshInterval(rawValue: Int(newValue.rounded())) {
                        AppGroupStore.refreshInterval = interval
                    }
                }

                Text("15m · 30m · 1h · 2h · 3h · 6h · 12h")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text("WidgetKit treats this as the earliest requested refresh; iOS controls the actual redraw time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("汉语谈话 · Backend") {
                TextField("Backend URL", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("Optional backend bearer token", text: $backendToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: backendToken) { _, value in
                        KeychainStore.set(value, for: "conversationBackendToken")
                    }

                Button {
                    Task { await checkBackend() }
                } label: {
                    if checkingHealth {
                        HStack {
                            ProgressView()
                            Text("Checking…")
                        }
                    } else {
                        Label("Test connection", systemImage: "network")
                    }
                }
                .disabled(checkingHealth)

                if let healthStatus {
                    Text(healthStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("For a physical iPhone on the same Wi-Fi, use your Mac's LAN address, such as http://192.168.1.20:8000. Use HTTPS before exposing the service beyond your LAN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Build identifiers") {
                LabeledContent("App Group", value: SharedConfig.appGroupID)
                    .font(.caption)
                Text("Edit Config/Base.xcconfig before signing the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }

    @MainActor
    private func checkBackend() async {
        checkingHealth = true
        defer { checkingHealth = false }
        do {
            let health = try await ConversationClient().health()
            healthStatus = "Connected · \(health.model) · Headroom \(health.headroom ? "on" : "off")"
        } catch {
            healthStatus = error.localizedDescription
        }
    }
}
