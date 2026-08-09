import Foundation

/// Tells an ordinary English word ("present", "taking", "market") from a name or
/// piece of jargon ("Bengaluru", "Uppekha", "Vercel").
///
/// This is the guard rail the personal dictionary was missing. Both the learner
/// and the corrector work by phonetic similarity, and phonetic similarity has no
/// idea that "connected" is a real word the speaker meant and "current johar" is
/// not. Without that distinction a single ordinary word in the dictionary rewrites
/// every word that rhymes with it: a dictionary containing "taking", "present" and
/// "Connect" turned "I was talking to the president about the connected app" into
/// "I was taking to the present about the Connect app".
///
/// The test is deliberately one-directional. A word being ordinary is strong
/// evidence against touching it; a word being unknown here is not evidence that it
/// *is* a name, just that the safety net doesn't apply. So callers use this only
/// to refuse work, never to justify it.
enum CommonWords {
    /// Whether every word in `phrase` is ordinary English, i.e. replacing the
    /// phrase (or replacing something else *with* it) is unsafe to do on sound
    /// alone. Empty or all-symbol input is not ordinary: there is nothing to
    /// vouch for.
    static func isOrdinaryPhrase(_ phrase: String) -> Bool {
        let words = phrase
            .split(whereSeparator: { $0.isWhitespace })
            .map(core)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        return words.allSatisfy(isOrdinary)
    }

    /// Whether a word is one of the few hundred words that hold English sentences
    /// together: articles, pronouns, prepositions, auxiliaries.
    ///
    /// A much narrower question than `isOrdinary`, and the right one when the task
    /// is finding where a phrase ends rather than whether a word is real. The
    /// system list is no use for that: it carries proper nouns and archaic words
    /// too, so `isOrdinary("nair")` is true and a name would read as a sentence
    /// boundary.
    static func isFrequentWord(_ word: String) -> Bool {
        fallbackWords.contains(core(Substring(word)))
    }

    /// Whether one word is ordinary English. Inflections are folded back to their
    /// stem, because the system word list stores base forms only: without this
    /// "ideas", "deleting" and "opened" all read as unknown and slip through.
    static func isOrdinary(_ word: String) -> Bool {
        let lower = core(Substring(word))
        guard lower.count >= 2 else { return true } // "a", "I", stray letters
        return candidates(for: lower).contains { wordList.contains($0) }
    }

    /// Lowercased letters of a token, apostrophes and edge punctuation dropped, so
    /// "Word," "word" and "word's" all reduce to the same key.
    private static func core(_ token: Substring) -> String {
        String(token.lowercased().filter { $0.isLetter })
    }

    /// The forms to look up: the word itself plus the stems it could be an
    /// inflection of. Over-generating is fine, since a hit on any form only ever
    /// makes the callers *more* cautious.
    private static func candidates(for word: String) -> [String] {
        var forms = [word]
        for (suffix, replacement) in [("ies", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", "")] {
            guard word.hasSuffix(suffix), word.count - suffix.count >= 3 else { continue }
            let stem = String(word.dropLast(suffix.count)) + replacement
            forms.append(stem)
            forms.append(stem + "e") // "deleting" -> "delete", "coding" -> "code"
            // "running" -> "run": undo the doubled consonant.
            if let last = stem.last, stem.dropLast().last == last {
                forms.append(String(stem.dropLast()))
            }
        }
        return forms
    }

    // MARK: Word list

    /// macOS ships the standard Unix word list, which is exactly the shape of
    /// evidence wanted here: broad coverage of ordinary English, and no coverage of
    /// the names and product jargon a personal dictionary exists for. Loaded once,
    /// on first use, so a user with an empty dictionary never pays for it.
    ///
    /// `fallbackWords` covers the case where the file is missing or unreadable.
    /// It is much smaller, but the words it does hold are the frequent ones that
    /// cause the worst damage when they end up in a dictionary.
    private static let wordList: Set<String> = loadSystemWordList() ?? fallbackWords

    private static func loadSystemWordList() -> Set<String>? {
        let candidates = ["/usr/share/dict/words", "/usr/share/dict/web2"]
        for path in candidates {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var words = Set<String>(minimumCapacity: 250_000)
            for line in contents.split(whereSeparator: \.isNewline) {
                let word = line.lowercased()
                // Single letters match everything and vouch for nothing.
                if word.count >= 2 { words.insert(word) }
            }
            // A truncated or placeholder file is worse than no file: it would let
            // common words through while looking like it had checked them.
            if words.count >= 10_000 {
                words.formUnion(fallbackWords)
                return words
            }
        }
        return nil
    }

    /// Frequent English words, contractions and function words, used when the
    /// system list is unavailable and merged into it when it is (the system list
    /// has no contractions).
    private static let fallbackWords: Set<String> = [
        "a", "about", "above", "after", "again", "against", "all", "also", "am", "an", "and",
        "any", "are", "aren't", "as", "ask", "at", "back", "be", "because", "been", "before",
        "being", "below", "best", "better", "between", "both", "but", "by", "call", "came",
        "can", "can't", "cannot", "case", "come", "could", "couldn't", "create", "day", "did",
        "didn't", "do", "does", "doesn't", "doing", "don't", "done", "down", "during", "each",
        "end", "even", "ever", "every", "few", "find", "first", "for", "from", "further", "get",
        "getting", "give", "go", "going", "good", "got", "great", "had", "hadn't", "has",
        "hasn't", "have", "haven't", "having", "he", "he'd", "he'll", "he's", "her", "here",
        "hers", "herself", "him", "himself", "his", "how", "i", "i'd", "i'll", "i'm", "i've",
        "if", "in", "into", "is", "isn't", "it", "it's", "its", "itself", "just", "keep",
        "kind", "know", "last", "least", "let", "let's", "like", "long", "look", "made",
        "make", "many", "may", "me", "mean", "might", "mode", "more", "most", "much", "must",
        "my", "myself", "need", "never", "new", "next", "no", "nor", "not", "now", "of", "off",
        "on", "once", "one", "only", "open", "or", "other", "our", "ours", "ourselves", "out",
        "over", "own", "part", "people", "place", "point", "put", "same", "say", "see", "set",
        "shall", "she", "she'd", "she'll", "she's", "should", "shouldn't", "since", "so",
        "some", "still", "such", "sure", "take", "taking", "tell", "term", "than", "that",
        "that's", "the", "their", "theirs", "them", "themselves", "then", "there", "there's",
        "these", "they", "they'd", "they'll", "they're", "they've", "thing", "think", "this",
        "those", "though", "through", "time", "to", "today", "too", "top", "try", "under",
        "until", "up", "us", "use", "used", "user", "using", "very", "want", "was", "wasn't",
        "way", "we", "we'd", "we'll", "we're", "we've", "well", "went", "were", "weren't",
        "what", "what's", "when", "where", "whether", "which", "while", "who", "who's", "whom",
        "why", "will", "with", "won't", "word", "work", "would", "wouldn't", "yes", "yet",
        "you", "you'd", "you'll", "you're", "you've", "your", "yours", "yourself",
    ]
}
