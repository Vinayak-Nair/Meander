import Foundation

/// Writing system of a language. Drives script-aware text cleanup so we never
/// apply Latin-centric rules (English filler words, capitalization) to non-Latin
/// text. `.indic` and `.other` both take the conservative, non-destructive path.
public enum Script: Sendable {
    case latin
    case indic
    case other
}

/// A spoken language Meander can transcribe. `code` is the Whisper language code
/// (ISO 639-1, or a close variant), or "auto" for Whisper's built-in language
/// detection. Every listed language is transcribable on-device by WhisperKit.
public struct Language: Equatable, Hashable, Sendable, Identifiable {
    public let code: String
    public let displayName: String
    public let script: Script

    public var id: String { code }
    public var isAuto: Bool { code == "auto" }
    /// The code to hand WhisperKit (`nil` means auto-detect).
    public var whisperCode: String? { isAuto ? nil : code }

    public init(code: String, displayName: String, script: Script) {
        self.code = code
        self.displayName = displayName
        self.script = script
    }

    public static let auto = Language(code: "auto", displayName: "Auto-detect", script: .other)

    // MARK: Indic (Whisper-supported)

    public static let hindi     = Language(code: "hi", displayName: "Hindi",     script: .indic)
    public static let bengali   = Language(code: "bn", displayName: "Bengali",   script: .indic)
    public static let tamil     = Language(code: "ta", displayName: "Tamil",     script: .indic)
    public static let telugu    = Language(code: "te", displayName: "Telugu",    script: .indic)
    public static let kannada   = Language(code: "kn", displayName: "Kannada",   script: .indic)
    public static let malayalam = Language(code: "ml", displayName: "Malayalam", script: .indic)
    public static let marathi   = Language(code: "mr", displayName: "Marathi",   script: .indic)
    public static let gujarati  = Language(code: "gu", displayName: "Gujarati",  script: .indic)
    public static let punjabi   = Language(code: "pa", displayName: "Punjabi",   script: .indic)
    public static let urdu      = Language(code: "ur", displayName: "Urdu",      script: .indic)
    public static let nepali    = Language(code: "ne", displayName: "Nepali",    script: .indic)
    public static let sanskrit  = Language(code: "sa", displayName: "Sanskrit",  script: .indic)
    public static let sindhi    = Language(code: "sd", displayName: "Sindhi",    script: .indic)
    public static let assamese  = Language(code: "as", displayName: "Assamese",  script: .indic)

    // MARK: European / Latin-script

    public static let english    = Language(code: "en", displayName: "English",     script: .latin)
    public static let spanish    = Language(code: "es", displayName: "Spanish",     script: .latin)
    public static let french     = Language(code: "fr", displayName: "French",      script: .latin)
    public static let german     = Language(code: "de", displayName: "German",      script: .latin)
    public static let italian    = Language(code: "it", displayName: "Italian",     script: .latin)
    public static let portuguese = Language(code: "pt", displayName: "Portuguese",  script: .latin)
    public static let dutch      = Language(code: "nl", displayName: "Dutch",       script: .latin)
    public static let polish     = Language(code: "pl", displayName: "Polish",      script: .latin)
    public static let turkish    = Language(code: "tr", displayName: "Turkish",     script: .latin)
    public static let swedish    = Language(code: "sv", displayName: "Swedish",     script: .latin)
    public static let danish     = Language(code: "da", displayName: "Danish",      script: .latin)
    public static let norwegian  = Language(code: "no", displayName: "Norwegian",   script: .latin)
    public static let finnish    = Language(code: "fi", displayName: "Finnish",     script: .latin)
    public static let czech      = Language(code: "cs", displayName: "Czech",       script: .latin)
    public static let romanian   = Language(code: "ro", displayName: "Romanian",    script: .latin)
    public static let hungarian  = Language(code: "hu", displayName: "Hungarian",   script: .latin)
    public static let catalan    = Language(code: "ca", displayName: "Catalan",     script: .latin)
    public static let croatian   = Language(code: "hr", displayName: "Croatian",    script: .latin)

    // MARK: Other world languages / non-Latin scripts

    public static let chinese    = Language(code: "zh", displayName: "Chinese",     script: .other)
    public static let japanese   = Language(code: "ja", displayName: "Japanese",    script: .other)
    public static let korean     = Language(code: "ko", displayName: "Korean",      script: .other)
    public static let arabic     = Language(code: "ar", displayName: "Arabic",      script: .other)
    public static let russian    = Language(code: "ru", displayName: "Russian",     script: .other)
    public static let ukrainian  = Language(code: "uk", displayName: "Ukrainian",   script: .other)
    public static let hebrew     = Language(code: "he", displayName: "Hebrew",      script: .other)
    public static let greek      = Language(code: "el", displayName: "Greek",       script: .other)
    public static let thai       = Language(code: "th", displayName: "Thai",        script: .other)
    public static let persian    = Language(code: "fa", displayName: "Persian",     script: .other)
    public static let vietnamese = Language(code: "vi", displayName: "Vietnamese",  script: .other)
    public static let indonesian = Language(code: "id", displayName: "Indonesian",  script: .latin)
    public static let malay      = Language(code: "ms", displayName: "Malay",       script: .latin)
    public static let tagalog    = Language(code: "tl", displayName: "Tagalog",     script: .latin)
    public static let swahili    = Language(code: "sw", displayName: "Swahili",     script: .latin)

    /// The Whisper-supported Indian languages, offered as a group in the picker.
    public static let indianLanguages: [Language] = [
        .hindi, .bengali, .tamil, .telugu, .kannada, .malayalam, .marathi,
        .gujarati, .punjabi, .urdu, .nepali, .sanskrit, .sindhi, .assamese,
    ]

    /// Widely-spoken international languages beyond English and the Indic group.
    public static let internationalLanguages: [Language] = [
        .spanish, .french, .german, .italian, .portuguese, .dutch, .polish,
        .turkish, .swedish, .danish, .norwegian, .finnish, .czech, .romanian,
        .hungarian, .catalan, .croatian, .indonesian, .malay, .tagalog, .swahili,
        .chinese, .japanese, .korean, .arabic, .russian, .ukrainian, .hebrew,
        .greek, .thai, .persian, .vietnamese,
    ]

    /// Languages offered by the WhisperKit backend: auto-detect, English, the
    /// Indian-language group, then the rest of the world. Fully on-device.
    public static let whisperKitLanguages: [Language] =
        [.auto, .english] + indianLanguages + internationalLanguages

    /// All language ids Meander may persist or display.
    public static let all: [Language] = whisperKitLanguages

    public static func from(code: String) -> Language {
        all.first { $0.code == code } ?? .english
    }
}
