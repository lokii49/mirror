import Testing
@testable import mirror

// Advisor-audit finding, 2026-09-17: isUngroundedFallback is plain content equality against the
// three current *UngroundedFallback constants. Those constants were already reworded once the
// same day this detection shipped (Mirror -> MirrorNotes, plus a full rewrite) — exact-equality
// alone would silently stop recognizing any fallback Insight already persisted with the old
// text, rendering it as a normal card with no Try Again button. legacyUngroundedFallbacks exists
// specifically to keep that data recognizable.
@Suite("InsightService.isUngroundedFallback")
struct UngroundedFallbackDetectionTests {

    @Test func currentDailyNudgeFallback_isDetected() {
        #expect(InsightService.isUngroundedFallback(InsightService.dailyNudgeUngroundedFallback))
    }

    @Test func currentWeeklyDigestFallback_isDetected() {
        #expect(InsightService.isUngroundedFallback(InsightService.weeklyDigestUngroundedFallback))
    }

    @Test func currentMonthlyReportFallback_isDetected() {
        #expect(InsightService.isUngroundedFallback(InsightService.monthlyReportUngroundedFallback))
    }

    // The exact strings this app has shipped as fallback content before the current wording —
    // regression coverage for the specific gap the audit caught, not just the current constants.
    @Test func legacyDailyNudgeFallback_stillDetected() {
        #expect(InsightService.isUngroundedFallback(
            "Mirror couldn't find a reflection clearly grounded in today's entries. Check back tomorrow, or add a bit more to what you've written today."
        ))
    }

    @Test func legacyWeeklyDigestFallback_stillDetected() {
        #expect(InsightService.isUngroundedFallback(
            "Mirror couldn't find a digest clearly grounded in this week's entries. Check back tomorrow, or write a bit more this week."
        ))
    }

    @Test func legacyMonthlyReportFallback_stillDetected() {
        #expect(InsightService.isUngroundedFallback(
            "Mirror couldn't find a report clearly grounded in this month's entries. Check back tomorrow, or write a bit more this month."
        ))
    }

    @Test func realReflectionContent_isNotDetected() {
        #expect(!InsightService.isUngroundedFallback(
            "The rain outside feels like it's holding back, a quiet grayness mirroring the feeling in your chest."
        ))
    }

    @Test func emptyString_isNotDetected() {
        #expect(!InsightService.isUngroundedFallback(""))
    }
}
