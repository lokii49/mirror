import Testing
@testable import mirror

// NotificationService.notificationSnippet is pure string truncation with no notification-center
// dependency — the rest of the notification-gating logic (permission timing, category
// registration) needs a UNUserNotificationCenter fake this suite doesn't have, so only this piece
// is covered.
@Suite("NotificationService.notificationSnippet")
struct NotificationSnippetTests {

    @Test func shortTextReturnedUnchanged() {
        #expect(NotificationService.notificationSnippet("A short reflection.") == "A short reflection.")
    }

    @Test func longTextTruncatesAtWordBoundary() {
        let text = "This reflection goes on for quite a while about several different things you wrote"
        let result = NotificationService.notificationSnippet(text, limit: 30)
        #expect(result == "This reflection goes on for…")
        #expect(!(result?.hasSuffix(" …") ?? false))
    }

    @Test func noSpaceBeforeLimitStillTruncates() {
        let text = String(repeating: "a", count: 80)
        let result = NotificationService.notificationSnippet(text, limit: 30)
        #expect(result?.count == 31)
        #expect(result?.hasSuffix("…") == true)
    }

    @Test func emptyStringReturnsNil() {
        #expect(NotificationService.notificationSnippet("") == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        #expect(NotificationService.notificationSnippet("   \n  ") == nil)
    }

    @Test func exactlyAtLimitReturnedUnchanged() {
        let text = String(repeating: "b", count: 60)
        #expect(NotificationService.notificationSnippet(text, limit: 60) == text)
    }
}
