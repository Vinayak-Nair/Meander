import Foundation

/// On-device, no-model, no-network cleanup. Instant and fully private, the
/// default. It is deliberately conservative: for Indic scripts (or auto-detected
/// Indic text) it only normalizes whitespace/punctuation and never strips words,
/// because the English filler/capitalization rules don't apply there.
public struct DeterministicCleanup: CleanupProvider {
    public let id = "deterministic"
    public let displayName = "On-device cleanup"
    public let requiresNetwork = false

    public init() {}

    /// Standalone filler words/phrases removed for Latin-script output.
    private static let fillers = [
        "you know", "i mean", "kind of", "sort of", "you see",
        "umm", "uhh", "uhm", "erm", "hmm",
        "um", "uh", "er", "ah", "mm",
    ]

    public func clean(_ text: String, language: Language) async throws -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }

        t = collapseWhitespace(t)

        let indic = language.script == .indic || (language.isAuto && Self.containsIndic(t))
        if indic {
            // Non-destructive: tidy spacing around punctuation only.
            t = removeSpaceBeforePunctuation(t)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        t = removeDoubledWords(from: t)
        t = removeFillers(from: t)
        t = collapseWhitespace(t)
        t = removeSpaceBeforePunctuation(t)
        t = addSpaceAfterSentencePunctuation(t)
        if language == .english || language.isAuto {
            t = capitalizeStandaloneI(t)
        }
        t = capitalizeSentences(t)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Transforms

    private func collapseWhitespace(_ s: String) -> String {
        var x = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        x = x.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        x = x.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return x
    }

    /// Collapses an immediately repeated word ("the the cat" -> "the cat"), a
    /// common dictation/transcription artifact. Case-insensitive match, keeps the
    /// first occurrence's casing. A word is letters/apostrophes only, so repeated
    /// numbers ("1 1") are left alone. Punctuation between words also blocks the
    /// match, so "no, no" stays intact.
    private func removeDoubledWords(from s: String) -> String {
        s.replacingOccurrences(
            of: "\\b([\\p{L}']+)\\s+\\1\\b",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private func removeFillers(from s: String) -> String {
        let escaped = Self.fillers.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // Match a filler as a whole word, optionally followed by a comma.
        let pattern = "\\b(?:\(escaped))\\b,?"
        var x = s.replacingOccurrences(
            of: pattern, with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Clean up artifacts: leading commas/space, doubled spaces.
        x = x.replacingOccurrences(of: "^[\\s,]+", with: "", options: .regularExpression)
        x = x.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        x = x.replacingOccurrences(of: " ,", with: ",", options: .regularExpression)
        return x
    }

    private func removeSpaceBeforePunctuation(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
    }

    /// Ensures a space follows sentence-ending punctuation when the transcriber
    /// glues the next sentence on (e.g. "done.Next" -> "done. Next"). Restricted
    /// to a letter following `.!?` so decimals ("3.14") and ellipses are untouched.
    private func addSpaceAfterSentencePunctuation(_ s: String) -> String {
        s.replacingOccurrences(
            of: "([.!?])(\\p{L})", with: "$1 $2", options: .regularExpression
        )
    }

    private func capitalizeStandaloneI(_ s: String) -> String {
        s.replacingOccurrences(of: "\\bi\\b", with: "I", options: .regularExpression)
    }

    private func capitalizeSentences(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var capitalizeNext = true
        for ch in s {
            if capitalizeNext, ch.isLetter {
                result.append(contentsOf: String(ch).uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
            }
            if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                capitalizeNext = true
            }
        }
        return result
    }

    // MARK: Script detection

    /// True if the text contains characters from a major Indic script block.
    static func containsIndic(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x0900...0x097F, // Devanagari (Hindi, Marathi…)
                 0x0980...0x09FF, // Bengali
                 0x0A00...0x0A7F, // Gurmukhi
                 0x0A80...0x0AFF, // Gujarati
                 0x0B00...0x0B7F, // Oriya
                 0x0B80...0x0BFF, // Tamil
                 0x0C00...0x0C7F, // Telugu
                 0x0C80...0x0CFF, // Kannada
                 0x0D00...0x0D7F: // Malayalam
                return true
            default:
                continue
            }
        }
        return false
    }
}
