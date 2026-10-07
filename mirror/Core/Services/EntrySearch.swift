import Foundation

/// Archive-only search. Immutable values can be searched off the model context's actor.
/// Decrypted documents remain in memory; they must never be persisted or logged.
nonisolated struct EntrySearchDocument: Sendable {
    struct Passage: Sendable {
        enum Source: Sendable { case body, transcript(Int), translation(Int) }
        let text: String
        let source: Source
        let folded: String

        init(_ text: String, source: Source) {
            self.text = text
            self.source = source
            self.folded = EntrySearch.fold(text)
        }
    }

    let passages: [Passage]
    let tags: [String]
    let moods: [String]
    let createdAt: Date
    let hasPhoto: Bool
    let hasAudio: Bool
    let isPinned: Bool
    let isReadable: Bool
}

nonisolated struct EntrySearchQuery: Sendable {
    enum Condition: Sendable {
        case text(String), tag(String), mood(String)
        case after(Date), before(Date), photo, audio, pinned
    }
    struct Term: Sendable {
        let condition: Condition
        let excluded: Bool
    }
    enum Problem: Error, Sendable {
        case unfinishedQuote, missingValue, unknownFilter, invalidDate, invalidValue
    }
    let terms: [Term]
    let problem: Problem?
    var isEmpty: Bool { terms.isEmpty && problem == nil }

    /// Quotes can follow a field name (tag:"work trip"). A backslash escapes a
    /// quote or backslash inside quotes. Operators are literal ASCII in all locales.
    static func parse(_ input: String, calendar: Calendar = .current) -> Self {
        var tokens: [(value: String, literal: Bool, excluded: Bool)] = []
        var token = ""
        var quoted = false
        var escaped = false
        var literal = false
        var excluded = false
        for character in input {
            if escaped { token.append(character); escaped = false; continue }
            if quoted && character == "\\" { escaped = true; continue }
            if character == "\"" {
                if !quoted && token.isEmpty { literal = true }
                quoted.toggle()
                continue
            }
            if character.isWhitespace && !quoted {
                if !token.isEmpty || literal || excluded { tokens.append((token, literal, excluded)) }
                token = ""; literal = false; excluded = false
            } else if character == "-", token.isEmpty, !quoted, !excluded, !literal {
                excluded = true
            } else { token.append(character) }
        }
        guard !quoted && !escaped else { return Self(terms: [], problem: .unfinishedQuote) }
        if !token.isEmpty || literal || excluded { tokens.append((token, literal, excluded)) }
        var terms: [Term] = []
        do {
            for token in tokens {
                var value = token.value
                let excluded = token.excluded
                guard !value.isEmpty else { throw Problem.missingValue }
                let condition: Condition
                if !token.literal, value.hasPrefix("#") {
                    value.removeFirst()
                    guard !value.isEmpty else { throw Problem.missingValue }
                    condition = .tag(EntrySearch.fold(value))
                } else if !token.literal, let colon = value.firstIndex(of: ":") {
                    let field = value[..<colon].lowercased()
                    value = String(value[value.index(after: colon)...])
                    guard !value.isEmpty else { throw Problem.missingValue }
                    switch field {
                    case "tag": condition = .tag(EntrySearch.fold(value))
                    case "mood": condition = .mood(EntrySearch.fold(value))
                    case "after", "before":
                        guard let day = parseDay(value, calendar: calendar) else { throw Problem.invalidDate }
                        if field == "after" {
                            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { throw Problem.invalidDate }
                            // A DST change can make the named day's first instant
                            // 01:00. Adding a day alone would then omit an hour.
                            condition = .after(calendar.startOfDay(for: next))
                        } else { condition = .before(day) }
                    case "has":
                        switch value.lowercased() {
                        case "photo": condition = .photo
                        case "audio": condition = .audio
                        default: throw Problem.invalidValue
                        }
                    case "is":
                        guard value.lowercased() == "pinned" else { throw Problem.invalidValue }
                        condition = .pinned
                    default: throw Problem.unknownFilter
                    }
                } else {
                    guard !value.isEmpty else { throw Problem.missingValue }
                    condition = .text(EntrySearch.fold(value))
                }
                terms.append(Term(condition: condition, excluded: excluded))
            }
            return Self(terms: terms, problem: nil)
        } catch let problem as Problem { return Self(terms: [], problem: problem) }
        catch { return Self(terms: [], problem: .invalidValue) }
    }

    private static func parseDay(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        // Query syntax uses Gregorian dates, with the user's timezone (including DST).
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        guard let date = gregorian.date(from: DateComponents(year: year, month: month, day: day)),
              gregorian.component(.year, from: date) == year,
              gregorian.component(.month, from: date) == month,
              gregorian.component(.day, from: date) == day else { return nil }
        return gregorian.startOfDay(for: date)
    }
}

