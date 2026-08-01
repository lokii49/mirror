import Foundation
import NaturalLanguage

enum ThemeNodeType: String, Codable, Sendable {
    case person
    case place
    case keyword
    /// Reserved for a future on-device LLM pass that extracts abstract themes.
    case theme
}

struct ExtractedTerm: Hashable, Sendable {
    /// Normalized identity: lowercased, diacritic-folded, trimmed.
    let key: String
    /// Display form as first seen in the entry (e.g. "Priya").
    let label: String
    let type: ThemeNodeType

    // Identity is the normalized key + type; label is presentation only,
    // so "Mom" and "mom" collapse to one term within an entry.
    static func == (lhs: ExtractedTerm, rhs: ExtractedTerm) -> Bool {
        lhs.key == rhs.key && lhs.type == rhs.type
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(type)
    }
}

/// Sendable snapshot taken on the main actor — @Model Entry must never cross actors.
struct EntryTextSnapshot: Sendable, Identifiable {
    let id: UUID
    /// Hash of the entry's ciphertext blobs. Ciphertext only changes when
    /// content is rewritten, so it detects edits without decrypting.
    let fingerprint: Int
    /// entry.insightContext, clipped.
    let text: String
    let moodScore: Double?
    let createdAt: Date
    /// True when the entry's ciphertext couldn't be decrypted (e.g. Keychain not
    /// yet readable) — `text` is `""` in that case, indistinguishable from a
    /// genuinely empty entry without this flag.
    let decryptionFailed: Bool
}

actor ThemeExtractionService {
    static let shared = ThemeExtractionService()

    static let maxTextLength = 4000

    private var cache: [UUID: (fingerprint: Int, terms: Set<ExtractedTerm>)] = [:]

    func termsBatch(for snapshots: [EntryTextSnapshot]) -> [UUID: Set<ExtractedTerm>] {
        var result: [UUID: Set<ExtractedTerm>] = [:]
        result.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            result[snapshot.id] = terms(for: snapshot)
        }
        return result
    }

    func terms(for snapshot: EntryTextSnapshot) -> Set<ExtractedTerm> {
        if let cached = cache[snapshot.id], cached.fingerprint == snapshot.fingerprint {
            return cached.terms
        }
        let terms = Self.extract(from: snapshot.text)
        // Below extract's own floor (see minTextLength) is indistinguishable here
        // from "decryption isn't ready yet" — text is legitimately short either
        // way. Ciphertext-based fingerprints don't change once decryption starts
        // working, so caching an empty result under a transiently-unreadable
        // entry would pin it wrong for the rest of the process. Skipping the
        // cache costs nothing: `extract` exits at its own guard immediately.
        guard snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minTextLength else {
            return terms
        }
        cache[snapshot.id] = (snapshot.fingerprint, terms)
        return terms
    }

    static let minTextLength = 20

    // MARK: - Extraction

    /// Per-entry deduped term set (each entry contributes at most one mention per key).
    static func extract(from text: String) -> Set<ExtractedTerm> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minTextLength else { return [] }
        let input = String(trimmed.prefix(maxTextLength))

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = input
        let fullRange = input.startIndex..<input.endIndex
        // Force the dominant language explicitly rather than relying on
        // NLTagger's implicit per-call detection — on some devices that
        // implicit path silently yields zero tags for short/informal text
        // instead of falling back, so every entry looks term-less.
        let language = NLLanguageRecognizer.dominantLanguage(for: input) ?? .english
        tagger.setLanguage(language, range: fullRange)

        var byKey: [String: ExtractedTerm] = [:]

        // Pass 1 — named entities (person/place/organization).
        tagger.enumerateTags(
            in: fullRange, unit: .word, scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            let type: ThemeNodeType?
            switch tag {
            case .personalName?: type = .person
            case .placeName?: type = .place
            case .organizationName?: type = .keyword
            default: type = nil
            }
            if let type, let term = makeTerm(String(input[range]), type: type) {
                // First-seen label wins; name types always claim the key.
                if byKey[term.key] == nil { byKey[term.key] = term }
            }
            return true
        }

        // Pass 2 — common nouns as keywords.
        tagger.enumerateTags(
            in: fullRange, unit: .word, scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .omitOther]
        ) { tag, range in
            guard tag == .noun else { return true }
            if let term = makeTerm(String(input[range]), type: .keyword),
               byKey[term.key] == nil {
                byKey[term.key] = term
            }
            return true
        }

        return Set(byKey.values)
    }

    private static func makeTerm(_ token: String, type: ThemeNodeType) -> ExtractedTerm? {
        // NLTagger word units can carry trailing punctuation ("walk.", "one,")
        // — strip everything outside letters so variants merge and junk dies.
        let label = token.trimmingCharacters(in: CharacterSet.letters.inverted)
        let key = label
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard key.count >= 4, Int(key) == nil, !stopWords.contains(key) else { return nil }
        return ExtractedTerm(key: key, label: label, type: type)
    }

    // Seeded from InsightService.recurringKeywords' stop set, extended with
    // journal filler and the insightContext scaffold words ("Voice note 1:",
    // "Language:", "Transcript:", "English translation:") so the concat
    // format never produces fake nodes.
    static let stopWords: Set<String> = [
        // recurringKeywords seed
        "about", "after", "again", "also", "because", "been", "being", "could", "didnt", "does", "dont",
        "feel", "feeling", "felt", "from", "have", "just", "like", "more", "really", "still", "that",
        "their", "there", "thing", "think", "this", "today", "very", "want", "were", "what", "when",
        "with", "would", "your", "journal", "entry",
        // insightContext scaffold
        "voice", "note", "notes", "transcript", "language", "english", "translation",
        // journal filler
        "morning", "night", "evening", "afternoon", "time", "times", "day", "days", "week", "weeks",
        "month", "months", "year", "years", "things", "something", "anything", "everything", "nothing",
        "people", "life", "lot", "bit", "way", "ways", "kind", "sort", "stuff", "moment", "moments",
        "tomorrow", "yesterday", "everyone", "someone", "anyone",
        "while", "hours", "hour", "minutes", "minute", "tonight", "ones", "everything's",
        "situation", "whole", "half", "part", "parts", "place", "back"
    ]
}
