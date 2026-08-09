import Foundation

/// The executable form of Meander's enhancement contract: one case per contract
/// bullet, with checks robust to an LLM's phrasing (substring presence/absence
/// and length bounds rather than brittle exact-match). The step-3 runner feeds
/// each `input` through a cleanup provider and asserts the checks hold.
///
/// Checks are intentionally conservative — they encode the *guarantee* of each
/// rule, not one specific correct output, so a small model that phrases things
/// slightly differently still passes as long as it honors the contract.
struct ContractCase {
    let name: String
    /// Which contract bullet this exercises (for readable failure output).
    let rule: String
    let input: String
    /// Substrings that must be GONE from the output (case-insensitive).
    var mustNotContain: [String] = []
    /// Substrings that must SURVIVE in the output (case-sensitive, so it also
    /// checks capitalization and exact preservation of names/numbers).
    var mustContain: [String] = []
    /// Output must end in sentence punctuation ("." / "?" / "!").
    var mustEndWithPunctuation = false
    /// Output must contain a line break (spoken "new paragraph").
    var mustContainNewline = false
    /// Guards "don't turn short messages into essays" / "don't expand".
    var maxWords: Int? = nil
    /// Guards "don't summarize" — output must keep at least this many words.
    var minWords: Int? = nil
}

enum EnhancementContractCases {
    static let all: [ContractCase] = mayCases + mustNotCases

    // MARK: What Meander MAY do

    static let mayCases: [ContractCase] = [
        ContractCase(
            name: "removes-um-uh", rule: "remove speech fillers",
            input: "um so I uh went to the store",
            mustNotContain: ["um", "uh"], mustContain: ["store"]
        ),
        ContractCase(
            name: "removes-you-know", rule: "remove speech fillers",
            input: "this is you know pretty solid work",
            mustNotContain: ["you know"], mustContain: ["pretty solid work"]
        ),
        ContractCase(
            name: "removes-filler-like", rule: "remove 'like' as filler",
            input: "it was like really far from the station",
            mustNotContain: ["like"], mustContain: ["really far"]
        ),
        ContractCase(
            name: "keeps-real-like", rule: "preserve 'like' when not filler",
            input: "I really like this song",
            mustContain: ["like", "song"]
        ),
        ContractCase(
            name: "removes-doubled-word", rule: "remove accidental repetitions",
            input: "send the the document",
            mustNotContain: ["the the"], mustContain: ["document"]
        ),
        ContractCase(
            name: "removes-repeated-phrase", rule: "remove accidental repetitions",
            input: "I think I think we should go",
            mustNotContain: ["I think I think"], mustContain: ["we should go"]
        ),
        ContractCase(
            name: "repairs-false-start", rule: "repair false starts",
            input: "Can you, actually, could you send it tomorrow?",
            mustNotContain: ["can you, actually"], mustContain: ["tomorrow"]
        ),
        ContractCase(
            name: "adds-punctuation", rule: "add punctuation",
            input: "hello how are you doing today",
            mustEndWithPunctuation: true
        ),
        ContractCase(
            name: "capitalizes-sentences", rule: "capitalize sentences",
            input: "hello there. how are you",
            mustContain: ["How"]
        ),
        ContractCase(
            name: "capitalizes-proper-nouns", rule: "capitalize proper nouns",
            input: "i talked to sarah about the london trip",
            mustContain: ["Sarah", "London"]
        ),
        ContractCase(
            name: "light-grammar", rule: "make light grammatical corrections",
            input: "he go to the office every day",
            mustContain: ["goes"]
        ),
        ContractCase(
            name: "normalizes-spacing", rule: "normalize spacing",
            input: "hello    world   there",
            mustNotContain: ["  "]
        ),
        ContractCase(
            name: "spoken-comma", rule: "convert spoken punctuation",
            input: "wait comma what did you say",
            mustNotContain: ["comma"], mustContain: [","]
        ),
        ContractCase(
            name: "spoken-full-stop", rule: "convert spoken punctuation",
            input: "that is all full stop",
            mustNotContain: ["full stop"], mustContain: ["."]
        ),
        ContractCase(
            name: "spoken-new-paragraph", rule: "convert spoken punctuation",
            input: "first idea new paragraph second idea",
            mustNotContain: ["new paragraph"], mustContainNewline: true
        ),
        ContractCase(
            name: "preserves-tone", rule: "preserve the user's tone and vocabulary",
            input: "yeah that's gonna be super cool",
            mustContain: ["gonna", "cool"]
        ),
    ]

    // MARK: What Meander MUST NOT do

    static let mustNotCases: [ContractCase] = [
        ContractCase(
            name: "no-summarize", rule: "must not summarize",
            input: "we should ship the feature next week but I am worried about the tests and we still need to tell the customer",
            mustContain: ["tests", "customer"], minWords: 18
        ),
        ContractCase(
            name: "no-add-info", rule: "must not add new information",
            input: "send the report to the team",
            mustContain: ["report", "team"], maxWords: 8
        ),
        ContractCase(
            name: "no-formalize", rule: "must not make the writing more formal",
            input: "I wanna grab lunch soon",
            mustNotContain: ["would like to"], mustContain: ["wanna", "lunch"]
        ),
        ContractCase(
            name: "no-elevate-vocab", rule: "must not replace simple words with sophisticated ones",
            input: "the food was good",
            mustNotContain: ["excellent", "superb", "delightful", "exquisite"],
            mustContain: ["good"]
        ),
        ContractCase(
            name: "no-change-opinion", rule: "must not change the user's opinion",
            input: "I think the new design is bad",
            mustNotContain: ["good", "great", "nice"], mustContain: ["bad"]
        ),
        ContractCase(
            name: "keeps-hedging", rule: "must not remove uncertainty or hedging",
            input: "I think maybe we should wait a bit",
            mustContain: ["maybe", "think"]
        ),
        ContractCase(
            name: "keeps-numbers-dates-names", rule: "must not change numbers, dates or names",
            input: "meet Raj at 3 pm on the 5th",
            mustContain: ["Raj", "3", "5th"]
        ),
        ContractCase(
            name: "no-essay", rule: "must not turn short messages into essays",
            input: "ok sounds good",
            maxWords: 5
        ),
        ContractCase(
            name: "no-restructure", rule: "must not restructure entire paragraphs",
            input: "the build is broken. I will fix it after lunch",
            mustContain: ["broken", "lunch"]
        ),
        ContractCase(
            name: "no-censor-profanity", rule: "must not censor informal language or profanity",
            input: "this is fucking brilliant work",
            mustContain: ["fucking", "brilliant"]
        ),
    ]
}
