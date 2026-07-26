import Foundation

/// The outcome of running one `ContractCase` through one cleanup provider.
struct CaseResult {
    let caseName: String
    let rule: String
    let input: String
    let output: String
    /// Human-readable descriptions of every check that failed (empty == passed).
    let failures: [String]
    /// Wall-clock time for the cleanup call (median of the timed runs).
    let latencyMs: Double

    var passed: Bool { failures.isEmpty }
}

/// Applies a `ContractCase`'s checks to a produced output and returns the list
/// of failures. Checks encode each contract rule's *guarantee* (substring
/// presence/absence, length bounds), not one exact expected string, so a model
/// that phrases things differently still passes when it honors the contract.
enum ContractChecker {
    static func failures(for c: ContractCase, output: String) -> [String] {
        var failures: [String] = []
        let lowerOutput = output.lowercased()

        for term in c.mustNotContain where lowerOutput.contains(term.lowercased()) {
            failures.append("still contains \"\(term)\"")
        }
        for term in c.mustContain where !output.contains(term) {
            failures.append("dropped \"\(term)\"")
        }
        if c.mustEndWithPunctuation {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = trimmed.last, !".?!".contains(last) {
                failures.append("does not end in sentence punctuation")
            } else if trimmed.isEmpty {
                failures.append("empty output")
            }
        }
        if c.mustContainNewline, !output.contains("\n") {
            failures.append("missing paragraph break")
        }
        let words = wordCount(output)
        if let maxWords = c.maxWords, words > maxWords {
            failures.append("too long: \(words) words (max \(maxWords))")
        }
        if let minWords = c.minWords, words < minWords {
            failures.append("too short: \(words) words (min \(minWords)) — possible summarizing")
        }
        return failures
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