nonisolated enum EntrySearch {
    struct Results: Sendable {
        var ids: Set<UUID> = []
        var excerpts: [UUID: Excerpt] = [:]
    }

    static func evaluate(_ documents: [(UUID, EntrySearchDocument)], query: EntrySearchQuery,
                         filters: EntryFilterCriteria = EntryFilterCriteria(), now: Date = Date(),
                         calendar: Calendar = .current) -> Results {
        var results = Results()
        for (id, document) in documents {
            guard !Task.isCancelled else { return Results() }
            guard filters.matches(document, now: now, calendar: calendar), matches(document, query: query) else { continue }
            results.ids.insert(id)
            results.excerpts[id] = excerpt(document, query: query)
        }
        return results
    }

    struct Excerpt: Sendable {
        let text: String
        let highlights: [NSRange]
        let source: EntrySearchDocument.Passage.Source
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func matches(_ document: EntrySearchDocument, query: EntrySearchQuery) -> Bool {
        guard query.problem == nil else { return false }
        guard !query.isEmpty else { return true }
        // Do not treat an unavailable key as an empty document satisfying exclusions.
        guard document.isReadable else { return false }
        return query.terms.allSatisfy { term in
            let found: Bool
            switch term.condition {
            case .text(let value):
                found = document.passages.contains { $0.folded.contains(value) }
                    || document.tags.contains { $0.contains(value) }
                    || document.moods.contains { $0.contains(value) }
            case .tag(let value): found = document.tags.contains(value)
            case .mood(let value): found = document.moods.contains(value)
            case .after(let date): found = document.createdAt >= date
            case .before(let date): found = document.createdAt < date
            case .photo: found = document.hasPhoto
            case .audio: found = document.hasAudio
            case .pinned: found = document.isPinned
            }
            return term.excluded ? !found : found
        }
    }

    /// Ranges are calculated in the original text, so accents and surrogate pairs
    /// retain their original coordinates. Excerpts never show AI context labels.
    static func excerpt(_ document: EntrySearchDocument, query: EntrySearchQuery, radius: Int = 70) -> Excerpt? {
        let values = query.terms.compactMap { term -> String? in
            guard !term.excluded, case .text(let value) = term.condition else { return nil }
            return value
        }
        guard !values.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let locale = Locale(identifier: "en_US_POSIX")
        for passage in document.passages {
            guard let found = values.compactMap({ passage.text.range(of: $0, options: options, locale: locale) })
                .min(by: { $0.lowerBound < $1.lowerBound }),
                  let first = Range((passage.text as NSString).rangeOfComposedCharacterSequences(
                    for: NSRange(found, in: passage.text)), in: passage.text) else { continue }
            // Put the match near the beginning so a compact archive row does not
            // truncate the very word the user searched for.
            let start = passage.text.index(first.lowerBound, offsetBy: -min(radius, 20), limitedBy: passage.text.startIndex) ?? passage.text.startIndex
            let end = passage.text.index(first.upperBound, offsetBy: radius, limitedBy: passage.text.endIndex) ?? passage.text.endIndex
            let snippet = (start > passage.text.startIndex ? "…" : "")
                + String(passage.text[start..<end]) + (end < passage.text.endIndex ? "…" : "")
            var ranges: [NSRange] = []
            for value in values {
                var cursor = snippet.startIndex
                while cursor < snippet.endIndex,
                      let range = snippet.range(of: value, options: options, range: cursor..<snippet.endIndex, locale: locale) {
                    ranges.append((snippet as NSString).rangeOfComposedCharacterSequences(for: NSRange(range, in: snippet)))
                    cursor = range.upperBound
                }
            }
            return Excerpt(text: snippet, highlights: ranges, source: passage.source)
        }
        return nil
    }
}
