import Foundation

/// A selectable Whisper model. `id` is the WhisperKit variant name, i.e. the
/// subfolder in the model repo (default repo: `argmaxinc/whisperkit-coreml`).
public struct ModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let approxSizeMB: Int
    public let multilingual: Bool

    public init(id: String, displayName: String, approxSizeMB: Int, multilingual: Bool) {
        self.id = id
        self.displayName = displayName
        self.approxSizeMB = approxSizeMB
        self.multilingual = multilingual
    }
}

/// The set of models Meander offers, and the default.
///
/// Variant names must match folders in the WhisperKit model repo. If Argmax
/// renames a variant, update the `id`s here; nothing else in the app changes.
public enum ModelCatalog {
    /// large-v3 turbo: best multilingual accuracy, the right default for Indian
    /// languages. Heavier on 8 GB RAM but uses the Neural Engine.
    public static let defaultVariant = "openai_whisper-large-v3-v20240930"

    public static let options: [ModelOption] = [
        ModelOption(id: "openai_whisper-large-v3-v20240930",
                    displayName: "Large v3 Turbo (best accuracy, recommended)",
                    approxSizeMB: 1560, multilingual: true),
        ModelOption(id: "openai_whisper-large-v3-v20240930_turbo_632MB",
                    displayName: "Large v3 Turbo, compressed (632 MB)",
                    approxSizeMB: 632, multilingual: true),
        ModelOption(id: "openai_whisper-small",
                    displayName: "Small (faster, lighter)",
                    approxSizeMB: 484, multilingual: true),
        ModelOption(id: "openai_whisper-base",
                    displayName: "Base (fastest, lowest accuracy)",
                    approxSizeMB: 145, multilingual: true),
    ]

    public static func option(for id: String) -> ModelOption? {
        options.first { $0.id == id }
    }
}
