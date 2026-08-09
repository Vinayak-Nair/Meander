import XCTest
@testable import DriftKit

final class VocabularyTests: XCTestCase {
    private func makeSettings() -> Settings {
        let suite = "drift-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Settings(defaults: defaults)
    }

    // MARK: Repairing dictionaries built by the old auto-learning rules

    func testPruneRemovesOrdinaryWordsAndKeepsNamesAndJargon() {
        let s = makeSettings()
        s.customVocabularyRaw = "Vinayak\ntaking\nUppekha\npresent\nBengaluru\nthe\nVercel\ndo it"
        let removed = s.pruneJunkFromVocabularyOnce()
        XCTAssertEqual(removed, ["taking", "present", "the", "do it"])
        XCTAssertEqual(s.customVocabulary, ["Vinayak", "Uppekha", "Bengaluru", "Vercel"])
    }

    /// Runs once so a user who deliberately re-adds a common word keeps it.
    func testPruneDoesNotRunTwice() {
        let s = makeSettings()
        s.customVocabularyRaw = "taking"
        XCTAssertEqual(s.pruneJunkFromVocabularyOnce(), ["taking"])

        s.customVocabularyRaw = "present"
        XCTAssertEqual(s.pruneJunkFromVocabularyOnce(), [])
        XCTAssertEqual(s.customVocabulary, ["present"])
    }

    /// Metadata for a pruned term goes with it, so re-adding the word by hand
    /// doesn't resurrect aliases learned in its previous life.
    func testPruneDropsLearnedMistakesForRemovedTerms() {
        let s = makeSettings()
        var book = VocabularyBook()
        book.note(term: "taking", misheardAs: "talking", source: "whisperKit")
        book.note(term: "Uppekha", misheardAs: "up a car", source: "whisperKit")
        s.vocabularyBook = book

        s.pruneJunkFromVocabularyOnce()
        XCTAssertEqual(s.vocabularyBook.terms, ["Uppekha"])
        XCTAssertNil(s.vocabularyBook.aliasIndex["talking"])
    }

    func testParseSplitsLinesAndCommas() {
        let terms = Vocabulary.parse("Karan Johar\nAishwarya Rai, Bengaluru")
        XCTAssertEqual(terms, ["Karan Johar", "Aishwarya Rai", "Bengaluru"])
    }

    func testParseTrimsAndDropsBlanks() {
        let terms = Vocabulary.parse("  Karan Johar  \n\n , \n Rai ")
        XCTAssertEqual(terms, ["Karan Johar", "Rai"])
    }

    func testParseDedupesCaseInsensitivelyKeepingFirst() {
        let terms = Vocabulary.parse("Karan Johar\nkaran johar\nRai")
        XCTAssertEqual(terms, ["Karan Johar", "Rai"])
    }

    func testWhisperPromptJoinsTermsAndCapsCount() {
        XCTAssertNil(Vocabulary.whisperPrompt(terms: []))
        XCTAssertEqual(
            Vocabulary.whisperPrompt(terms: ["Karan Johar", "Rai"]),
            "Karan Johar, Rai"
        )
        let many = (0..<100).map { "Term\($0)" }
        let prompt = Vocabulary.whisperPrompt(terms: many)!
        XCTAssertEqual(prompt.components(separatedBy: ", ").count, Vocabulary.maxWhisperTerms)
    }

    func testCleanupClauseListsTerms() {
        XCTAssertNil(Vocabulary.cleanupClause(terms: []))
        let clause = Vocabulary.cleanupClause(terms: ["Karan Johar", "Aishwarya Rai"])!
        XCTAssertTrue(clause.contains("Karan Johar, Aishwarya Rai"))
    }

    func testCleanupClauseCapsTermCount() {
        let many = (0..<200).map { "Term\($0)" }
        let clause = Vocabulary.cleanupClause(terms: many)!
        XCTAssertTrue(clause.contains("Term\(Vocabulary.maxCleanupTerms - 1)"))
        XCTAssertFalse(clause.contains("Term\(Vocabulary.maxCleanupTerms)"))
    }

    /// The on-device MLX provider builds its system prompt from this, so a
    /// dictionary term has to survive into it — the bug being guarded is the
    /// provider silently ignoring the dictionary entirely.
    func testEnhancementContractAppendsVocabulary() {
        let bare = EnhancementContract.systemPrompt(vocabulary: VocabularyBook())
        XCTAssertEqual(bare, EnhancementContract.systemPrompt)

        let book = VocabularyBook(terms: ["Karan Johar"], metadata: [])
        let withVocab = EnhancementContract.systemPrompt(vocabulary: book)
        XCTAssertTrue(withVocab.hasPrefix(EnhancementContract.systemPrompt))
        XCTAssertTrue(withVocab.contains("Karan Johar"))
    }

    func testSettingsParsesRawVocabulary() {
        let s = makeSettings()
        XCTAssertEqual(s.customVocabulary, [])
        s.customVocabularyRaw = "Karan Johar\nAishwarya Rai"
        XCTAssertEqual(s.customVocabulary, ["Karan Johar", "Aishwarya Rai"])
    }

    func testCleanupSystemPromptIncludesVocabulary() {
        let book = VocabularyBook(terms: ["Karan Johar"], metadata: [])
        let prompt = CleanupPrompt.system(for: .english, vocabulary: book)
        XCTAssertTrue(prompt.contains("Karan Johar"))
        let without = CleanupPrompt.system(for: .english)
        XCTAssertFalse(without.contains("often says"))
    }

    func testFactoryThreadsVocabularyIntoLLMProviders() {
        let s = makeSettings()
        s.customVocabularyRaw = "Karan Johar"
        s.cleanupProviderID = "openai"
        let openai = CleanupFactory.make(settings: s) as? OpenAICompatibleCleanup
        XCTAssertEqual(openai?.vocabulary.terms, ["Karan Johar"])
        s.cleanupProviderID = "ollama"
        let ollama = CleanupFactory.make(settings: s) as? OllamaCleanup
        XCTAssertEqual(ollama?.vocabulary.terms, ["Karan Johar"])
    }

    /// The factory has to hand providers the learned mistakes too, not just the
    /// term list, or the cleanup prompt loses the concrete "heard as" hints.
    func testFactoryThreadsLearnedMistakesIntoLLMProviders() {
        let s = makeSettings()
        var book = s.vocabularyBook
        book.note(term: "Karan Johar", misheardAs: "current johar", source: "whisperKit")
        s.vocabularyBook = book
        s.cleanupProviderID = "openai"
        let openai = CleanupFactory.make(settings: s) as? OpenAICompatibleCleanup
        XCTAssertEqual(openai?.vocabulary.entries.first?.aliases, ["current johar"])
    }
}
