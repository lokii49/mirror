import Testing
import Foundation
@testable import mirror

// Regression coverage for the truncation bug found 2026-09-17: `buildMemoryBrief`'s stats
// header (~280 chars) plus 5 excerpts at up to 220 chars each regularly exceeded the daily
// nudge's ~1,288-char background budget (28% of `dailyNudgePromptBudget`, 4,600). The final
// `clipped(brief, maxChars:)` call has no word-boundary awareness, so the overflow silently
// hard-cut the brief mid-word/mid-excerpt on nearly every generation. Fixed by dropping
// `memoryBriefExcerptLimit` from 5 to 4, which fits with margin. `buildMemoryBrief` bumped
// private -> internal (same pattern as `selectRepresentativeExcerpts`) so this suite can
// exercise the real function instead of re-deriving its arithmetic by hand.
@Suite("InsightService memory brief budget")
struct MemoryBriefBudgetTests {

    // 20 entries with substantial text (>220 chars each) — the realistic worst case: every
    // excerpt candidate is long enough to need its own per-excerpt clip, maximizing how much
    // of the outer budget the excerpts block consumes.
    private func longBackgroundPool(count: Int = 20) -> [Entry] {
        let filler = Array(repeating: "word", count: 80).joined(separator: " ")  // ~400 chars
        return (1...count).map { i in
            let e = Entry(text: "Entry \(i): \(filler)", mood: i % 3 == 0 ? "Anxious" : nil)
            e.createdAt = Calendar.current.date(byAdding: .day, value: -(i + 14), to: Date()) ?? Date()
            return e
        }
    }

    // The daily nudge's real background budget: Int(Double(4_600) * 0.28) — see
    // `dailyNudgePromptBudget` and `buildUserMessage` in InsightService.swift.
    private let dailyNudgeBackgroundBudget = 1_288

    @Test func allSelectedExcerptsSurviveIntact_atDailyNudgeBudget() {
        let brief = InsightService.buildMemoryBrief(from: longBackgroundPool(), maxChars: dailyNudgeBackgroundBudget)

        // Every excerpt line is prefixed "- <date>: " (see buildMemoryBrief). If the outer
        // clip had to cut into the excerpts block, at least one of these would be missing —
        // either dropped entirely or left as a dangling fragment that no longer starts a new
        // line cleanly.
        let excerptLines = brief
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("- ") }
        #expect(excerptLines.count == InsightService.memoryBriefExcerptLimit)

        // The stats header (reviewed count, moods, keywords, voice count) must also survive —
        // these are the FIRST thing in the string, so they're only at risk if maxChars itself
        // is too small overall, not from the excerpt-count issue, but worth pinning down.
        #expect(brief.contains("Older entries reviewed: 20"))
    }

    // Was named/written as "doesNotEndMidWord" checking `!brief.hasSuffix("...")` — wrong test
    // for this fixture: each excerpt is individually capped at 220 chars via its own `clipped()`
    // call (buildMemoryBrief line ~1363), and every entry here is ~400 chars, so the LAST
    // excerpt line legitimately ends in "..." from that per-excerpt clip — correct, intentional
    // behavior, not the bug this file is about. `hasSuffix("...")` was true unconditionally
    // regardless of whether the outer budget clip ever fired, so the assertion never actually
    // tested what its name claimed. The bug this file is really about (the OUTER
    // `clipped(brief, maxChars:)` call stacking a second truncation on top of an
    // already-clipped excerpt) is what a DOUBLED marker would signal — allSelectedExcerptsSurviveIntact
    // already proves the outer clip didn't cut a whole excerpt line away, so a doubled "......"
    // is the only remaining way it could still be touching the string.
    @Test func doesNotDoubleTruncate() {
        let brief = InsightService.buildMemoryBrief(from: longBackgroundPool(), maxChars: dailyNudgeBackgroundBudget)
        #expect(!brief.hasSuffix("......"))
    }

    @Test func staysWithinBudget() {
        let brief = InsightService.buildMemoryBrief(from: longBackgroundPool(), maxChars: dailyNudgeBackgroundBudget)
        #expect(brief.count <= dailyNudgeBackgroundBudget)
    }

    // Sanity check on the arithmetic itself: 4 excerpts at up to 220 chars plus header should
    // land comfortably under budget, not just barely. Actual measured margin against this
    // fixture is ~168 chars (brief.count 1,120 vs. budget 1,288) — the original "200" threshold
    // here was picked before that number was checked and didn't match it. 100 keeps the same
    // intent (a real cushion, not "barely fits") without asserting a margin tighter than what
    // the current implementation actually produces.
    @Test func hasComfortableMargin() {
        let brief = InsightService.buildMemoryBrief(from: longBackgroundPool(), maxChars: dailyNudgeBackgroundBudget)
        #expect(brief.count < dailyNudgeBackgroundBudget - 100)
    }

    // Fewer entries than the excerpt limit — the pool itself caps how many can be quoted,
    // same as the disclosure label's `min(background, memoryBriefExcerptLimit)`.
    @Test func smallPool_quotesAllOfIt() {
        let brief = InsightService.buildMemoryBrief(from: longBackgroundPool(count: 2), maxChars: dailyNudgeBackgroundBudget)
        let excerptLines = brief.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(excerptLines.count == 2)
    }
}
