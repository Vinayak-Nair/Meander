import Foundation

/// Turns a spoken clock time into the way people write one: "three pm" becomes
/// "3pm", "three thirty p.m." becomes "3:30pm".
///
/// Two things go wrong without this. Transcribers spell the hour out, so a
/// perfectly heard "3pm" arrives as "three pm" and has to be fixed by hand every
/// time. And the hour is the single most misheard word in a short utterance,
/// because it is one unstressed syllable carrying all the meaning: Parakeet
/// returned "Tree pm works for me" for "3pm works for me".
///
/// The meridiem is what makes repairing that safe. "Tree" on its own is a word
/// the speaker might well have said, and nothing here would touch it; "tree"
/// immediately before "pm" is not a phrase English produces. So the rewrite is
/// scoped to the position where the reading is unambiguous, rather than being a
/// blanket word swap of the kind that made the personal dictionary unusable.
enum SpokenTime {
    /// Hour words, including the mishearings worth repairing in this position.
    ///
    /// Deliberately absent: "to" -> 2 and "for" -> 4. They are the same kind of
    /// slip, but unlike "tree" they have ordinary readings right before those
    /// letters ("I sent it to PM", "for PM approval"), and rewriting a sentence
    /// the model got right is the worse failure. A user who hits them often can
    /// still fix them once and have it learned.
    private static let hours: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        // Observed transcriber slips for "three", which has no competing reading
        // in front of a meridiem.
        "tree": 3, "free": 3, "thee": 3,
    ]

    /// Minute words common enough in speech to be worth spelling out. Anything
    /// else stays as the transcriber wrote it.
    private static let minutes: [String: Int] = [
        "o'clock": 0, "oclock": 0, "clock": 0,
        "fifteen": 15, "thirty": 30, "forty five": 45, "fortyfive": 45, "forty-five": 45,
    ]

    private static let pattern: NSRegularExpression? = {
        let hourWords = hours.keys.map { NSRegularExpression.escapedPattern(for: $0) }
            .sorted { $0.count > $1.count }.joined(separator: "|")
        let minuteWords = minutes.keys.map { NSRegularExpression.escapedPattern(for: $0) }
            .sorted { $0.count > $1.count }.joined(separator: "|")
        // hour, then either ":MM" or a spelled-out minute, then the meridiem.
        return try? NSRegularExpression(
            pattern: "\\b(\(hourWords)|\\d{1,2})(?:\\s*:\\s*([0-5]\\d)|\\s+(\(minuteWords)))?\\s*([ap])\\.?\\s?m\\.?(?![\\p{L}])",
            options: [.caseInsensitive]
        )
    }()

    /// Rewrites every spoken time in `text`. Anything that doesn't parse as a
    /// real clock time (a 13 o'clock, a stray "5 am" inside a larger number) is
    /// left exactly as it was.
    static func format(_ text: String) -> String {
        guard let pattern, !text.isEmpty else { return text }
        let full = NSRange(text.startIndex..., in: text)
        var result = text

        // Right to left so earlier match ranges stay valid as we substitute.
        for match in pattern.matches(in: text, range: full).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            guard let replacement = rendered(match: match, in: text) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private static func rendered(match: NSTextCheckingResult, in text: String) -> String? {
        func group(_ index: Int) -> String? {
            guard let r = Range(match.range(at: index), in: text) else { return nil }
            return String(text[r]).lowercased()
        }
        guard let rawHour = group(1), let meridiem = group(4) else { return nil }

        let hour = hours[rawHour] ?? Int(rawHour).map { $0 }
        // A 24-hour reading ("15 pm") isn't a time anyone says; leave it alone
        // rather than guess at what was meant.
        guard let hour, (1...12).contains(hour) else { return nil }

        var minute = 0
        if let digits = group(2), let value = Int(digits) {
            minute = value
        } else if let word = group(3) {
            guard let value = minutes[word.replacingOccurrences(of: "-", with: " ")] else { return nil }
            minute = value
        }

        let suffix = meridiem == "a" ? "am" : "pm"
        return minute == 0 ? "\(hour)\(suffix)" : "\(hour):\(String(format: "%02d", minute))\(suffix)"
    }
}
