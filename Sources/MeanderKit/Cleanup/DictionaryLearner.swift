import Foundation

/// Learns dictionary terms from the user's own corrections: Meander pastes a
/// transcript, the user fixes a misheard name in place, and the fix becomes a
/// vocabulary entry so the next dictation gets it right.
///
/// The caller supplies the pasted transcript plus before/after snapshots of the
/// destination text field. Only replacements *inside the pasted region of the
/// field* are considered — edits the user makes to their own text elsewhere in
/// the same field are ignored, even when they reuse words the dictation also
/// contained. A replacement is learned when it plausibly sounds like what it
/// replaced ("current johar" -> "Karan Johar"), so content rewrites
/// ("noon" -> "night") don't pollute the dictionary.
///
/// The other half of not polluting the dictionary is refusing to learn ordinary
/// English. Every edit inside a pasted region looks like a correction from here,
/// including the user simply carrying on writing their message, and a dictionary
/// that accumulates words like "taking", "present" and "connect" does not sit
/// there harmlessly: `VocabularyCorrector` matches by sound, so each one rewrites
/// every word that rhymes with it, and dictation gets worse the more it is used.
/// A word the speaker might genuinely have said is therefore never learned on its
/// own, however plausible the edit looks; users who really do want one can type it
/// into the dictionary by hand.
public enum DictionaryLearner {
    /// One correction the user demonstrated: the term they typed, and the text
    /// the transcript actually had there.
    ///
    /// `misheardAs` is the half worth keeping. The term alone leaves every later
    /// correction to re-derive "does this span sound like the term?" from a
    /// phonetic threshold, and a mishearing that fell outside that threshold once
    /// will fall outside it every time. Storing the observed wrong form turns the
    /// same repair into an exact lookup.
    public struct LearnedTerm: Equatable, Sendable {
        public let term: String
        public let misheardAs: String

        public init(term: String, misheardAs: String) {
            self.term = term
            self.misheardAs = misheardAs
        }
    }

    /// Fields larger than this are skipped: diffing huge documents is wasteful
    /// and corrections in them are ambiguous anyway.
    private static let maxTokens = 1200
    private static let maxTermWords = 4
    private static let minTermLetters = 3
    /// Looser than `VocabularyCorrector`'s matching thresholds on purpose: the
    /// user just demonstrated the correction, so a badly mangled capture
    /// ("I should have a run" -> "Aishwarya Rai") should still be learned.
    private static let phoneticTolerance = 0.75
    private static let spellingTolerance = 0.5

    public static func newTerms(pasted: String, before: String, after: String, vocabulary: [String]) -> [LearnedTerm] {
        guard before != after, !pasted.isEmpty else { return [] }
        let beforeTokens = tokens(before)
        let afterTokens = tokens(after)
        guard beforeTokens.count <= maxTokens, afterTokens.count <= maxTokens else { return [] }
        let pastedTokens = tokens(pasted)

        // Where in the field the dictation actually sits. An edit only counts
        // as a correction when it lands inside one of these regions.
        let regions = occurrences(of: pastedTokens, in: beforeTokens)
        guard !regions.isEmpty else { return [] }

        var known = Set(vocabulary.map { $0.lowercased() })
        var learned: [LearnedTerm] = []
        for hunk in replaceHunks(beforeTokens, afterTokens) {
            // ArraySlice keeps the parent array's indices, so the hunk's span
            // in the field is just its own index range.
            let span = hunk.old.startIndex..<hunk.old.endIndex
            guard regions.contains(where: { $0.lowerBound <= span.lowerBound && span.upperBound <= $0.upperBound }) else { continue }
            guard let term = candidateTerm(from: hunk.new) else { continue }
            guard !known.contains(term.lowercased()) else { continue }
            guard isPlausibleCorrection(of: hunk.old, to: term) else { continue }
            known.insert(term.lowercased())
            // The replaced span, normalized the same way the term is, so it can
            // be compared against future transcripts word for word.
            let misheard = hunk.old.map(trimEdgePunctuation).filter { !$0.isEmpty }.joined(separator: " ")
            learned.append(LearnedTerm(term: term, misheardAs: misheard))
        }
        return learned
    }

    // MARK: Candidate filtering

    /// The corrected span as a dictionary term, or nil when it doesn't look
    /// like one.
    private static func candidateTerm(from span: ArraySlice<String>) -> String? {
        let cores = span.map(trimEdgePunctuation)
        guard cores.allSatisfy({ !$0.isEmpty }) else { return nil }
        let term = cores.joined(separator: " ")
        // Judged on the raw tokens, not the trimmed cores: the punctuation is
        // itself evidence about where the text came from.
        guard isAcceptableTerm(term, tokens: Array(span)) else { return nil }
        return term
    }

