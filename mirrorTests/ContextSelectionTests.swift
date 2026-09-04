import Testing
import Foundation
@testable import mirror

// A5 of the 2.1.0 design plan (.claude/2.1.0-design-plan.md, Track A5): context selection into
// the LLM prompt budget shouldn't be pure recency — a substantive entry from weeks ago (long,
// or flagged with a negative mood) is more useful for spotting a recurring pattern than a short
// neutral check-in from yesterday. `InsightService.selectRepresentativeExcerpts` is the one
// seam this changed (feeds `buildMemoryBrief`'s excerpt selection, used by the "Long-term
// context"/"Older context" blocks in dailyNudge/weeklyDigest/monthlyReport's user messages) —
// bumped private -> internal for this suite, same pattern as InsightService.validate.
//
// These construct standalone `Entry` instances directly (no ModelContainer/context) — safe
// here since the function under test takes a plain `[Entry]` array and Entry has no
// relationships that need a context to resolve.

@Suite("InsightService context selection")
struct ContextSelectionTests {

    private func entry(daysAgo: Int, words: Int, mood: String? = nil) -> Entry {
        let text = Array(repeating: "word", count: words).joined(separator: " ")
        let e = Entry(text: text, mood: mood)
        e.createdAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return e
    }

    @Test func fewerThanLimit_returnsAllInRecencyOrder() {
        let entries = [entry(daysAgo: 3, words: 10), entry(daysAgo: 1, words: 10), entry(daysAgo: 5, words: 10)]
        let result = InsightService.selectRepresentativeExcerpts(from: entries, limit: 5)
        #expect(result.count == 3)
        #expect(result[0].createdAt > result[1].createdAt)
        #expect(result[1].createdAt > result[2].createdAt)
    }

    // Regression: with a uniform pool (no mood/word-count signal to differentiate), the result
    // must match the old `.prefix(5)`-on-recency behavior exactly, so typical journaling
    // patterns with no mood extremes aren't disturbed by this change.
    @Test func uniformPool_fallsBackToPureRecency() {
        let entries = (1...8).map { entry(daysAgo: $0, words: 20) }
        let result = InsightService.selectRepresentativeExcerpts(from: entries, limit: 5)
        #expect(result.count == 5)
        for (index, daysAgo) in [1, 2, 3, 4, 5].enumerated() {
            let expectedDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            #expect(Calendar.current.isDate(result[index].createdAt, inSameDayAs: expectedDate))
        }
    }

    // The core new behavior: an old, short, negative-mood entry outranks recency alone — pure
    // recency (the old `.prefix(5)`) would have excluded it entirely, since it's the 6th most
    // recent of 6 entries, one past the limit.
    @Test func negativeMoodEntry_outranksRecencyAlone() {
        var entries = (1...5).map { entry(daysAgo: $0, words: 20) }  // 5 short neutral entries, days 1-5
        let oldAnxious = entry(daysAgo: 20, words: 30, mood: "Anxious")  // scores 30 + 150 = 180
        entries.append(oldAnxious)

        let result = InsightService.selectRepresentativeExcerpts(from: entries, limit: 5)
        #expect(result.count == 5)
        #expect(result.contains { $0.mood == "Anxious" })
    }

    // Word count alone (no mood bonus) also matters, independent of the case above.
    @Test func longNeutralEntry_outranksRecencyAlone() {
        var entries = (1...5).map { entry(daysAgo: $0, words: 20) }  // 5 short neutral entries, days 1-5
        let oldLong = entry(daysAgo: 10, words: 300)  // scores 300, no mood bonus
        entries.append(oldLong)

        let result = InsightService.selectRepresentativeExcerpts(from: entries, limit: 5)
        #expect(result.count == 5)
        #expect(result.contains { $0.wordCount == 300 })
    }

    // A short positive-mood entry (Content: not in MirrorTheme.negativeMoods) gets no bonus and
    // should NOT outrank recency the way the negative-mood case above does — the bonus is
    // deliberately scoped to negativeMoods, not "any mood at all".
    @Test func positiveMoodEntry_getsNoBonus_recencyStillWins() {
        var entries = (1...5).map { entry(daysAgo: $0, words: 20) }  // 5 short neutral entries, days 1-5
        let oldContent = entry(daysAgo: 20, words: 20, mood: "Content")  // scores 20, tied with the rest, older
        entries.append(oldContent)

        let result = InsightService.selectRepresentativeExcerpts(from: entries, limit: 5)
        #expect(result.count == 5)
        #expect(!result.contains { $0.mood == "Content" })
    }

    // Selection is scored, but the final result is re-sorted to recency (newest first) for
    // display — the excerpt block should still read chronologically, not score-ordered, even
    // though the oldest entry here has the highest score.
    @Test func resultIsSortedByRecency_notByScore() {
        var entries = (1...5).map { entry(daysAgo: $0, words: 20) }
        entries.append(entry(daysAgo: 20, words: 30, mood: "Anxious"))
        let result = InsightService.selectRepresentativeExcerpts(from: entries, limit: 5)
        for i in 0..<(result.count - 1) {
            #expect(result[i].createdAt > result[i + 1].createdAt)
        }
    }
}
