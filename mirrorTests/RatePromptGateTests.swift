import Testing
@testable import mirror

/// Backlog A17: the rate prompt was marked shown before presenting, so a presentation dropped
/// behind another sheet spent the once-per-install prompt unseen.
@Suite("Rate prompt gate")
struct RatePromptGateTests {
    @Test func presentsWhenPendingAndTheScreenIsFree() {
        #expect(ReviewRequestManager.canPresentPrompt(pending: true, alreadyShown: false, rootSheetUp: false, childSheetUp: false, onboardingComplete: true))
    }

    @Test func waitsWhileAChildViewHasASheetUp() {
        // Settings over Insights, a sheet in Ask or Brain: the root can't see these.
        #expect(!ReviewRequestManager.canPresentPrompt(pending: true, alreadyShown: false, rootSheetUp: false, childSheetUp: true, onboardingComplete: true))
    }

    @Test func otherBlockers() {
        #expect(!ReviewRequestManager.canPresentPrompt(pending: true, alreadyShown: false, rootSheetUp: true, childSheetUp: false, onboardingComplete: true))
        #expect(!ReviewRequestManager.canPresentPrompt(pending: true, alreadyShown: true, rootSheetUp: false, childSheetUp: false, onboardingComplete: true))
        #expect(!ReviewRequestManager.canPresentPrompt(pending: false, alreadyShown: false, rootSheetUp: false, childSheetUp: false, onboardingComplete: true))
        #expect(!ReviewRequestManager.canPresentPrompt(pending: true, alreadyShown: false, rootSheetUp: false, childSheetUp: false, onboardingComplete: false))
    }
}
