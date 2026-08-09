import Foundation

/// Assembles spoken email addresses and domains: "vinayak at gmail dot com"
/// becomes "vinayak@gmail.com", "vinayakvnair dot com" becomes
/// "vinayakvnair.com".
///
/// Transcribers write what they hear, so an address always arrives as prose. No
/// amount of acoustic accuracy fixes that on its own, which is why this is
/// formatting rather than transcription.
///
/// The trailing "dot <tld>" is what licenses the whole rewrite. Without it, "at"
/// is one of the most common words in English and joining across it would wreck
/// ordinary sentences; with it, the span is an address and the reading is not in
/// doubt. Everything is anchored on finding that ending first and working
/// outwards.
enum SpokenAddress {
    /// Endings that make a span an address rather than a sentence. Kept short and
    /// common on purpose: a longer list buys little and every entry is another
    /// chance to swallow real prose.
    private static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "co", "edu", "gov", "dev", "app", "ai", "in", "me",
    ]

    /// The most words that can be pulled in front of "at" as the local part. An
    /// address is spoken as a short run of name-like words; a longer reach starts
    /// eating the sentence that introduced it.
    private static let maxLocalWords = 3

    static func format(_ text: String) -> String {
        guard text.contains(" ") else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var changed = false

        // Right to left: rewriting shortens the array, and a later address must
        // not shift the indices of an earlier one.
        var index = words.count - 1
        while index >= 1 {
            defer { index -= 1 }
            guard isDot(words[index - 1]), let tld = topLevelDomain(words[index]) else { continue }
            guard let span = addressSpan(in: words, dotAt: index - 1) else { continue }
            words.replaceSubrange(span.range, with: [span.rendered(tld: tld, trailing: trailing(words[index]))])
            index = span.range.lowerBound
            changed = true
        }
        return changed ? words.joined(separator: " ") : text
    }

    // MARK: Span resolution

    private struct Address {
        let range: Range<Int>
        let local: String?
        let domain: String

        func rendered(tld: String, trailing: String) -> String {
            let host = "\(domain).\(tld)\(trailing)"
            guard let local, !local.isEmpty else { return host }
            return "\(local)@\(host)"
        }
    }

    /// The full span of the address ending at `dotIndex`, or nil when what
    /// precedes the dot doesn't read as one.
    private static func addressSpan(in words: [String], dotAt dotIndex: Int) -> Address? {
        guard dotIndex >= 1 else { return nil }

        // With an "at" in reach, everything between it and the dot is the domain,
        // spaces and all: "at vinayak v nair dot com" is one host spelled aloud.
        if let atIndex = indexOfAt(in: words, before: dotIndex) {
            let domain = glued(words[(atIndex + 1)..<dotIndex])
            guard !domain.isEmpty else { return nil }
            let localStart = localPartStart(in: words, before: atIndex)
            // The local part keeps the casing the speaker used; hosts are
            // conventionally lower case and case-insensitive anyway.
            let local = glued(words[localStart..<atIndex], lowercased: false)
            // No name-like words in front of "at" means this is a sentence that
            // happens to mention a domain ("email me at meander.com"), so the "at"
            // stays a word and only the host is assembled.
            guard !local.isEmpty else {
                return Address(range: (atIndex + 1)..<(dotIndex + 2), local: nil, domain: domain)
            }
            return Address(range: localStart..<(dotIndex + 2), local: local, domain: domain)
        }

        // No "at": just a bare domain, and only the single word before the dot
        // belongs to it.
        let domain = glued(words[(dotIndex - 1)..<dotIndex])
        guard !domain.isEmpty else { return nil }
        return Address(range: (dotIndex - 1)..<(dotIndex + 2), local: nil, domain: domain)
    }

    /// The nearest "at" close enough in front of the dot to be part of the same
    /// address. Every word between the two has to be address-shaped, which is
    /// what stops "at" in a sentence from reaching across to a later domain.
    private static func indexOfAt(in words: [String], before dotIndex: Int) -> Int? {
        var index = dotIndex - 1
        while index >= 0, dotIndex - index <= maxLocalWords + 1 {
            if normalized(words[index]) == "at" { return index }
            guard isAddressWord(words[index]) else { return nil }
            index -= 1
        }
        return nil
    }

    /// How far back the local part runs. It stops at the first everyday function
    /// word, so the sentence that introduced the address ("this is Vinayak at
    /// ...") is not swallowed into it, while a multi-word name still is.
    ///
    /// Deliberately `isFrequentWord` and not `isOrdinary`: plenty of local parts
    /// are real words ("hello@", "info@", "support@"), and plenty of surnames are
    /// in the system word list, so the broader test would refuse most addresses.
    private static func localPartStart(in words: [String], before atIndex: Int) -> Int {
        var start = atIndex
        while start > 0, atIndex - start < maxLocalWords {
            let candidate = words[start - 1]
            guard isAddressWord(candidate), !CommonWords.isFrequentWord(candidate) else { break }
            start -= 1
        }
        return start
    }

    // MARK: Word tests

    /// Whether a word can sit inside an address: letters and digits only, with no
    /// punctuation that would mean the sentence has moved on.
    private static func isAddressWord(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static func isDot(_ word: String) -> Bool {
        ["dot", "."].contains(normalized(word))
    }

    /// The TLD in a word that may carry trailing punctuation ("com." at the end
    /// of a sentence), or nil when it isn't one.
    private static func topLevelDomain(_ word: String) -> String? {
        let core = normalized(word)
        return topLevelDomains.contains(core) ? core : nil
    }

    /// Punctuation the TLD word carried, put back after the assembled address so
    /// a sentence still ends.
    private static func trailing(_ word: String) -> String {
        String(word.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
    }

    private static func glued(_ words: ArraySlice<String>, lowercased: Bool = true) -> String {
        words.map { lowercased ? normalized($0) : stripped($0) }.joined()
    }

    private static func normalized(_ word: String) -> String {
        stripped(word).lowercased()
    }

    private static func stripped(_ word: String) -> String {
        word.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
