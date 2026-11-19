import Foundation

/// A provider that continues text the user is typing (inline autocomplete).
/// On-device only today: the typed context never leaves the Mac.
public protocol CompletionProvider {
    /// Returns a short continuation of `prefix`, or an empty string for none.
    func complete(prefix: String) async throws -> String
}

public enum CompletionPrompt {
    public static let system = """
    You are an autocomplete engine. The user message is text they are typing, \
    cut off at the cursor. Continue it with the next few words, in the same \
    language, tone and script. Output ONLY the continuation, never repeat the \
    text, never add quotes or commentary. If the text ends in a complete word, \
    start your output with a single space. Keep it under 12 words and stop at the \
    end of the current sentence or clause.
    """

    /// Normalizes a raw model continuation for display at the cursor.
    public static func sanitize(_ raw: String, prefix: String) -> String {
        var text = raw.replacingOccurrences(of: "\r", with: "")
        if let newline = text.firstIndex(of: "\n") { text = String(text[..<newline]) }
        // Models sometimes echo the end of the prefix. Drop the longest overlap
        // between the prefix's tail and the continuation's start (3+ characters,
        // so a single repeated letter is never treated as an echo).
        let trimmed = String(text.drop(while: { $0 == " " }))
        let maxOverlap = min(prefix.count, trimmed.count)
        if maxOverlap >= 3 {
            for k in stride(from: maxOverlap, through: 3, by: -1)
            where prefix.hasSuffix(trimmed.prefix(k)) {
                text = String(trimmed.dropFirst(k))
                break
            }
        }
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        let endsWithSpace = prefix.last?.isWhitespace ?? true
        if endsWithSpace { text = String(text.drop(while: { $0 == " " })) }
        else if let first = text.first, !first.isWhitespace, !first.isPunctuation,
                let last = prefix.last, last.isLetter || last.isNumber {
            // Ambiguous mid-word case: keep as-is so word completions still work.
        }
        return String(text.prefix(120))
    }
}
