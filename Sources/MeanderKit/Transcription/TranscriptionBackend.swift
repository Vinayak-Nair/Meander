import Foundation

/// Transcription engines Meander can use. Keep this separate from model variants:
/// some engines expose multiple models. WhisperKit is the widest on-device engine
/// (English, Indian languages, and international languages); FluidAudio Parakeet
/// is the fastest, covering English and 24 other European languages.
///
/// A backend may only report `supportsLanguageSelection == false` if the language
/// it produces is guaranteed rather than guessed. For Parakeet that guarantee comes
/// from the per-token script filter Meander drives via the language hint, not from
/// the label on the backend: see `ModelManager.parakeetVersion`. A multilingual
/// model left to infer its own output language will occasionally infer wrong.
public enum TranscriptionBackend: String, CaseIterable, Identifiable, Sendable {
    case fluidAudioParakeet = "fluidAudioParakeet"
    case nemotronEnglish = "nemotronEnglish"
    case parakeetEou = "parakeetEou"
    case parakeetUnified = "parakeetUnified"
    case appleSpeech = "appleSpeech"
    case nemotronMultilingual = "nemotronMultilingual"
    case whisperKit = "whisperKit"

    public static let defaultBackend: TranscriptionBackend = .fluidAudioParakeet

    /// Settings written before the backend was renamed. Parakeet was labelled
    /// "English" back when Meander believed the model was English-only.
    private static let legacyIDs: [String: TranscriptionBackend] = [
        "fluidAudioEnglish": .fluidAudioParakeet
    ]

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fluidAudioParakeet:
            return "FluidAudio Parakeet"
        case .nemotronEnglish:
            return "Nemotron English (streaming, beta)"
        case .parakeetEou:
            return "Parakeet Lite (120M, English)"
        case .parakeetUnified:
            return "Parakeet Unified (English)"
        case .appleSpeech:
            return "Apple Speech (macOS 26)"
        case .nemotronMultilingual:
            return "Nemotron Multilingual (streaming, beta)"
        case .whisperKit:
            return "WhisperKit Multilingual"
        }
    }

    public var modelDisplayName: String? {
        switch self {
        case .fluidAudioParakeet:
            return "Parakeet TDT v3"
        case .nemotronEnglish:
            return "Nemotron 0.6B (1120ms)"
        case .parakeetEou:
            return "Parakeet EOU 120M (320ms)"
        case .parakeetUnified:
            return "Parakeet Unified 0.6B (offline)"
        case .appleSpeech:
            return "SpeechAnalyzer (system-managed)"
        case .nemotronMultilingual:
            return "Nemotron 3.5 0.6B (2240ms)"
        case .whisperKit:
            return nil
        }
    }

    /// Whether Meander offers a language picker for this backend.
    ///
    /// Parakeet keeps this `false` for now: the script filter makes its output
    /// language safe to declare, so opening the picker to FluidAudio's 25 European
    /// languages is a UI change rather than a correctness one, and is tracked
    /// separately. Nemotron is genuinely English-only.
    public var supportsLanguageSelection: Bool {
        switch self {
        case .fluidAudioParakeet, .nemotronEnglish, .parakeetEou, .parakeetUnified, .appleSpeech:
            return false
        case .whisperKit, .nemotronMultilingual:
            return true
        }
    }

    /// Backends that need a newer OS than Meander's macOS 14 floor.
    public var isAvailableOnThisSystem: Bool {
        switch self {
        case .appleSpeech:
            if #available(macOS 26.0, *) { return true }
            return false
        default:
            return true
        }
    }

    public static func from(id: String) -> TranscriptionBackend {
        TranscriptionBackend(rawValue: id) ?? legacyIDs[id] ?? .defaultBackend
    }
}
