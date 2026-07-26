import Foundation

/// Transcription engines Drift can use. Keep this separate from model variants:
/// some engines expose multiple models, while FluidAudio is intentionally
/// English-only for the current product focus. WhisperKit is the on-device
/// multilingual engine (English, Indian languages, and international languages).
public enum TranscriptionBackend: String, CaseIterable, Identifiable, Sendable {
    case fluidAudioEnglish = "fluidAudioEnglish"
    case nemotronEnglish = "nemotronEnglish"
    case whisperKit = "whisperKit"

    public static let defaultBackend: TranscriptionBackend = .fluidAudioEnglish

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fluidAudioEnglish:
            return "FluidAudio English"
        case .nemotronEnglish:
            return "Nemotron English (streaming, beta)"
        case .whisperKit:
            return "WhisperKit Multilingual"
        }
    }

    public var modelDisplayName: String? {
        switch self {
        case .fluidAudioEnglish:
            return "Parakeet TDT v3"
        case .nemotronEnglish:
            return "Nemotron 0.6B (1120ms)"
        case .whisperKit:
            return nil
        }
    }

    public var supportsLanguageSelection: Bool {
        switch self {
        case .fluidAudioEnglish, .nemotronEnglish:
            return false
        case .whisperKit:
            return true
        }
    }

    public static func from(id: String) -> TranscriptionBackend {
        TranscriptionBackend(rawValue: id) ?? .defaultBackend
    }
}
