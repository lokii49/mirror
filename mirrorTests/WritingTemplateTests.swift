import Testing
@testable import mirror

// Real on-device bug: NoteEditorTextView.updateUIView only clamps the *old* selectedRange into
// newly-set text's bounds, it doesn't reposition it meaningfully — so the caret landed wherever
// that clamp happened to fall for each template's specific shape, not where typing should start.
// cursorOffset is the fix's one purely-testable seam: it must always point exactly at the
// boundary between seedPrefix and seedSuffix, i.e. the character position right after the
// prompt text and right before whatever comes next (a checklist number, a blank line, etc).
@Suite("WritingTemplate cursor placement")
struct WritingTemplateTests {

    @Test func gratitude_cursorLandsRightAfterPromptText() {
        let template = WritingTemplate.gratitude
        let prefix = String(template.seedText.prefix(template.cursorOffset))
        #expect(prefix == "Today I'm grateful for…")
        #expect(template.seedText.hasSuffix("\n\n"))
    }

    @Test func threeWins_cursorLandsInsideFirstItemNotAtStartOfList() {
        let template = WritingTemplate.threeWins
        let prefix = String(template.seedText.prefix(template.cursorOffset))
        #expect(prefix == "1. ")
        #expect(template.seedText == "1. \n2. \n3. ")
    }

    @Test func moodLog_cursorLandsAfterFeelingNotAfterBecause() {
        let template = WritingTemplate.moodLog
        let prefix = String(template.seedText.prefix(template.cursorOffset))
        #expect(prefix == "Right now I feel…")
        #expect(template.seedText.hasSuffix("Because…"))
    }

    @Test(arguments: WritingTemplate.allCases)
    func cursorOffset_isAlwaysWithinSeedTextBounds(_ template: WritingTemplate) {
        #expect(template.cursorOffset >= 0)
        #expect(template.cursorOffset <= template.seedText.count)
    }
}
