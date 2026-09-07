import AppIntents

struct WidgetStudyIntent: AppIntent {
    static var title: LocalizedStringResource = "Study flashcard"
    static var openAppWhenRun = false
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Card token") var token: String

    init() {}
    init(action: String, token: String) { self.action = action; self.token = token }

    func perform() async throws -> some IntentResult {
        try AppGroupStore.widgetAction(action, token: token)
        return .result()
    }
}
