import XCTest
@testable import MeanderKit

final class DictionaryLearnerTests: XCTestCase {
    func testLearnsCorrectedName() {
        let pasted = "I met current johar yesterday"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: "Notes so far.\n\(pasted)",
            after: "Notes so far.\nI met Karan Johar yesterday",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), ["Karan Johar"])
    }

    func testLearnsSeverelyMangledCorrection() {
        // The case the deterministic corrector deliberately skips: the user
        // demonstrating the fix is strong enough evidence to learn from.
        let pasted = "I should have a run is my favorite actress"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "Aishwarya Rai is my favorite actress",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), ["Aishwarya Rai"])
    }

    func testLearnsCasingFix() {
        let pasted = "meeting with vinayak tomorrow"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "meeting with Vinayak tomorrow",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), ["Vinayak"])
    }

    func testLearnsLowercaseSoundAlikeFix() {
        let pasted = "we deployed to versal last night"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "we deployed to Vercel last night",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), ["Vercel"])
    }

    /// The rule that keeps the dictionary from degrading dictation over time.
    ///
    /// "hat" -> "hair" is a perfectly plausible mishear fix, and learning it is
    /// still wrong: `VocabularyCorrector` matches on sound, so "hair" in the
    /// dictionary rewrites every word that sounds like it ("her", "here", "hare")
    /// for as long as it stays there. The user might genuinely have said any of
    /// those. Ordinary English is therefore never learned on its own, and a user
    /// who really wants it can add it in Settings by hand.
    func testDoesNotLearnOrdinaryEnglishWords() {
        let pasted = "she cut her hat short"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "she cut her hair short",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    /// The observed failure this rule exists for: a dictation into a chat box
    /// followed by ordinary typing looks exactly like a correction, and the words
    /// it produced ("taking", "present", "connect") went on to rewrite every
    /// transcript that rhymed with them.
    func testDoesNotLearnFromOrdinaryTypingAfterDictation() {
        let pasted = "can you review the doc"
        for after in ["can you review the document", "can you present the doc", "can you review the code"] {
            let terms = DictionaryLearner.newTerms(
                pasted: pasted, before: pasted, after: after, vocabulary: []
            )
            XCTAssertEqual(terms.map(\.term), [], "learned from \"\(after)\"")
        }
    }

    /// The shared bar, checked directly: `Settings.pruneJunkFromVocabularyOnce`
    /// holds stored terms to it, so these cases are also what gets cleaned out of
    /// a dictionary built under the old rules.
    func testAcceptableTermRejectsWhatIsNotATerm() {
        for junk in [
            "the", "taking", "do it",                  // ordinary English
            "us toAre they best.",                     // a captured sentence
            "Users/vinayaknair/Documents/index.html",  // a path
            "rank(YC",                                 // stray code punctuation
            "add 1 Sharique Shamsudeen",               // a typed digit
            "fil o",                                   // half-typed word
            "a b",                                     // fragments
        ] {
            XCTAssertFalse(DictionaryLearner.isAcceptableTerm(junk), "accepted \"\(junk)\"")
        }
    }

    /// Product names capitalize mid-token exactly the way an editing slip does
    /// ("ChatGPT" reads like "toAre"), so the bar must not use that as a tell.
    /// These are the names the dictionary exists for.
    func testAcceptableTermKeepsNamesAndJargon() {
        for term in [
            "Vinayak", "Uppekha", "Bengaluru", "Vercel", "Replit", "CRM", "CRED",
            "termux", "Anoop Ambika", "ChatGPT", "iPhone", "GPT-4",
        ] {
            XCTAssertTrue(DictionaryLearner.isAcceptableTerm(term), "rejected \"\(term)\"")
        }
    }

    func testDoesNotLearnPathsOrCodeFragments() {
        let pasted = "open the index file"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "open the ~/Documents/app/public/index.html file",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    func testIgnoresContentRewrites() {
        // "noon" -> "night" sounds nothing alike beyond a shared consonant,
        // so it's a content edit, not a mishear fix, and must not be learned.
        let pasted = "the meeting is at noon"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "the meeting is at night",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    func testIgnoresEditsOutsideDictatedRegionEvenWithSharedWords() {
        // "well" appears in the dictation too, but the user edited the copy of
        // it in their own earlier text; nothing may be learned from that.
        let terms = DictionaryLearner.newTerms(
            pasted: "the demo went well",
            before: "well done team. the demo went well",
            after: "Wexil done team. the demo went well",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    func testLearnsSameWordWhenCorrectedInsideDictatedRegion() {
        let terms = DictionaryLearner.newTerms(
            pasted: "the demo went well",
            before: "well done team. the demo went well",
            after: "well done team. the demo went Wexil",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), ["Wexil"])
    }

    func testIgnoresEditsOutsidePastedText() {
        let terms = DictionaryLearner.newTerms(
            pasted: "and the demo went well",
            before: "kiran presented today. and the demo went well",
            after: "Kiran presented today. and the demo went well",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    func testIgnoresAlreadyKnownTerms() {
        let pasted = "call current johar"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "call Karan Johar",
            vocabulary: ["Karan Johar"]
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    func testIgnoresPureInsertionsAndDeletions() {
        let pasted = "send the report"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "send the report to Priya please",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), [])
    }

    func testLearnsMultipleCorrections() {
        let pasted = "current johar and ash rai"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "Karan Johar and Aishwarya Rai",
            vocabulary: []
        )
        XCTAssertEqual(terms.map(\.term), ["Karan Johar", "Aishwarya Rai"])
    }

    func testNoChangeLearnsNothing() {
        let pasted = "hello there"
        XCTAssertEqual(
            DictionaryLearner.newTerms(pasted: pasted, before: pasted, after: pasted, vocabulary: []).map(\.term),
            []
        )
    }

    // MARK: Misheard forms

    func testCapturesWhatTheModelActuallyProduced() {
        let pasted = "I met current johar yesterday"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "I met Karan Johar yesterday",
            vocabulary: []
        )
        XCTAssertEqual(terms, [.init(term: "Karan Johar", misheardAs: "current johar")])
    }

    /// The mangled case is exactly the one the phonetic corrector cannot reach,
    /// so capturing the wrong form verbatim is what makes it fixable next time.
    func testCapturesSeverelyMangledMisheardForm() {
        let pasted = "I should have a run is my favorite actress"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "Aishwarya Rai is my favorite actress",
            vocabulary: []
        )
        XCTAssertEqual(terms.first?.misheardAs, "I should have a run")
    }

    func testMisheardFormDropsSurroundingPunctuation() {
        let pasted = "call current johar, please"
        let terms = DictionaryLearner.newTerms(
            pasted: pasted,
            before: pasted,
            after: "call Karan Johar, please",
            vocabulary: []
        )
        XCTAssertEqual(terms.first?.misheardAs, "current johar")
    }
}
