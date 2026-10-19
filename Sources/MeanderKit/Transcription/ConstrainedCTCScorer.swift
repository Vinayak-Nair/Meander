import Foundation

/// Scores how well a candidate spelling explains a specific stretch of audio,
/// using CTC log-probabilities that have already been computed.
///
/// This is the acoustic half of "did the speaker say *log* or *lock*?". Given the
/// per-frame log-probabilities an auxiliary CTC head produced for the recording,
/// it answers a narrow question: over these frames, how likely is this exact
/// token sequence? Two candidate spellings scored over the *same* frames are
/// directly comparable, because the audio being explained is identical in both
/// cases. The difference between their scores is a log-likelihood ratio, which is
/// what a replacement decision can honestly be based on.
///
/// Deliberately free of any language model, spelling heuristic, or sentence
/// meaning: the only evidence used here is the recording.
///
/// One property to respect when choosing what to compare: the score is a raw
/// likelihood, so it is not length-neutral. A short token sequence can leave more
/// of the window to blanks, which CTC finds cheap, and so a one-token word scores
/// well above a two-token word over frames that plainly contain the longer one
/// (measured: "the" beat both "log" and "lock" by roughly eleven nats over frames
/// containing "log"). That is fine for the comparison this exists to make, where
/// rival spellings have parallel shapes, and it is why candidates that differ in
/// length should not be ranked against each other on this number alone.
///
/// The algorithm is the standard CTC forward pass over the blank-expanded symbol
/// sequence `[B, t1, B, t2, ..., tN, B]`, summing (not maximizing) over every
/// alignment, so the result is a true marginal likelihood rather than the score of
/// one best path. It is pure arithmetic over an array, which is what keeps it both
/// testable without models and far too cheap to matter for latency.
public enum ConstrainedCTCScorer {

    /// Natural-log likelihood that `tokens` account for frames `startFrame..<endFrame`.
    ///
    /// - Parameters:
    ///   - tokens: CTC token ids for the candidate spelling.
    ///   - logProbs: Per-frame log-probabilities `[frame][vocabulary]`, as produced
    ///     by the CTC head. Must already be log-softmaxed.
    ///   - blankId: Vocabulary index of the CTC blank symbol.
    ///   - startFrame: First frame of the window, inclusive.
    ///   - endFrame: Last frame of the window, exclusive.
    /// - Returns: The log-likelihood, or nil when the window is empty, the tokens
    ///   are out of range, or the window is too short to hold the sequence. A nil
    ///   means "no opinion", never "unlikely".
    public static func logLikelihood(
        tokens: [Int],
        logProbs: [[Float]],
        blankId: Int,
        startFrame: Int,
        endFrame: Int
    ) -> Double? {
        let start = max(0, startFrame)
        let end = min(logProbs.count, endFrame)
        guard start < end, !tokens.isEmpty else { return nil }

        let vocabularySize = logProbs[start].count
        guard blankId >= 0, blankId < vocabularySize else { return nil }
        guard tokens.allSatisfy({ $0 >= 0 && $0 < vocabularySize }) else { return nil }

        // Blank-expanded symbols: a blank may appear before, between, and after
        // tokens, and must appear between two identical neighbouring tokens.
        var symbols: [Int] = [blankId]
        symbols.reserveCapacity(2 * tokens.count + 1)
        for token in tokens {
            symbols.append(token)
            symbols.append(blankId)
        }
        let stateCount = symbols.count

        // Shortest path through the sequence: every token, plus a mandatory blank
        // wherever the same token repeats. A window below that cannot hold it.
        var minimumFrames = tokens.count
        for index in 1..<max(1, tokens.count) where tokens[index] == tokens[index - 1] {
            minimumFrames += 1
        }
        guard end - start >= minimumFrames else { return nil }

        var previous = [Double](repeating: -.infinity, count: stateCount)
        var current = [Double](repeating: -.infinity, count: stateCount)

        // The path may open on the leading blank or straight on the first token.
        previous[0] = Double(logProbs[start][symbols[0]])
        if stateCount > 1 {
            previous[1] = Double(logProbs[start][symbols[1]])
        }

        for frame in (start + 1)..<end {
            let row = logProbs[frame]
            for state in 0..<stateCount {
                // Stay where we are, or step forward one symbol.
                var total = logSumExp(previous[state], state > 0 ? previous[state - 1] : -.infinity)
                // Skipping the blank between two symbols is allowed only when they
                // differ; identical tokens must be separated by an emitted blank.
                if state >= 2, symbols[state] != blankId, symbols[state] != symbols[state - 2] {
                    total = logSumExp(total, previous[state - 2])
                }
                current[state] = total.isFinite ? total + Double(row[symbols[state]]) : -.infinity
            }
            swap(&previous, &current)
        }

        // A complete path ends on the final token or on the blank that follows it.
        let score = logSumExp(previous[stateCount - 1], stateCount > 1 ? previous[stateCount - 2] : -.infinity)
        return score.isFinite ? score : nil
    }

    /// Numerically stable `log(exp(a) + exp(b))`.
    private static func logSumExp(_ a: Double, _ b: Double) -> Double {
        if a == -.infinity { return b }
        if b == -.infinity { return a }
        let high = max(a, b)
        let low = min(a, b)
        return high + log1p(exp(low - high))
    }
}
