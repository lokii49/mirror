import Testing
@testable import mirror

// A6 of the 2.1.0 design plan (.claude/2.1.0-design-plan.md, Track A6): Insight.generatedByEngine
// is a persisted, CloudKit-synced field — its rawValue strings are a wire format, not free to
// rename (see the comment at LLMEngine's declaration). These are small but deliberate: a rename
// here would silently strand the old value on every already-synced Insight.

@Suite("Insight engine attribution")
struct InsightModelTests {

    @Test func engineRawValues_areStable() {
        // Locks the exact wire-format strings. If this fails, something renamed a case —
        // that's a breaking change for every already-synced Insight, not a free rename.
        #expect(LLMEngine.foundationModels.rawValue == "foundationModels")
        #expect(LLMEngine.gemma.rawValue == "gemma")
    }

    @Test func insightInit_withEngine_setsGeneratedByEngine() {
        let insight = Insight(type: .dailyNudge, content: "test", periodIdentifier: "2026-W36", generatedByEngine: .gemma)
        #expect(insight.generatedByEngine == "gemma")
    }

    @Test func insightInit_withoutEngine_leavesNil() {
        // Default parameter — existing call sites that don't pass one (if any remain, or a
        // future one added without thinking about it) shouldn't silently start persisting a
        // wrong value.
        let insight = Insight(type: .dailyNudge, content: "test", periodIdentifier: "2026-W36")
        #expect(insight.generatedByEngine == nil)
    }
}
