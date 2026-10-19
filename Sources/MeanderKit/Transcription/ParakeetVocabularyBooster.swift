import Foundation
import FluidAudio

/// Acoustic vocabulary correction for the Parakeet backend.
///
/// Parakeet has no equivalent of Whisper's conditioning prompt: its TDT decoder
/// takes audio and decoder state, with no place to hand it the user's spellings,
/// so nothing biases it toward a name before decoding. Without this, the
/// dictionary reaches Parakeet output only through the text-level layers, which
/// see the transcript and never the audio.
///
/// FluidAudio ships the missing piece: an auxiliary CTC head that can score how
/// well a candidate spelling matches the actual audio in a given time span. Each
/// transcript word is compared, on acoustic evidence, against the dictionary; a
/// term only replaces a word when the audio supports the term better. That is
/// what makes this different in kind from `VocabularyCorrector` — it is checking
/// the recording, not guessing from spelling.
///
/// Learned mistakes are admitted only when their spelling remains recognizably
/// close to the canonical term. A stored alias is evidence about an earlier
/// correction, not proof that unrelated words mean the dictionary term in a new
/// sentence. The similarity gate keeps useful compressions such as "Ask GP" for
/// "Ask ChatGPT" while rejecting collisions such as "what is DLC".
///
/// Everything here is best-effort. The CTC model is a second, separate download,
/// so it is fetched only once the user actually has dictionary terms, and any
/// failure leaves the transcript exactly as Parakeet produced it.
public actor ParakeetVocabularyBooster {
    /// Keep rescoring anchored to a plausible TDT word or learned alias. FluidAudio's
    /// acoustic-only rescue can otherwise inject a short dictionary term into unrelated
    /// speech (for example, "Xbox" over ordinary sentence fragments).
    static let rescorerConfig = VocabularyRescorer.Config(spotterRescueEnabled: false)

    /// FluidAudio permits 0.50 similarity for small vocabularies. That is useful
    /// for recall, but too permissive for dictation: it allowed the correctly
    /// decoded word "next" to be replaced by the dictionary term "Xbox" at
    /// 0.57 similarity. Keep FluidAudio's size-aware threshold while enforcing
    /// the conservative 0.60 floor it already uses for large vocabularies.
    static let minimumReplacementSimilarity: Float = 0.60

    /// Require the canonical dictionary spelling to win on acoustic evidence.
    /// A positive context-biasing weight can turn a learned alias into a forced
    /// replacement even when the speaker said ordinary prose (for example,
    /// "what I'm" becoming "Ask ChatGPT"). Aliases still nominate candidates;
    /// they no longer receive free score simply for being in the dictionary.
    static let contextBiasingWeight: Float = 0

    /// Minimum letters-only similarity between a learned alias and its canonical
    /// term. This is deliberately independent of transcript similarity: it
    /// decides whether the learned mapping itself is safe enough to reuse.
    static let minimumLearnedAliasSimilarity = 0.50

    static func safeAliases(for entry: VocabularyEntry) -> [String] {
        entry.aliases.filter {
            VocabularyCorrector.spellingSimilarity($0, entry.term)
                >= minimumLearnedAliasSimilarity
        }
    }

    static func replacementSimilarity(forVocabularySize size: Int) -> Float {
        max(
            ContextBiasingConstants.rescorerConfig(forVocabSize: size).minSimilarity,
            minimumReplacementSimilarity
        )
    }

    /// Where the CTC models live. Mirrors `ModelManager`'s layout so a
    /// user-chosen model directory (e.g. an external SSD) holds these too.
    private let modelDirectory: URL

    private var spotter: CtcKeywordSpotter?
    private var tokenizer: CtcTokenizer?
    /// Rescorer for the vocabulary described by `cachedSignature`. Rebuilt when
    /// the dictionary changes, since it precomputes an index over the terms.
    private var rescorer: VocabularyRescorer?
    private var cachedSignature: String?

    /// Set after a load failure so a missing model or an offline first run costs
    /// one attempt per launch rather than a download attempt per dictation.
    /// Dictation is unaffected either way; only boosting is skipped.
    private var loadFailed = false

    public init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    /// Returns a corrected transcript, or nil when boosting did not apply:
    /// an empty dictionary, no token timings, unavailable models, or the
    /// rescorer finding nothing the audio supports changing.
    ///
    /// `samples` must be the same 16kHz audio that produced `text`; the CTC head
    /// re-reads it to score candidate spellings against the recording.
    public func boost(
        text: String,
        tokenTimings: [TokenTiming],
        samples: [Float],
        book: VocabularyBook
    ) async -> String? {
        guard !book.isEmpty, !text.isEmpty, !tokenTimings.isEmpty, !samples.isEmpty else { return nil }
        guard !loadFailed else { return nil }

        // Never fetch during a dictation: this call sits between the user
        // releasing the hotkey and the text landing, and a model download there
        // would stall the paste for as long as the network takes. Absent means
        // "no boost this time"; `prepare()` is what installs it.
        guard Self.isModelInstalled(at: modelDirectory) else { return nil }

        do {
            // Models first: the tokenizer's vocabulary file ships with them, so
            // loading it before them would fail on a fresh install and latch
            // boosting off for the session.
            let spotter = try await loadedSpotter()

            let context = try await vocabularyContext(for: book)
            // Terms too short to tokenize (or below FluidAudio's minimum length)
            // leave nothing for the CTC head to match against.
            guard !context.terms.isEmpty else { return nil }

            let rescorer = try await preparedRescorer(for: book, context: context, spotter: spotter)
            let spotted = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples,
                customVocabulary: context,
                minScore: nil
            )
            guard !spotted.logProbs.isEmpty else { return nil }

            // Thresholds tighten as the dictionary grows: more candidates means
            // more chances for a plausible-but-wrong substitution.
            let output = rescorer.ctcTokenRescore(
                transcript: text,
                tokenTimings: tokenTimings,
                logProbs: spotted.logProbs,
                frameDuration: spotted.frameDuration,
                cbw: Self.contextBiasingWeight,
                marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
                minSimilarity: Self.replacementSimilarity(forVocabularySize: context.terms.count)
            )
            guard output.wasModified else { return nil }
            LatencyLog.record("parakeet vocab boost applied \(output.replacements.count) replacement(s)")
            return output.text
        } catch {
            loadFailed = true
            LatencyLog.record("parakeet vocab boost unavailable (\(error)); transcript left unchanged")
            return nil
        }
    }

    // MARK: Model loading

    /// The rescorer for this dictionary, rebuilt only when the dictionary
    /// changes: it precomputes an index over the terms, which is wasted work to
    /// repeat on every dictation.
    private func preparedRescorer(
        for book: VocabularyBook,
        context: CustomVocabularyContext,
        spotter: CtcKeywordSpotter
    ) async throws -> VocabularyRescorer {
        let signature = Self.signature(of: book)
        if let rescorer, cachedSignature == signature { return rescorer }
        let built = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: context,
            config: Self.rescorerConfig,
            ctcModelDirectory: modelDirectory
        )
        rescorer = built
        cachedSignature = signature
        return built
    }

    /// Whether the CTC model is installed. Cheap and synchronous, so it can gate
    /// every dictation without cost.
    public static func isModelInstalled(at directory: URL) -> Bool {
        CtcModels.modelsExist(at: directory)
    }

    public var isModelInstalled: Bool {
        Self.isModelInstalled(at: modelDirectory)
    }

    /// Loads the spotter and tokenizer ahead of the first dictation that needs
    /// them, so `boost()`'s first real call isn't the one paying for it. Callers
    /// should only invoke this once `isModelInstalled` is true; best-effort, like
    /// `boost()` itself, since a boosting failure never affects dictation.
    public func prewarm() async {
        guard !loadFailed else { return }
        do {
            // Models first: the tokenizer's vocabulary file ships with them, so
            // loading it before them would fail on a fresh install.
            _ = try await loadedSpotter()
            _ = try await loadedTokenizer()
        } catch {
            loadFailed = true
            LatencyLog.record("parakeet vocab boost prewarm failed (\(error)); transcript left unchanged")
        }
    }

    /// Downloads the CTC model. Separate from `boost` on purpose: this is the
    /// slow, network-bound, user-visible step, and it belongs wherever the app
    /// can show progress and let the user decline, not inside a dictation.
    public func prepare() async throws {
        guard !isModelInstalled else { return }
        _ = try await CtcModels.download(to: modelDirectory)
        // A previous session's failure shouldn't outlive the missing model.
        loadFailed = false
    }

    private func loadedSpotter() async throws -> CtcKeywordSpotter {
        if let spotter { return spotter }
        let models = try await CtcModels.load(from: modelDirectory)
        // FluidAudio's CTC vocabulary excludes the blank symbol, so its count is
        // the blank's index.
        let built = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        spotter = built
        return built
    }

    private func loadedTokenizer() async throws -> CtcTokenizer {
        if let tokenizer { return tokenizer }
        let loaded = try await CtcTokenizer.load(from: modelDirectory)
        tokenizer = loaded
        return loaded
    }

    // MARK: Vocabulary

    /// Meander's dictionary as FluidAudio's context: correct spellings as terms,
    /// learned mistakes as aliases, both pre-tokenized for the CTC head (terms
    /// without token ids are silently skipped by the spotter, so tokenizing here
    /// is what makes an entry count at all).
    private func vocabularyContext(for book: VocabularyBook) async throws -> CustomVocabularyContext {
        let tokenizer = try await loadedTokenizer()
        let terms = book.entries.compactMap { entry -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(entry.term)
            guard !ids.isEmpty else { return nil }
            let aliases = Self.safeAliases(for: entry)
            return CustomVocabularyTerm(
                text: entry.term,
                aliases: aliases.isEmpty ? nil : aliases,
                ctcTokenIds: ids
            )
        }
        return CustomVocabularyContext(terms: terms)
    }

    /// Cheap identity for a dictionary, so the rescorer is rebuilt when terms or
    /// their learned mistakes change and reused when they haven't.
    private static func signature(of book: VocabularyBook) -> String {
        book.entries
            .map { "\($0.term)|\($0.aliases.joined(separator: ","))" }
            .joined(separator: ";")
    }
}
