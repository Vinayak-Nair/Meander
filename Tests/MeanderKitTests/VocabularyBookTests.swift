import XCTest
@testable import MeanderKit

final class VocabularyBookTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "meander-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeSettings() -> Settings {
        Settings(defaults: makeDefaults())
    }

    // MARK: Recording mistakes

    func testNoteRecordsMisheardFormAndSource() {
        var book = VocabularyBook()
        book.note(term: "Karan Johar", misheardAs: "current johar", source: "whisperKit")
        XCTAssertEqual(book.terms, ["Karan Johar"])
        XCTAssertEqual(book.entries.first?.aliases, ["current johar"])
        XCTAssertEqual(book.entries.first?.sources, ["whisperKit"])
    }

    func testNoteAccumulatesDistinctMistakesForOneTerm() {
        var book = VocabularyBook()
        book.note(term: "Karan Johar", misheardAs: "current johar", source: "whisperKit")
        book.note(term: "Karan Johar", misheardAs: "Karen Joha", source: "fluidAudioParakeet")
        book.note(term: "Karan Johar", misheardAs: "current johar", source: "whisperKit")
        XCTAssertEqual(book.entries.count, 1)
        XCTAssertEqual(book.entries.first?.aliases, ["current johar", "karen joha"])
        XCTAssertEqual(book.entries.first?.sources, ["whisperKit", "fluidAudioParakeet"])
    }

    /// A casing-only fix teaches the correction layers nothing they can match on,
    /// so it must not become an alias that maps a term onto itself.
    func testNoteIgnoresAliasEqualToTerm() {
        var book = VocabularyBook()
        book.note(term: "Vinayak", misheardAs: "vinayak", source: "whisperKit")
        XCTAssertEqual(book.entries.first?.aliases, [])
    }

    // MARK: Reconciliation against the user's list

    func testInitCarriesMetadataForSurvivingTermsAndDropsTheRest() {
        let metadata = [
            VocabularyEntry(term: "Karan Johar", aliases: ["current johar"], sources: ["whisperKit"]),
            VocabularyEntry(term: "Deleted Term", aliases: ["deleted"], sources: ["whisperKit"]),
        ]
        let book = VocabularyBook(terms: ["Karan Johar", "Bengaluru"], metadata: metadata)
        XCTAssertEqual(book.terms, ["Karan Johar", "Bengaluru"])
        XCTAssertEqual(book.entries[0].aliases, ["current johar"])
        XCTAssertEqual(book.entries[1].aliases, [])
    }

    /// Hand-editing the list is how a user recases a term; their spelling has to
    /// win without discarding what was learned under the old casing.
    func testInitPrefersUserSpellingOverStoredCasing() {
        let metadata = [VocabularyEntry(term: "karan johar", aliases: ["current johar"], sources: [])]
        let book = VocabularyBook(terms: ["Karan Johar"], metadata: metadata)
        XCTAssertEqual(book.entries.first?.term, "Karan Johar")
        XCTAssertEqual(book.entries.first?.aliases, ["current johar"])
    }

    func testAliasIndexMapsMistakesToTerms() {
        let book = VocabularyBook(
            terms: ["Karan Johar"],
            metadata: [VocabularyEntry(term: "Karan Johar", aliases: ["current johar"], sources: [])]
        )
        XCTAssertEqual(book.aliasIndex, ["current johar": "Karan Johar"])
    }

    // MARK: Persistence

    func testSettingsRoundTripsBookAcrossTermsAndMetadata() {
        let s = makeSettings()
        var book = s.vocabularyBook
        book.note(term: "Karan Johar", misheardAs: "current johar", source: "fluidAudioParakeet")
        s.vocabularyBook = book

        XCTAssertEqual(s.customVocabulary, ["Karan Johar"])
        XCTAssertEqual(s.vocabularyBook.entries.first?.aliases, ["current johar"])
        XCTAssertEqual(s.vocabularyBook.entries.first?.sources, ["fluidAudioParakeet"])
    }

    /// Deleting a term in the settings editor must take its learned data with it,
    /// rather than leaving metadata that silently reappears if the term is retyped.
    func testRemovingTermFromRawListDropsItsMetadata() {
        let s = makeSettings()
        var book = s.vocabularyBook
        book.note(term: "Karan Johar", misheardAs: "current johar", source: "whisperKit")
        s.vocabularyBook = book

        s.customVocabularyRaw = ""
        XCTAssertTrue(s.vocabularyBook.isEmpty)

        s.customVocabularyRaw = "Karan Johar"
        XCTAssertEqual(s.vocabularyBook.entries.first?.aliases, [])
    }

    func testCorruptMetadataDegradesToPlainTermList() {
        let defaults = makeDefaults()
        let s = Settings(defaults: defaults)
        s.customVocabularyRaw = "Karan Johar"
        defaults.set(Data("not json".utf8), forKey: "vocabularyMetadata")
        XCTAssertEqual(s.vocabularyBook.terms, ["Karan Johar"])
        XCTAssertEqual(s.vocabularyBook.entries.first?.aliases, [])
    }

    // MARK: Prompt surfaces

    func testCleanupClauseNamesLearnedMistakes() {
        let book = VocabularyBook(
            terms: ["Karan Johar"],
            metadata: [VocabularyEntry(term: "Karan Johar", aliases: ["current johar"], sources: [])]
        )
        let clause = Vocabulary.cleanupClause(book: book)!
        XCTAssertTrue(clause.contains("Karan Johar"))
        XCTAssertTrue(clause.contains("current johar"))
    }

    func testCleanupClauseOmitsHintForTermsWithoutMistakes() {
        let book = VocabularyBook(terms: ["Bengaluru"], metadata: [])
        let clause = Vocabulary.cleanupClause(book: book)!
        XCTAssertTrue(clause.contains("Bengaluru"))
        XCTAssertFalse(clause.contains("transcribed as"))
    }

    func testCleanupClauseCapsAliasesPerTerm() {
        let many = (0..<10).map { "wrong\($0)" }
        let book = VocabularyBook(
            terms: ["Term"],
            metadata: [VocabularyEntry(term: "Term", aliases: many, sources: [])]
        )
        let clause = Vocabulary.cleanupClause(book: book)!
        let quoted = many.filter { clause.contains($0) }
        XCTAssertEqual(quoted.count, Vocabulary.maxAliasesPerTerm)
    }

    /// Whisper's prompt biases decoding toward the text it contains, so putting a
    /// misheard form in it would push the model toward producing the mistake.
    func testWhisperPromptNeverContainsMisheardForms() {
        let book = VocabularyBook(
            terms: ["Karan Johar"],
            metadata: [VocabularyEntry(term: "Karan Johar", aliases: ["current johar"], sources: [])]
        )
        let prompt = Vocabulary.whisperPrompt(terms: book.terms)!
        XCTAssertEqual(prompt, "Karan Johar")
        XCTAssertFalse(prompt.contains("current johar"))
    }
}
