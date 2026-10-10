import Testing
import Foundation
@testable import mirror

/// A day whose newest reflection is the fallback retries automatically only after the writing
/// changes (backlog A5). Synthetic text only.
@Suite("Fallback retry gate")
struct FallbackRetryGateTests {
    @Test(arguments: [false, true], [false, true])
    func realOrNoReflectionNeverBlocks(sameSignature: Bool, userTap: Bool) {
        #expect(InsightService.allowsRetryAfterFallback(
            newestTodayIsFallback: false,
            storedSignature: sameSignature ? "s" : "other",
            signature: "s",
            userInitiatedRetry: userTap
        ))
    }

    @Test func fallbackWithUnchangedWritingBlocksAutomaticTriggers() {
        #expect(!InsightService.allowsRetryAfterFallback(newestTodayIsFallback: true, storedSignature: "s", signature: "s", userInitiatedRetry: false))
    }

    @Test func fallbackWithChangedWritingRetries() {
        #expect(InsightService.allowsRetryAfterFallback(newestTodayIsFallback: true, storedSignature: "s", signature: "t", userInitiatedRetry: false))
    }

    @Test func fallbackFromAnotherDeviceGetsOneTryHere() {
        #expect(InsightService.allowsRetryAfterFallback(newestTodayIsFallback: true, storedSignature: nil, signature: "s", userInitiatedRetry: false))
    }

    @Test func tryAgainTapAlwaysRuns() {
        #expect(InsightService.allowsRetryAfterFallback(newestTodayIsFallback: true, storedSignature: "s", signature: "s", userInitiatedRetry: true))
    }

    @Test func signatureChangesWhenAnEntryGrowsOrANewOneArrives() {
        let entry = Entry(text: "Short note about the bus.")
        let before = InsightService.fallbackRetrySignature(day: "2026-10-10", recent: [entry])
        #expect(before == InsightService.fallbackRetrySignature(day: "2026-10-10", recent: [entry]))

        entry.text = "Short note about the bus. Then a longer walk home along the canal."
        let grown = InsightService.fallbackRetrySignature(day: "2026-10-10", recent: [entry])
        #expect(grown != before)

        let another = Entry(text: "A second synthetic entry.")
        #expect(InsightService.fallbackRetrySignature(day: "2026-10-10", recent: [another, entry]) != grown)
        #expect(InsightService.fallbackRetrySignature(day: "2026-10-11", recent: [entry]) != grown)
    }

    @Test func signatureHoldsNoJournalText() {
        let entry = Entry(text: "Synthetic sentence with a distinctive word: marmalade.")
        #expect(!InsightService.fallbackRetrySignature(day: "2026-10-10", recent: [entry]).contains("marmalade"))
    }
}
