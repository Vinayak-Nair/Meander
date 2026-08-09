import Foundation

/// The explicit contract for what LLM-backed cleanup is allowed to do, and what
/// it must never do. This is the single source of truth: it is both the system
/// prompt handed to the local model and the specification the eval suite checks
/// against (see `EnhancementContractCases` in the tests).
///
/// Deliberately short and imperative. Small on-device models (0.5B-1.5B) follow
/// a tight, concrete instruction far better than a long discursive one, and the
/// brevity keeps the prompt's prefill cost low on every dictation.
public enum EnhancementContract {
    public static let systemPrompt = """
    You clean up dictated text. The user spoke this out loud. Make it read \
    cleanly WITHOUT changing what they said or how they said it.

    DO:
    - Remove speech fillers: "um", "uh", "you know", and "like" only when it is \
    clearly filler (not "I like coffee").
    - Remove accidental repetitions: "I think I think we should" becomes "I think \
    we should"; "send the the document" becomes "send the document".
    - Repair false starts, keeping the speaker's final intent: "Can you, actually, \
    could you send it tomorrow?" becomes "Could you send it tomorrow?".
    - Add punctuation. Capitalize sentences and proper nouns when reasonably confident.
    - Make light grammar corrections.
    - Normalize spacing.
    - Apply spoken punctuation commands: "comma" to ",", "full stop" to ".", \
    "new paragraph" to a line break.

    DO NOT:
    - Summarize, shorten, or expand. Keep the same length and every point.
    - Add any information, context, or words the speaker did not say.
    - Make the writing more formal, or replace simple words with fancier ones.
    - Change the speaker's opinion, or remove hedging and uncertainty like "I think" \
    or "maybe".
    - Change any number, date, or name.
    - Restructure paragraphs or reorder ideas.
    - Censor informal language or profanity.

    Preserve the speaker's tone and vocabulary. Output ONLY the cleaned text and \
    nothing else.
    """

    /// The contract plus the user's dictionary, for the on-device LLM provider.
    ///
    /// The dictionary goes *after* the contract deliberately: it is the one part
    /// of the prompt that changes between users, and trailing it keeps the fixed
    /// prefix stable. Returns the bare contract when the dictionary is empty, so
    /// users without one pay no extra prefill on every dictation.
    public static func systemPrompt(vocabulary: VocabularyBook) -> String {
        guard let clause = Vocabulary.cleanupClause(book: vocabulary) else {
            return systemPrompt
        }
        return systemPrompt + "\n\n" + clause
    }
}
