import Foundation
import Testing
@testable import mirror

@Suite("Archive search")
struct EntrySearchTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func document(_ text: String = "Had coffee by the river after the work trip.",
                          date: Date? = nil, tags: [String] = ["work", "travel"],
                          moods: [String] = ["Content", "Zufrieden"], readable: Bool = true,
                          passages: [EntrySearchDocument.Passage]? = nil) -> EntrySearchDocument {
        EntrySearchDocument(passages: passages ?? [.init(text, source: .body)],
                            tags: tags.map(EntrySearch.fold), moods: moods.map(EntrySearch.fold),
                            createdAt: date ?? calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!,
                            hasPhoto: true, hasAudio: true, isPinned: false, isReadable: readable)
    }

    @Test func bestMatchRanksBodyAboveTranscriptAboveMetadata() {
        let query = EntrySearchQuery.parse("river")
        let body = document("Walked by the river.", tags: [])
        let transcript = document(tags: [], passages: [.init("Quiet day.", source: .body), .init("The river was loud.", source: .transcript(1))])
        let translation = document(tags: [], passages: [.init("Ruhiger Tag.", source: .body), .init("By the river.", source: .translation(1))])
        let tagOnly = document("Quiet day.", tags: ["river"])
        let scores = [body, transcript, translation, tagOnly].map { EntrySearch.relevance($0, query: query) }
        #expect(scores == scores.sorted(by: >))
        #expect(Set(scores).count == 4)
        // Word start counts more than a match inside a word.
        #expect(EntrySearch.relevance(document("river walk", tags: []), query: query)
                > EntrySearch.relevance(document("riverriver", tags: []), query: .parse("verri")))
    }

    @Test func evaluateReportsScoresOnlyForWordSearches() {
        let docs = [(UUID(), document()), (UUID(), document("Nothing related.", tags: []))]
        #expect(!EntrySearch.evaluate(docs, query: .parse("river"), calendar: calendar).scores.isEmpty)
        #expect(EntrySearch.evaluate(docs, query: .parse("tag:work"), calendar: calendar).scores.isEmpty)
        #expect(!EntrySearchQuery.parse("-river tag:work").hasTextTerms)
    }

    @Test func emptyFilteredResultsCountSearchOnlyMatches() {
        let docs = [(UUID(), document()), (UUID(), document("The river again.", tags: []))]
        var filters = EntryFilterCriteria()
        filters.moods = ["Anxious"]
        let results = EntrySearch.evaluate(docs, query: .parse("river"), filters: filters, calendar: calendar)
        #expect(results.ids.isEmpty)
        #expect(results.matchesWithoutFilters == 2)
        // Not computed when something matched, or when there is no search.
        #expect(EntrySearch.evaluate(docs, query: .parse("river"), calendar: calendar).matchesWithoutFilters == nil)
        #expect(EntrySearch.evaluate(docs, query: .parse(""), filters: filters, calendar: calendar).matchesWithoutFilters == nil)
    }

    @Test func wordsAreConjunctiveAndPhraseIsContiguous() {
        #expect(EntrySearch.matches(document(), query: .parse("river coffee")))
        #expect(!EntrySearch.matches(document(), query: .parse("coffee library")))
        #expect(EntrySearch.matches(document(), query: .parse("\"work trip\"")))
        #expect(!EntrySearch.matches(document(), query: .parse("\"coffee river\"")))
    }

    @Test func exclusionsApplyToTextAndFilters() {
        #expect(EntrySearch.matches(document(), query: .parse("coffee -meeting -is:pinned")))
        #expect(!EntrySearch.matches(document(), query: .parse("coffee -river")))
        #expect(!EntrySearch.matches(document(), query: .parse("-tag:work")))
    }

    @Test func metadataMatchesAndFieldsRequireFullNames() {
        #expect(EntrySearch.matches(document("Quiet afternoon"), query: .parse("travel zufrieden")))
        #expect(EntrySearch.matches(document(), query: .parse("#work tag:travel mood:Zufrieden has:audio has:photo")))
        #expect(!EntrySearch.matches(document(), query: .parse("tag:wor")))
        #expect(!EntrySearch.matches(document(), query: .parse("mood:Cont")))
        #expect(EntrySearch.matches(document(tags: ["work trip"]), query: .parse("tag:\"work trip\"")))
    }

    @Test func quotedPunctuationAndEscapesStayLiteral() {
        #expect(EntrySearch.matches(document("I said \"hello\" at 9:30, then wrote -meeting."),
                                   query: .parse("\"\\\"hello\\\"\" \"9:30\" \"-meeting\"")))
        #expect(EntrySearch.matches(document("Literal #work in my note."), query: .parse("\"#work\"")))
    }

    @Test(arguments: ["\"work", "tag:", "\"\"", "-", "has:video", "is:starred", "folder:work", "after:2026-02-30", "before:2026-2-01"])
    func malformedQueryNeverExpandsToAllEntries(_ input: String) {
        let query = EntrySearchQuery.parse(input)
        #expect(query.problem != nil)
        #expect(!EntrySearch.matches(document(), query: query))
    }

    @Test func dateBoundariesExcludeNamedDaysInLocalTimezone() {
        let query = EntrySearchQuery.parse("after:2026-10-06 before:2026-10-08", calendar: calendar)
        let first = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7))!
        #expect(EntrySearch.matches(document(date: first), query: query))
        #expect(!EntrySearch.matches(document(date: first.addingTimeInterval(-1)), query: query))
        let end = calendar.date(byAdding: .day, value: 1, to: first)!
        #expect(EntrySearch.matches(document(date: end.addingTimeInterval(-1)), query: query))
        #expect(!EntrySearch.matches(document(date: end), query: query))
    }

    @Test func daylightSavingBoundaryUsesCalendarDays() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        let query = EntrySearchQuery.parse("after:2026-03-08", calendar: calendar)
        #expect(EntrySearch.matches(document(date: start), query: query))
        #expect(!EntrySearch.matches(document(date: start.addingTimeInterval(-1)), query: query))
    }

    @Test func originalTranscriptsAndTranslationsAreSearchableWithoutContextLabels() {
        let value = document("", passages: [.init("今日は図書館に行った。", source: .transcript(1)),
                                           .init("I went to the library.", source: .translation(1))])
        #expect(EntrySearch.matches(value, query: .parse("図書館")))
        #expect(EntrySearch.matches(value, query: .parse("library")))
        #expect(!EntrySearch.matches(value, query: .parse("Transcript")))
        guard let excerpt = EntrySearch.excerpt(value, query: .parse("library")) else {
            Issue.record("Expected translated transcript excerpt"); return
        }
        if case .translation(1) = excerpt.source {} else { Issue.record("Wrong source attribution") }
    }

    @Test func afterDateStartsAtMidnightEvenWhenPreviousDayHasNoMidnight() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "Africa/Cairo")!
        let nextDay = local.date(from: DateComponents(year: 2026, month: 4, day: 25))!
        let query = EntrySearchQuery.parse("after:2026-04-24", calendar: local)
        #expect(EntrySearch.matches(document(date: nextDay), query: query))
        #expect(!EntrySearch.matches(document(date: nextDay.addingTimeInterval(-1)), query: query))
    }

    @Test func unicodeHighlightRangesReferToOriginalCharacters() {
        let value = document("🙂 Walked to the cafe\u{301} after visiting 東京.")
        let query = EntrySearchQuery.parse("cafe 東京")
        #expect(EntrySearch.matches(value, query: query))
        guard let excerpt = EntrySearch.excerpt(value, query: query) else {
            Issue.record("Expected Unicode excerpt"); return
        }
        let ns = excerpt.text as NSString
        #expect(excerpt.highlights.map { ns.substring(with: $0) }.contains("cafe\u{301}"))
        #expect(excerpt.highlights.map { ns.substring(with: $0) }.contains("東京"))
    }

    @Test func excerptFindsMatchBeyondOpeningParagraph() {
        let value = document(String(repeating: "Quiet morning. ", count: 30) + "Met at the library after lunch.")
        let excerpt = EntrySearch.excerpt(value, query: .parse("library"))
        #expect(excerpt?.text.hasPrefix("…") == true)
        #expect(excerpt?.text.contains("library") == true)
        let matchLocation = (excerpt?.text as NSString?)?.range(of: "library").location ?? Int.max
        #expect(matchLocation <= 21)
        #expect(EntrySearch.excerpt(value, query: .parse("-library")) == nil)
    }

    @Test func unavailableContentCannotSatisfyExclusions() {
        #expect(!EntrySearch.matches(document("", readable: false), query: .parse("-coffee")))
        #expect(EntrySearch.matches(document("", readable: false), query: .parse("  ")))
    }
}
