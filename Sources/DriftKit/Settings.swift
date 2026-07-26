import Foundation

/// Typed, persisted configuration. Backed by `UserDefaults`; inject a custom
/// suite in tests. Note: the API key lives in UserDefaults for now; moving it to
/// the Keychain is tracked in the roadmap.
public final class Settings {
    public static let shared = Settings()

    private let d: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.d = defaults }

    // MARK: Transcription

    public var transcriptionBackendID: String {
        get { d.string(forKey: "transcriptionBackendID") ?? TranscriptionBackend.defaultBackend.rawValue }
        set { d.set(newValue, forKey: "transcriptionBackendID") }
    }

    public var transcriptionBackend: TranscriptionBackend {
        get { TranscriptionBackend.from(id: transcriptionBackendID) }
        set { transcriptionBackendID = newValue.rawValue }
    }

    public var modelVariant: String {
        get { d.string(forKey: "modelVariant") ?? ModelCatalog.defaultVariant }
        set { d.set(newValue, forKey: "modelVariant") }
    }

    public var modelRepo: String {
        get { d.string(forKey: "modelRepo") ?? "argmaxinc/whisperkit-coreml" }
        set { d.set(newValue, forKey: "modelRepo") }
    }

    /// Optional custom model storage directory (e.g. an external SSD). When nil,
    /// models are stored under Application Support.
    public var modelStoragePath: String? {
        get { d.string(forKey: "modelStoragePath") }
        set { d.set(newValue, forKey: "modelStoragePath") }
    }

    /// Remembers where a downloaded variant lives so relaunches work offline
    /// without re-checking the network.
    public func modelFolderPath(for variant: String) -> String? {
        d.string(forKey: "modelFolder_\(variant)")
    }
    public func setModelFolderPath(_ path: String, for variant: String) {
        d.set(path, forKey: "modelFolder_\(variant)")
    }

    public var languageCode: String {
        get { d.string(forKey: "languageCode") ?? "en" }
        set { d.set(newValue, forKey: "languageCode") }
    }

    public var language: Language {
        get { Language.from(code: languageCode) }
        set { languageCode = newValue.code }
    }

    /// The language used for transcription and cleanup. English-only backends
    /// ignore an old multilingual preference; WhisperKit honors the selection
    /// (including auto-detect).
    public var effectiveLanguage: Language {
        switch transcriptionBackend {
        case .fluidAudioEnglish, .nemotronEnglish:
            return .english
        case .whisperKit:
            return language
        }
    }

    public var inputDeviceID: String {
        get { d.string(forKey: "inputDeviceID") ?? AudioInputDevice.systemDefaultID }
        set { d.set(newValue, forKey: "inputDeviceID") }
    }

    /// The AudioQueue capture path is the default for all microphones because it
    /// starts far faster than an AVAudioEngine graph (lower hotkey-to-mic
    /// latency). Escape hatch, not exposed in UI: set to false to force the
    /// engine path (`defaults write` works).
    public var recorderUsesAudioQueue: Bool {
        get { d.object(forKey: "recorderUsesAudioQueue") as? Bool ?? true }
        set { d.set(newValue, forKey: "recorderUsesAudioQueue") }
    }

    // MARK: Hotkey

    /// Push-to-talk key. Default: Right Option (keycode 61).
    public var pttKeyCode: Int {
        get { d.object(forKey: "pttKeyCode") as? Int ?? 61 }
        set { d.set(newValue, forKey: "pttKeyCode") }
    }

    // MARK: Cleanup

    /// Active cleanup provider id: "none", "deterministic", "openai", or
    /// "ollama". Defaults to the instant on-device rules. (The legacy "apple"
    /// on-device LLM was removed: it cold-loaded the model on every dictation,
    /// costing 14-21s per utterance; its stored value maps back to deterministic.)
    public var cleanupProviderID: String {
        get {
            let stored = d.string(forKey: "cleanupProviderID") ?? Self.defaultCleanupProviderID
            return stored == "apple" ? "deterministic" : stored
        }
        set { d.set(newValue, forKey: "cleanupProviderID") }
    }

    public static let defaultCleanupProviderID = "deterministic"

    // OpenAI-compatible (OpenAI, Groq, Sarvam, LM Studio, …)
    public var openAIBaseURL: String {
        get { d.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1" }
        set { d.set(newValue, forKey: "openAIBaseURL") }
    }
    public var openAIModel: String {
        get { d.string(forKey: "openAIModel") ?? "gpt-4o-mini" }
        set { d.set(newValue, forKey: "openAIModel") }
    }
    public var openAIKey: String {
        get { d.string(forKey: "openAIKey") ?? "" }
        set { d.set(newValue, forKey: "openAIKey") }
    }

    // Ollama (advanced/local)
    public var ollamaBaseURL: String {
        get { d.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434" }
        set { d.set(newValue, forKey: "ollamaBaseURL") }
    }
    public var ollamaModel: String {
        get { d.string(forKey: "ollamaModel") ?? "llama3.2" }
        set { d.set(newValue, forKey: "ollamaModel") }
    }

    // MARK: Vocabulary

    /// The user's vocabulary list as typed (one term per line). Kept raw so the
    /// settings editor round-trips exactly; consumers use `customVocabulary`.
    public var customVocabularyRaw: String {
        get { d.string(forKey: "customVocabularyRaw") ?? "" }
        set { d.set(newValue, forKey: "customVocabularyRaw") }
    }

    /// Parsed personal vocabulary: names and terms the speech models keep
    /// mishearing. Feeds Whisper prompt biasing and the LLM cleanup prompt.
    public var customVocabulary: [String] {
        Vocabulary.parse(customVocabularyRaw)
    }

    // MARK: Per-app formatting

    /// When on, Drift picks a formatting profile based on the app being dictated
    /// into (e.g. Casual in Slack, Code in Xcode).
    public var perAppProfilesEnabled: Bool {
        get { d.object(forKey: "perAppProfilesEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "perAppProfilesEnabled") }
    }

    /// The profile applied to any app without its own rule. User-selectable.
    public var defaultProfileID: String {
        get { d.string(forKey: "defaultProfileID") ?? "standard" }
        set { d.set(newValue, forKey: "defaultProfileID") }
    }

    /// User-chosen profile id per app bundle id, overriding the built-in defaults.
    public var profileOverrides: [String: String] {
        get { d.dictionary(forKey: "profileOverrides") as? [String: String] ?? [:] }
        set { d.set(newValue, forKey: "profileOverrides") }
    }

    public func setProfileOverride(_ profileID: String?, forBundleID id: String) {
        var overrides = profileOverrides
        overrides[id] = profileID
        profileOverrides = overrides
    }

    // MARK: Commands

    /// When on, spoken commands ("new line", "comma", "scratch that"…) are
    /// interpreted as formatting instead of literal words. English only.
    public var commandModeEnabled: Bool {
        get { d.bool(forKey: "commandModeEnabled") }
        set { d.set(newValue, forKey: "commandModeEnabled") }
    }

    // MARK: App state

    public var hasCompletedOnboarding: Bool {
        get { d.bool(forKey: "hasCompletedOnboarding") }
        set { d.set(newValue, forKey: "hasCompletedOnboarding") }
    }
}
