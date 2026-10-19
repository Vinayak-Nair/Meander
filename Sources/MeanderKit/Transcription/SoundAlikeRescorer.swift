import Foundation

/// A word from the transcript together with the stretch of audio it came from.
/// Kept free of any transcription library's types so the rescoring rule can be
/// tested with hand-written numbers instead of a model.
public struct TimedWord: Sendable, Equatable {
    public let text: String
    public let startTime: Double
    public let endTime: Double

    public init(text: String, startTime: Double, endTime: Double) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Word endings that a sound-alike pair carries along with it. If "log" and
/// "lock" are confusable, so are "logs" and "locks", without either plural being
/// written down anywhere. The spelling rules here are ordinary English
/// orthography, not facts about any particular word.
enum WordSuffix: CaseIterable {
    case none, plural, past, progressive, possessive

    func applied(to base: String) -> String {
        switch self {
        case .none: return base
        case .plural: return base + (Self.endsInSibilant(base) ? "es" : "s")
        case .possessive: return base + "'s"
        case .past: return Self.doublingFinalConsonant(base) + "ed"
        case .progressive: return Self.doublingFinalConsonant(base) + "ing"
        }
    }

    private static func endsInSibilant(_ base: String) -> Bool {
        ["s", "x", "z", "ch", "sh"].contains { base.hasSuffix($0) }
    }

    /// The consonant-vowel-consonant doubling rule: "log" becomes "logg" before a
    /// vowel-initial ending, while "lock" (two final consonants) does not.
    private static func doublingFinalConsonant(_ base: String) -> String {
        let letters = Array(base)
        guard letters.count >= 3 else { return base }
        let vowels = Set("aeiou")
        let last = letters[letters.count - 1]
        let middle = letters[letters.count - 2]
        let first = letters[letters.count - 3]
        guard !vowels.contains(last), !"wxy".contains(last) else { return base }
        guard vowels.contains(middle), !vowels.contains(first) else { return base }
        return base + String(last)
    }
}

/// Words the acoustics barely separate, where Parakeet's choice would be worth a
/// second look against the recording.
///
/// A group is a set of spellings, not a preferred spelling and its corrections:
/// nothing here would say "log" should become "lock" or the reverse. Which one
/// wins is decided entirely by `SoundAlikeRescorer`, from the audio. Adding a pair
/// is one line, which is the point of keeping this table separate from the rule.
///
/// **The table is empty, and log/lock is deliberately not in it.**
///
/// The pair was measured twice, on synthesized voices and then on real speech.
/// `SoundAlikeRescorerTests` holds the summary.
///
/// Synthesized: 108 clips (18 sentences x 6 voices), 117 log/lock occurrences.
/// Parakeet TDT v3 got 90.6% right on its own. Asked which spelling its own audio
/// supported, the CTC head answered correctly 39-50% of the time depending on the
/// alignment window, and leaned toward "log" almost regardless of what was said.
///
/// Real speech: one speaker reading 20 phrases, 20 occurrences. Parakeet got 19.
/// The CTC head got 13 at best, 8 at the widest window. It did not rescue the one
/// word Parakeet missed - it backed the error by 1.65 nats. At every window the
/// best available threshold scored net -1: nothing repaired, one correct word
/// broken.
///
/// What rules out a cautious threshold is that CTC's confidence carries no
/// information about its correctness. Among its most emphatic opinions on real
/// speech (2.0 nats or more) it was right 2 times out of 4, and the two largest
/// margins in the whole set were both wrong. A high threshold does not filter for
/// the cases it has right, it just filters for the cases it feels strongly about.
///
/// The failure is in the evidence, not the arithmetic - the same scorer, over the
/// same windows, rates "banana" and "elephant" roughly ten nats worse than either
/// real candidate.
///
/// The two spellings differ by one CTC token in the same frame ("g" against
/// "ck"), which is exactly the voicing distinction a 110M-parameter CTC head
/// resolves worst. A pair that differs by more, or over more frames, may well
/// separate; this one does not, so nothing is enabled here rather than shipping a
/// coin flip over Parakeet's own answer.
public enum SoundAlikeGroups {
    public static let all: [[String]] = []

    /// Base spellings that share a group with `base`, excluding it.
    static func alternatives(to base: String, in groups: [[String]]) -> [String] {
        groups.first { $0.contains(base) }?.filter { $0 != base } ?? []
    }
}

/// Second-guesses individual words against the recording, and only against the
/// recording.
///
/// For a word that belongs to a sound-alike group, every spelling in that group
/// is scored over exactly the frames the word occupies. Parakeet's own choice
/// keeps the word unless a rival explains those frames better by a clear margin,
/// so a tie, a near-tie, or missing evidence all leave the transcript alone. No
/// sentence meaning, no language model, and no per-word replacement rules are
/// involved: the same code decides every group in the table.
public struct SoundAlikeRescorer {

    public struct Config: Sendable {
        /// Slack around the word's reported boundaries, covering the imprecision
        /// between the decoder's timings and the CTC head's frames.
        public var marginSeconds: Double
        /// How much better, in log-likelihood, a rival spelling must explain the
        /// audio before it may replace what Parakeet decoded. Measured in nats:
        /// 1.0 means "about three times as likely".
        public var minimumWinMargin: Double

        public init(marginSeconds: Double = 0.10, minimumWinMargin: Double) {
            self.marginSeconds = marginSeconds
            self.minimumWinMargin = minimumWinMargin
        }
    }

    /// One spelling and how well it explains the word's audio.
    public struct Candidate: Sendable, Equatable {
        public let word: String
        public let score: Double
    }

