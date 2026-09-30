import Testing
import Foundation
@testable import mirror

@Suite("PreGrammarInsightRegrade.candidates")
struct PreGrammarInsightRegradeTests {
    private let free = "A synthetic free-prose digest that never quotes the writer."
    private let grounded = "WHAT'S BUILDING: You wrote, \"synthetic sentence.\" You seem steady."

    private func insight(_ type: InsightType, _ text: String, period: String, engine: LLMEngine?, age: TimeInterval = 0) -> Insight {
        let i = Insight(type: type, content: text, periodIdentifier: period, generatedByEngine: engine)
        i.generatedAt = Date(timeIntervalSinceNow: -age)
        return i
    }

    @Test func picksLatestUngroundedGemmaAndNilEngine() {
        let old = insight(.weeklyDigest, free, period: "2026-W38", engine: .gemma, age: 700)
        let latest = insight(.weeklyDigest, free, period: "2026-W39", engine: nil, age: 10)
        let month = insight(.monthlyReport, free, period: "2026-09", engine: .gemma)
        let result = PreGrammarInsightRegrade.candidates(among: [old, latest, month])
        #expect(result.count == 2)
        #expect(result.contains { $0 === latest })
        #expect(result.contains { $0 === month })
        #expect(!result.contains { $0 === old })
    }

    @Test func skipsGroundedAndFoundationModels() {
        let g = insight(.weeklyDigest, grounded, period: "2026-W39", engine: .gemma)
        let fm = insight(.monthlyReport, free, period: "2026-09", engine: .foundationModels)
        #expect(PreGrammarInsightRegrade.candidates(among: [g, fm]).isEmpty)
    }

    @Test func ignoresOtherTypes() {
        let nudge = insight(.dailyNudge, free, period: "2026-09-29", engine: .gemma)
        #expect(PreGrammarInsightRegrade.candidates(among: [nudge]).isEmpty)
    }

    @Test func latestRowGroundedMeansNothingToRegrade() {
        let old = insight(.weeklyDigest, free, period: "2026-W39", engine: .gemma, age: 500)
        let redone = insight(.weeklyDigest, grounded, period: "2026-W39", engine: .gemma)
        #expect(PreGrammarInsightRegrade.candidates(among: [old, redone]).isEmpty)
    }
}
