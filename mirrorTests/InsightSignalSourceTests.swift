import Testing
import Foundation
@testable import mirror

// "How this was generated" (InsightSignalSource) on the grammar-constrained Gemma paths
// (2026-09-28): a device showed "READ CLOSELY 3 entries · 26 – 27 Sep" and "20 earlier entries
// summarized · 4 quoted" for a grounded nudge, but Gemma had only been sent the 27 Sep entries.
// The sheet reconstructs the inputs, so it must follow the path the insight actually took.
@MainActor
struct InsightSignalSourceTests {

    private let asOf = Calendar.current.startOfDay(for: Date()).addingTimeInterval(20 * 3_600)

    private func entry(_ text: String, _ mood: String, hoursBefore: Double) -> Entry {
        let e = Entry(text: text, mood: mood)
        e.createdAt = asOf.addingTimeInterval(-hoursBefore * 3_600)
        return e
    }

    private func insight(_ type: InsightType, _ content: String, _ engine: LLMEngine) -> Insight {
        let i = Insight(type: type, content: content, periodIdentifier: "test", generatedByEngine: engine)
        i.generatedAt = asOf
        return i
    }

    /// Two entries today, one yesterday, five older.
    private var nudgeEntries: [Entry] {
        [
            [real journal text removed]
            [real journal text removed]
            [real journal text removed]
        ] + (2...6).map { entry("An older entry about an ordinary working day number \($0).", "Content", hoursBefore: Double($0) * 24 + 3) }
    }

    private func value(_ label: String, in r: InsightSignalSource.Resolved) -> String? {
        r.rows.first { $0.label == label }?.value
    }

    @Test func groundedGemmaNudge_showsOnlyTheNewestDaysEntries_andNoContext() {
        let r = InsightSignalSource.resolve(
            [real journal text removed]
            entries: nudgeEntries, engineLabel: "GEMMA"
        )
        #expect(value("READ CLOSELY", in: r)?.hasPrefix("2 entries") == true)
        #expect(value("CONTEXT", in: r) == "none sent")
        #expect(value("MOOD READ", in: r) == "\(MirrorTheme.localizedMoodName(for: "Content").uppercased()), \(MirrorTheme.localizedMoodName(for: "Hopeful").uppercased())")
        #expect(r.reading.count == 2)
        #expect(r.note != nil)
    }

    @Test func freeProseNudge_keepsTheRecentAndSummarizedContext() {
        let r = InsightSignalSource.resolve(
            insight: insight(.dailyNudge, "The evening at the flat sounds like it gave you room to breathe.", .foundationModels),
            entries: nudgeEntries, engineLabel: "FM"
        )
        #expect(value("READ CLOSELY", in: r)?.hasPrefix("3 entries") == true)
        #expect(value("CONTEXT", in: r) == "5 earlier entries summarized · 4 quoted")
        #expect(r.reading.count == 3)
    }

    @Test func groundedGemmaDigest_saysNothingEarlierWasSent() {
        let entries = [
            entry("Long day at work, the release slipped again and I stayed late.", "Drained", hoursBefore: 1),
            entry("An entry from two weeks ago about the garden and the weekend.", "Content", hoursBefore: 24 * 14),
        ]
        let grounded = InsightSignalSource.resolve(
            insight: insight(.weeklyDigest, #"THIS WEEK'S THEME: A heavy week. YOUR ENERGY: x WHAT'S BUILDING: You wrote, "Long day at work, the release slipped again and I stayed late." WATCH OUT FOR: x"#, .gemma),
            entries: entries, engineLabel: "GEMMA"
        )
        #expect(value("EARLIER", in: grounded) == "none sent")
        #expect(grounded.note != nil)

        let freeProse = InsightSignalSource.resolve(
            insight: insight(.weeklyDigest, "THIS WEEK'S THEME: The release kept slipping.", .foundationModels),
            entries: entries, engineLabel: "FM"
        )
        #expect(value("EARLIER", in: freeProse) == "1 entry carried in")
    }

    @Test func groundedGemmaMonthly_saysNothingEarlierWasSent() {
        let entries = [
            entry("Signed the lease for the new flat today, finally.", "Hopeful", hoursBefore: 1),
            entry("An entry from last month about the old flat.", "Content", hoursBefore: 24 * 40),
        ]
        let r = InsightSignalSource.resolve(
            insight: insight(.monthlyReport, #"THE IMAGE: x WHAT YOU'RE BECOMING: You wrote, "Signed the lease for the new flat today, finally." x"#, .gemma),
            entries: entries, engineLabel: "GEMMA"
        )
        #expect(value("EARLIER", in: r) == "none sent")
        #expect(r.note?.contains("word for word") == true)
    }
}
