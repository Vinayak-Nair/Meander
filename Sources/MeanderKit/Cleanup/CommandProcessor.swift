import Foundation

/// Interprets spoken editing / formatting commands inside dictated text and
/// rewrites them as the corresponding characters — "new line" → a line break,
/// "comma" → ",", "scratch that" → deletes the current sentence, and so on.
///
/// It runs *before* cleanup so the cleaner polishes the already-edited text, and
/// is intentionally deterministic (no model, no network). The commands are
/// English, so the pipeline only applies it to English / Latin-script dictation.
public struct CommandProcessor {
    public init() {}

    /// Human-readable list of supported commands, for surfacing in the UI.
    public static let reference: [(spoken: String, effect: String)] = [
        ("new line", "line break"),
        ("new paragraph", "blank line"),
        ("new bullet", "bullet point"),
        ("period / full stop", "."),
        ("comma", ","),
        ("question mark", "?"),
        ("exclamation mark", "!"),
        ("colon / semicolon", ": ;"),
        ("open / close paren", "( )"),
        ("scratch that", "delete last sentence"),
    ]

    public func process(_ text: String) -> String {
        let words = text
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        guard !words.isEmpty else { return text }

        var builder = Builder()
        var i = 0
        while i < words.count {
            let consumed = apply(words, at: i, into: &builder)
            if consumed > 0 {
                i += consumed
            } else {
                builder.append(word: words[i])
                i += 1
            }
        }
        return builder.result()
    }

    /// Tries to interpret a command starting at `i`. Returns how many words it
    /// consumed (0 means "not a command, emit the word as-is").
    private func apply(_ words: [String], at i: Int, into b: inout Builder) -> Int {
        let w0 = Self.normalize(words[i])
        let w1 = i + 1 < words.count ? Self.normalize(words[i + 1]) : ""

        switch (w0, w1) {
        case ("new", "line"):                                    b.append(lineBreak: "\n");   return 2
        case ("new", "paragraph"):                               b.append(lineBreak: "\n\n"); return 2
        case ("new", "bullet"), ("bullet", "point"):             b.append(lineBreak: "\n- "); return 2
        case ("full", "stop"):                                   b.append(punctuation: "."); return 2
        case ("question", "mark"):                               b.append(punctuation: "?"); return 2
        case ("exclamation", "mark"), ("exclamation", "point"):  b.append(punctuation: "!"); return 2
        case ("open", "parenthesis"), ("open", "paren"):         b.append(opening: "(");     return 2
        case ("close", "parenthesis"), ("close", "paren"):       b.append(punctuation: ")"); return 2
        case ("scratch", "that"), ("delete", "that"):            b.deleteSentence();         return 2
        default: break
        }

        switch w0 {
        case "period":    b.append(punctuation: "."); return 1
        case "comma":     b.append(punctuation: ","); return 1
        case "colon":     b.append(punctuation: ":"); return 1
        case "semicolon": b.append(punctuation: ";"); return 1
        default:          return 0
        }
    }

    /// Lowercases a token and strips surrounding punctuation so a transcriber
    /// that glues punctuation on ("Comma,") still matches the command.
    static func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}

/// Accumulates output text with sensible spacing around words and punctuation.
private struct Builder {
    private var out = ""
    private var attachNext = false  // next word hugs an opener (e.g. after "(")

    mutating func append(word: String) {
        if needsSpace { out += " " }
        out += word
        attachNext = false
    }

    /// Punctuation hugs the preceding text: "done" + "." → "done.".
    mutating func append(punctuation: String) {
        out += punctuation
        attachNext = false
    }

    /// An opener gets a space before but the following word hugs it.
    mutating func append(opening: String) {
        if needsSpace { out += " " }
        out += opening
        attachNext = true
    }

    mutating func append(lineBreak: String) {
        while out.hasSuffix(" ") { out.removeLast() }
        out += lineBreak
        attachNext = false
    }

    /// Removes the current (in-progress) sentence: everything back to the last
    /// sentence terminator or line break.
    mutating func deleteSentence() {
        while out.hasSuffix(" ") { out.removeLast() }
        if let idx = out.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" || $0 == "\n" }) {
            out = String(out[...idx])
        } else {
            out = ""
        }
        attachNext = false
    }

    private var needsSpace: Bool {
        guard let last = out.last else { return false }
        if attachNext { return false }
        return last != " " && last != "\n"
    }

    func result() -> String {
        out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
