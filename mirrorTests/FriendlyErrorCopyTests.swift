import Testing
@testable import mirror

/// Backlog A15a: the generic failure copy shown by Ask, the digest and the report must not promise
/// an automatic retry tonight; nothing retries Ask, and the nightly digest runs only on Sundays.
@Suite("Friendly error copy")
struct FriendlyErrorCopyTests {
    @Test func serviceUnavailablePromisesNoNightlyRetry() {
        let text = friendlyLLMError(InsightError.serviceUnavailable("synthetic"))
        #expect(!text.contains("tonight"))
        #expect(text == friendlyLLMError(CancellationError()))
    }
}
