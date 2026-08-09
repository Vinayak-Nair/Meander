import Foundation

/// Cleans up raw dictation into polished text. The whole point of this protocol
/// is that providers are swappable: deterministic on-device today, an
/// OpenAI-compatible or Indian-language model (e.g. Sarvam) tomorrow, with no
/// changes to the pipeline or UI.
public protocol CleanupProvider {
    var id: String { get }
    var displayName: String { get }
    /// Whether `clean` reaches out over the network (drives privacy messaging).
    var requiresNetwork: Bool { get }
    func clean(_ text: String, language: Language) async throws -> String
}

/// No-op cleanup: returns the raw transcription untouched.
public struct PassthroughCleanup: CleanupProvider {
    public let id = "none"
    public let displayName = "Raw transcription"
    public let requiresNetwork = false
    public init() {}
    public func clean(_ text: String, language: Language) async throws -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Lightweight description of a provider for settings UI, without instantiating it.
public struct CleanupProviderInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let requiresNetwork: Bool
    public let requiresAPIKey: Bool
}

public enum CleanupRegistry {
    public static var all: [CleanupProviderInfo] {
        [
            .init(id: "deterministic", displayName: "On-device rules (fast, no AI)",  requiresNetwork: false, requiresAPIKey: false),
            .init(id: "mlx",           displayName: "On-device LLM (MLX, beta)",      requiresNetwork: false, requiresAPIKey: false),
            .init(id: "none",          displayName: "Raw transcription (no cleanup)", requiresNetwork: false, requiresAPIKey: false),
            .init(id: "openai",        displayName: "Cloud (OpenAI / Groq / Sarvam)", requiresNetwork: true,  requiresAPIKey: true),
            .init(id: "ollama",        displayName: "Local LLM via Ollama (advanced)", requiresNetwork: false, requiresAPIKey: false),
        ]
    }
}

/// Builds the active provider from current settings. The optional `profile`
/// carries the per-app tone instruction and `destination` names the app the
/// text is headed to ("Gmail", "Claude Code"); only the LLM providers use them.
public enum CleanupFactory {
    /// Providers that live in heavier targets (e.g. MLX) register a builder here,
    /// keyed by provider id, so the pipeline can use them without DriftKit taking
    /// a dependency on that target. The app wires these up at launch. Returning a
    /// shared instance (not a fresh one per call) is what keeps a warm model warm.
    public static var externalBuilders: [String: @Sendable (Settings, FormattingProfile, String?) -> CleanupProvider] = [:]

    public static func make(
        settings: Settings,
        profile: FormattingProfile = .standard,
        destination: String? = nil
    ) -> CleanupProvider {
        if let build = externalBuilders[settings.cleanupProviderID] {
            return build(settings, profile, destination)
        }
        switch settings.cleanupProviderID {
        case "none":
            return PassthroughCleanup()
        case "openai":
            return OpenAICompatibleCleanup(
                baseURL: settings.openAIBaseURL,
                model: settings.openAIModel,
                apiKey: settings.openAIKey,
                tone: profile.tone,
                vocabulary: settings.vocabularyBook,
                destination: destination
            )
        case "ollama":
            return OllamaCleanup(
                baseURL: settings.ollamaBaseURL,
                model: settings.ollamaModel,
                tone: profile.tone,
                vocabulary: settings.vocabularyBook,
                destination: destination
            )
        default:
            return DeterministicCleanup()
        }
    }
}

/// Shared instruction used by every LLM-backed provider. Crucially tells the
/// model to keep the original language and script (so Malayalam stays Malayalam).
enum CleanupPrompt {
    static func system(
        for language: Language,
        tone: String? = nil,
        vocabulary: VocabularyBook = .init(),
        destination: String? = nil
    ) -> String {
        let langClause: String
        if language.isAuto {
            langClause = "the same language and script as the input"
        } else {
            langClause = "\(language.displayName) (keep the same script as the input)"
        }
        var prompt = """
        You are a dictation cleanup engine. The user dictated text by voice. \
        Rewrite it as clean written text in \(langClause): remove filler words, \
        fix grammar and punctuation, and apply natural capitalization and spacing. \
        Do NOT translate. Do NOT add information, answer questions, or add commentary. \
        Preserve the original meaning. Output ONLY the cleaned text.
        """
        if let destination, !destination.isEmpty {
            prompt += " The cleaned text will be pasted into \(destination), so shape it the way text is normally written there."
        }
        if let tone, !tone.isEmpty {
            prompt += " \(tone)"
        }
        if let clause = Vocabulary.cleanupClause(book: vocabulary) {
            prompt += " \(clause)"
        }
        return prompt
    }
}

public enum CleanupError: LocalizedError {
    case badResponse(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let m): return "Cleanup failed: \(m)"
        case .http(let code, let m): return "Cleanup HTTP \(code): \(m)"
        }
    }
}