    /// What the audio said about one word of the transcript.
    public struct Verdict: Sendable, Equatable {
        public let wordIndex: Int
        /// The spelling Parakeet decoded.
        public let original: String
        /// Every group spelling scored over this word's frames, best first.
        public let candidates: [Candidate]
        /// The spelling that replaced the original, or nil when it stood.
        public let replacement: String?

        /// How much better the leading spelling explains the audio than
        /// Parakeet's own. Zero or negative means Parakeet's word already won.
        public var margin: Double {
            guard let best = candidates.first,
                  let incumbent = candidates.first(where: { $0.word == original })
            else { return 0 }
            return best.score - incumbent.score
        }
    }

    public struct Result: Sendable, Equatable {
        public let text: String
        public let verdicts: [Verdict]

        public var wasModified: Bool { verdicts.contains { $0.replacement != nil } }
    }

    private let config: Config
    private let groups: [[String]]
    /// Candidate spellings as CTC token ids. More than one sequence may be
    /// returned (a word-initial and a mid-word tokenization); every candidate is
    /// scored across all of its variants, so no spelling gets an unfair shape.
    private let tokenize: @Sendable (String) -> [[Int]]

    public init(
        config: Config,
        groups: [[String]] = SoundAlikeGroups.all,
        tokenize: @escaping @Sendable (String) -> [[Int]]
    ) {
        self.config = config
        self.groups = groups
        self.tokenize = tokenize
    }

    /// Re-examines `text` against the audio behind `words`.
    ///
    /// `words` must be the decoder's own word timings for this transcript, in
    /// order. When the two disagree about how many words there are, nothing is
    /// changed: without a trustworthy alignment there is no trustworthy window to
    /// score, and leaving the transcript alone is the safe answer.
    public func rescore(
        text: String,
        words: [TimedWord],
        logProbs: [[Float]],
        frameDuration: Double,
        blankId: Int
    ) -> Result {
        var pieces = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let spoken = pieces.indices.filter { !pieces[$0].isEmpty }
        guard !logProbs.isEmpty, frameDuration > 0, spoken.count == words.count else {
            return Result(text: text, verdicts: [])
        }

        var verdicts: [Verdict] = []
        for (position, index) in spoken.enumerated() {
            guard let core = Self.core(of: pieces[index]) else { continue }
            let spelling = pieces[index][core].lowercased()
            let word = words[position]
            // The decoder's timing must describe the word we are about to judge.
            guard Self.core(of: word.text).map({ word.text[$0].lowercased() }) == spelling
            else { continue }
            guard let match = Self.match(spelling: spelling, in: groups) else { continue }

            let rivals = SoundAlikeGroups.alternatives(to: match.base, in: groups)
                .map { match.suffix.applied(to: $0) }
            guard !rivals.isEmpty else { continue }

            let window = frames(for: word, frameDuration: frameDuration, total: logProbs.count)
            let scored = ([spelling] + rivals).compactMap { candidate in
                score(candidate, logProbs: logProbs, blankId: blankId, window: window)
                    .map { Candidate(word: candidate, score: $0) }
            }
            // Parakeet's own word must be scoreable, or there is nothing to beat.
            guard let incumbent = scored.first(where: { $0.word == spelling }) else { continue }

            let ranked = scored.sorted { $0.score > $1.score }
            let winner = ranked[0]
            let replacement = winner.word != spelling
                && winner.score - incumbent.score >= config.minimumWinMargin
                ? winner.word
                : nil
            if let replacement {
                pieces[index].replaceSubrange(core, with: Self.matchingCase(of: pieces[index][core], in: replacement))
            }
            verdicts.append(
                Verdict(wordIndex: position, original: spelling, candidates: ranked, replacement: replacement)
            )
        }

        return Result(text: pieces.joined(separator: " "), verdicts: verdicts)
    }

    /// Best log-likelihood across a candidate's tokenizations.
    private func score(
        _ candidate: String,
        logProbs: [[Float]],
        blankId: Int,
        window: Range<Int>
    ) -> Double? {
        tokenize(candidate).compactMap {
            ConstrainedCTCScorer.logLikelihood(
                tokens: $0,
                logProbs: logProbs,
                blankId: blankId,
                startFrame: window.lowerBound,
                endFrame: window.upperBound
            )
        }.max()
    }

    private func frames(for word: TimedWord, frameDuration: Double, total: Int) -> Range<Int> {
        let first = max(0, Int(((word.startTime - config.marginSeconds) / frameDuration).rounded(.down)))
        let last = min(total, Int(((word.endTime + config.marginSeconds) / frameDuration).rounded(.up)))
        return first < last ? first..<last : 0..<0
    }

    // MARK: Word shapes

    /// The letters-and-apostrophes heart of a transcript word, ignoring
    /// surrounding punctuation. Nil when there is nothing to judge.
    static func core(of piece: String) -> Range<String.Index>? {
        let isCore: (Character) -> Bool = { $0.isLetter || $0 == "'" }
        guard let first = piece.firstIndex(where: isCore),
              let last = piece.lastIndex(where: isCore)
        else { return nil }
        return first..<piece.index(after: last)
    }

    /// The group spelling and ending that produce `spelling`, if any.
    static func match(spelling: String, in groups: [[String]]) -> (base: String, suffix: WordSuffix)? {
        for group in groups {
            for base in group {
                for suffix in WordSuffix.allCases where suffix.applied(to: base) == spelling {
                    return (base, suffix)
                }
            }
        }
        return nil
    }

    /// `replacement` wearing the capitalization of the word it stands in for.
    static func matchingCase(of original: Substring, in replacement: String) -> String {
        if original.count > 1, original.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return replacement.uppercased()
        }
        if original.first?.isUppercase == true {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
