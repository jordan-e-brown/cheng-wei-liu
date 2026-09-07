import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImportController: ObservableObject {
    @Published var deckExport = AppGroupStore.loadDeckExport()
    @Published var isImporting = false
    @Published var message: String?
    @Published var failed = false

    func importURL(_ url: URL) {
        run { try DeckImporter.read(url: url) }
    }

    func loadSample() {
        run {
            guard let url = Bundle.main.url(forResource: "anki-widget", withExtension: "json") else { throw ImportFailure(message: "Sample file is missing from the app bundle.") }
            return try Data(contentsOf: url)
        }
    }

    private func run(_ read: @escaping @Sendable () throws -> Data) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AppGroupStore.saveDeckExport(data: read())
                }.value
                deckExport = result.export
                failed = false
                message = "Imported \(result.noteCount) notes from \(result.export.decks.count) decks (\(result.format)). Widget data is ready.\n\n" + result.warnings.joined(separator: "\n")
            } catch {
                failed = true
                message = error.localizedDescription
            }
            isImporting = false
        }
    }
}

struct ActivityDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