    /// Whether a string belongs in the dictionary at all.
    ///
    /// Shared with `Settings.pruneJunkFromVocabularyOnce`, so the bar for keeping a
    /// stored term is the same as the bar for learning a new one. Dictionaries
    /// built before these rules existed hold entries no version of the learner
    /// would accept today ("us toAre they best.", a file path, "add 1 Sharique
    /// Shamsudeen"), and one definition is what keeps the cleanup honest instead of
    /// being a second, drifting opinion.
    public static func isAcceptableTerm(_ term: String, tokens: [String]? = nil) -> Bool {
        let tokens = tokens ?? term.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...maxTermWords).contains(tokens.count) else { return false }
        guard VocabularyCorrector.lettersOnly(term).count >= minTermLetters else { return false }
        // The dictionary exists for words the models can't be expected to know.
        // Ordinary English is not that, and adding it does active harm.
        guard !CommonWords.isOrdinaryPhrase(term) else { return false }
        // A term is something the user says. Anything ending in sentence
        // punctuation is a captured sentence, not a name.
        guard !term.hasSuffix(".") && !term.hasSuffix("?") && !term.hasSuffix("!") else { return false }
        return tokens.allSatisfy { looksLikeProse($0, inPhrase: tokens.count > 1) }
    }

    /// Whether a token reads as a spoken word rather than something typed at a
    /// machine.
    private static func looksLikeProse(_ token: String, inPhrase: Bool) -> Bool {
        // Paths, URLs and code fragments reach the learner whenever a dictation
        // lands in an editor or a terminal. They are not terms, and their
        // punctuation makes them match strangely once the phonetic layers strip it.
        let disallowed = CharacterSet(charactersIn: "/\\@#$%^&*<>{}[]()|=+~`")
        guard token.rangeOfCharacter(from: disallowed) == nil else { return false }
        // Digits are fine inside a name ("GPT-4"), but a token that is mostly
        // digits is a number the user typed, not a term.
        let digits = token.filter(\.isNumber).count
        guard digits * 2 <= token.count else { return false }
        // Deliberately no rule against a capital mid-token. It looks like a clean
        // tell for two words run together by an editing slip ("toAre"), but the
        // product names this dictionary exists for are spelled the same way
        // ("ChatGPT", "iPhone"), and those slips are already caught as the
        // sentences they are.
        //
        // Inside a phrase, a fragment of a word ("fil o") gives the phonetic layers
        // a stub to match on. A one- or two-letter word standing alone is fine.
        if inPhrase, token.filter(\.isLetter).count < 2 { return false }
        return true
    }

    /// Whether replacing `old` with `term` reads as fixing a mishear rather
    /// than rewriting content. Pure casing fixes always qualify.
    private static func isPlausibleCorrection(of old: ArraySlice<String>, to term: String) -> Bool {
        let oldLetters = VocabularyCorrector.lettersOnly(old.joined(separator: " "))
        let termLetters = VocabularyCorrector.lettersOnly(term)
        guard !oldLetters.isEmpty else { return false }
        if oldLetters == termLetters { return true }

        let spellingDistance = VocabularyCorrector.editDistance(oldLetters, termLetters)
        let spelling = Double(spellingDistance) / Double(max(oldLetters.count, termLetters.count))
        if spelling <= spellingTolerance { return true }

        let oldKey = VocabularyCorrector.phoneticKey(oldLetters)
        let termKey = VocabularyCorrector.phoneticKey(termLetters)
        // Tiny keys make the loose tolerance meaningless ("Noon" and "Night"
        // are one edit apart as keys), so they must pass the spelling check.
        guard oldKey.count >= 2, termKey.count >= 2 else { return false }
        let keyDistance = VocabularyCorrector.editDistance(oldKey, termKey)
        return Double(keyDistance) / Double(max(oldKey.count, termKey.count)) <= phoneticTolerance
    }

    private static func trimEdgePunctuation(_ token: String) -> String {
        let isEdge: (Character) -> Bool = { !$0.isLetter && !$0.isNumber }
        let core = token.drop(while: isEdge)
        return String(core.reversed().drop(while: isEdge).reversed())
    }

    // MARK: Diffing

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Contiguous spans where `a` was replaced by `b` (LCS diff, with adjacent
    /// delete+insert merged into one replacement). Pure insertions and pure
    /// deletions are dropped: they're new content, not corrections.
    private static func replaceHunks(_ a: [String], _ b: [String]) -> [(old: ArraySlice<String>, new: ArraySlice<String>)] {
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var hunks: [(ArraySlice<String>, ArraySlice<String>)] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            let startI = i, startJ = j
            while i < n || j < m {
                if i < n, j < m, a[i] == b[j] { break }
                if j == m || (i < n && lcs[i + 1][j] >= lcs[i][j + 1]) { i += 1 } else { j += 1 }
            }
            let old = a[startI..<i], new = b[startJ..<j]
            if !old.isEmpty, !new.isEmpty { hunks.append((old, new)) }
        }
        return hunks
    }

    /// Token index ranges where `needle` appears as a consecutive run inside
    /// `haystack`. The snapshot is only taken once the field is known to contain
    /// the pasted text, so this is normally exactly one range.
    private static func occurrences(of needle: [String], in haystack: [String]) -> [Range<Int>] {
        guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
        var ranges: [Range<Int>] = []
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle {
                ranges.append(start..<(start + needle.count))
            }
        }
        return ranges
    }
}
