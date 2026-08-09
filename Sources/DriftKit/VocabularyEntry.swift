import Foundation

/// What Drift knows about one dictionary term beyond its spelling: the wrong
/// transcriptions it has actually been seen as, and which engine produced them.
///
/// The misheard forms are the valuable half. A term on its own only tells the
/// correction layers *what the right answer looks like*, so they have to guess
/// which spans might be a mangled version of it — that guess is a phonetic
/// threshold, and anything past it repeats forever. An alias tells them exactly
/// what the mistake looks like, which turns the guess into a lookup.
///
/// `sources` records the engine that produced each mistake. It is deliberately
/// *not* used to scope corrections: a mishearing is evidence about how the term
/// sounds, and every engine decoding the same audio is prone to a similar slip,
/// so aliases apply across backends. The tag is for diagnostics and for deciding
/// which backend needs decode-time biasing, not for gating.
public struct VocabularyEntry: Codable, Sendable, Equatable {
    /// The correct spelling, as the user wrote it.
    public var term: String
    /// Wrong transcriptions observed for this term, most recent last. Lowercased
    /// on insert, deduplicated.
    public var aliases: [String]
    /// Transcription backend ids that produced those mistakes (`TranscriptionBackend.rawValue`).
    public var sources: [String]

    public init(term: String, aliases: [String] = [], sources: [String] = []) {
        self.term = term
        self.aliases = aliases
        self.sources = sources
    }

    /// Records one observed mistake. No-ops on an alias that matches the term
    /// itself (a pure casing fix teaches the correction layers nothing).
    public mutating func note(misheardAs heard: String, source: String?) {
        let cleaned = heard.trimmingCharacters(in: .whitespaces).lowercased()
        if !cleaned.isEmpty, cleaned != term.lowercased(), !aliases.contains(cleaned) {
            aliases.append(cleaned)
        }
        if let source, !source.isEmpty, !sources.contains(source) {
            sources.append(source)
        }
    }
}

/// The dictionary as the correction layers see it: the user's terms, each with
/// whatever mistakes Drift has learned for it.
///
/// Term membership lives in `Settings.customVocabularyRaw` (the plain-text list
/// the settings editor round-trips); this store only adds metadata, keyed by
/// lowercased term. Keeping them separate means hand-editing the list can never
/// corrupt learned data, and a term deleted from the list drops its metadata on
/// the next read rather than lingering invisibly.
public struct VocabularyBook: Sendable, Equatable {
    public private(set) var entries: [VocabularyEntry]

    public init(entries: [VocabularyEntry] = []) {
        self.entries = entries
    }

    /// Builds the book for `terms`, carrying over metadata for terms that are
    /// still present and dropping the rest. Order follows `terms`, so the user's
    /// own ordering in the settings editor is preserved.
    public init(terms: [String], metadata: [VocabularyEntry]) {
        let byKey = Dictionary(
            metadata.map { ($0.term.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        entries = terms.map { term in
            guard var existing = byKey[term.lowercased()] else { return VocabularyEntry(term: term) }
            // The user's current spelling wins: they may have recased the term
            // in the editor since it was learned.
            existing.term = term
            return existing
        }
    }

    public var terms: [String] { entries.map(\.term) }

    public var isEmpty: Bool { entries.isEmpty }

    /// Every known misheard form, mapped to the term it should become. Used by
    /// the deterministic corrector for exact-match repair.
    public var aliasIndex: [String: String] {
        var index: [String: String] = [:]
        for entry in entries {
            for alias in entry.aliases where index[alias] == nil {
                index[alias] = entry.term
            }
        }
        return index
    }

    /// Records a mistake against `term`, adding the term if it is new.
    public mutating func note(term: String, misheardAs heard: String?, source: String?) {
        let key = term.lowercased()
        if let index = entries.firstIndex(where: { $0.term.lowercased() == key }) {
            entries[index].term = term
            if let heard { entries[index].note(misheardAs: heard, source: source) }
        } else {
            var entry = VocabularyEntry(term: term)
            if let heard { entry.note(misheardAs: heard, source: source) }
            entries.append(entry)
        }
    }

    public mutating func remove(term: String) {
        let key = term.lowercased()
        entries.removeAll { $0.term.lowercased() == key }
    }
}
