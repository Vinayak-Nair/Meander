import Foundation

/// The user's personal vocabulary: names and terms the speech models keep
/// mishearing ("Karan Johar" -> "current johar"). One list feeds every layer
/// that can fix this: Whisper decode-time biasing and the LLM cleanup prompt.
public enum Vocabulary {
    /// Terms sent to Whisper as a decoding prompt. Whisper's prompt shares a
    /// 224-token budget with prefill, and WhisperKit keeps the prompt's *suffix*
    /// when trimming, so we cap the term count ourselves to keep the outcome
    /// deterministic. ~30 short names fits comfortably.
    public static let maxWhisperTerms = 30

    /// Splits raw user input (one term per line, commas also accepted) into a
    /// clean list: trimmed, blanks dropped, case-insensitive duplicates removed,
    /// original order kept.
    public static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { term in
                guard !term.isEmpty else { return false }
                return seen.insert(term.lowercased()).inserted
            }
    }

    /// Text passed to Whisper as the conditioning prompt (the model treats it as
    /// preceding transcript, which biases decoding toward these spellings).
    /// Plain comma-separated terms, per OpenAI's spelling-hint guidance.
    ///
    /// Correct spellings only, never learned aliases: Whisper biases *toward*
    /// whatever this prompt contains, so feeding it the misheard form would make
    /// the model likelier to produce the mistake. Aliases are for the layers that
    /// repair text after decoding, not for the one that conditions it.
    public static func whisperPrompt(terms: [String]) -> String? {
        guard !terms.isEmpty else { return nil }
        return terms.prefix(maxWhisperTerms).joined(separator: ", ")
    }

    /// Cap on terms named in the cleanup prompt. Unlike the Whisper cap this is
    /// not a hard model limit: it keeps a large dictionary from crowding out the
    /// cleanup instructions themselves, which matters most for the 0.5B on-device
    /// model, and keeps per-dictation prefill cost bounded for every provider.
    public static let maxCleanupTerms = 60

    /// Instruction appended to the LLM cleanup system prompt so mangled names
    /// ("I should have a run") are restored from the user's list.
    public static func cleanupClause(terms: [String], limit: Int = maxCleanupTerms) -> String? {
        guard !terms.isEmpty else { return nil }
        let list = terms.prefix(limit).joined(separator: ", ")
        return """
        The speaker often says these names and terms: \(list). \
        If a word or phrase in the transcript looks like a misrecognition of one \
        of them (similar sound, garbled spelling), replace it with the correct \
        term. Only substitute when the match is plausible from context.
        """
    }

    /// The cleanup clause with learned mistakes spelled out, which is strictly
    /// more useful to the model than the term list alone: "written as X when the
    /// speaker said Y" is a concrete rule, where a bare list leaves the model to
    /// judge phonetic similarity itself. Terms with no learned mistakes still
    /// appear, just without the "heard as" hint.
    public static func cleanupClause(book: VocabularyBook, limit: Int = maxCleanupTerms) -> String? {
        guard !book.isEmpty else { return nil }
        let described = book.entries.prefix(limit).map { entry -> String in
            guard !entry.aliases.isEmpty else { return entry.term }
            // Cap the aliases per term too: a long-lived entry can accumulate
            // many, and one term must not crowd out the rest of the list.
            let heard = entry.aliases.suffix(maxAliasesPerTerm).joined(separator: "\", \"")
            return "\(entry.term) (sometimes transcribed as \"\(heard)\")"
        }
        return """
        The speaker often says these names and terms: \(described.joined(separator: "; ")). \
        If a word or phrase in the transcript looks like a misrecognition of one \
        of them (similar sound, garbled spelling), replace it with the correct \
        term. Only substitute when the match is plausible from context.
        """
    }

    /// Cap on learned mistakes quoted per term in the cleanup prompt.
    public static let maxAliasesPerTerm = 3
}
