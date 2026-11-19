import AppIntents

/// Shortcuts and Siri actions for Meander. They drive the same dictation flow the
/// hotkey does, so they work with any shortcut, automation or voice command.

struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Starts Meander dictation if it is ready.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.startDictation()
        return .result()
    }
}

struct StopDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Stops Meander dictation and pastes the result.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppState.shared.stopDictation()
        return .result()
    }
}

struct ToggleDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dictation"
    static let description = IntentDescription("Starts dictation, or stops it if it is already running.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.toggleDictation()
        return .result()
    }
}

struct LatestDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Dictation"
    static let description = IntentDescription("Returns the text of your most recent dictation.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let latest = AppState.shared.transcriptHistory.max { $0.createdAt < $1.createdAt }
        return .result(value: latest?.text ?? "")
    }
}

struct MeanderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: ["Toggle dictation in \(.applicationName)", "Dictate with \(.applicationName)"],
            shortTitle: "Toggle Dictation",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: LatestDictationIntent(),
            phrases: ["Get my latest dictation from \(.applicationName)"],
            shortTitle: "Latest Dictation",
            systemImageName: "text.quote"
        )
    }
}
