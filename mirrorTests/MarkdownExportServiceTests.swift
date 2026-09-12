import Testing
import Foundation
@testable import mirror

// Standalone `Entry` instances (no ModelContainer/context) — safe per the
// same reasoning as ContextSelectionTests.swift: MarkdownExportService only
// reads properties, never inserts into a context.
struct MarkdownExportServiceTests {

    @Test func plainBodyParagraphIsUnwrapped() {
        let entry = Entry(text: "Just a normal line.")
        #expect(MarkdownExportService.markdownBody(for: entry) == "Just a normal line.")
    }

    @Test func headingAndBlockQuote() throws {
        let entry = Entry(text: "Title line\nA quote")
        entry.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: [.title, .blockQuote],
            indentLevels: nil
        ))
        #expect(MarkdownExportService.markdownBody(for: entry) == "# Title line\n> A quote")
    }

    @Test func checklistAndNumberedListWithIndent() throws {
        let entry = Entry(text: "Done\nNot done\nFirst\nSecond")
        entry.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: [.checklistChecked, .checklistUnchecked, .numberedList, .numberedList],
            indentLevels: [0, 1, 0, 0]
        ))
        let expected = "- [x] Done\n  - [ ] Not done\n1. First\n2. Second"
        #expect(MarkdownExportService.markdownBody(for: entry) == expected)
    }

    @Test func numberedListCounterResetsOnStyleBreak() throws {
        let entry = Entry(text: "One\nInterrupt\nOne again")
        entry.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: [.numberedList, .body, .numberedList],
            indentLevels: nil
        ))
        #expect(MarkdownExportService.markdownBody(for: entry) == "1. One\nInterrupt\n1. One again")
    }

    @Test func numberedListRestartsCounterOnNestedIndent() throws {
        // Outer 1, 2 — then two nested items under item 2 should restart at 1,
        // then the outer list resumes its own sequence at 3 (not 5).
        let entry = Entry(text: "First\nSecond\nSub one\nSub two\nThird")
        entry.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(
            paragraphStyles: [.numberedList, .numberedList, .numberedList, .numberedList, .numberedList],
            indentLevels: [0, 0, 1, 1, 0]
        ))
        let expected = "1. First\n2. Second\n  1. Sub one\n  2. Sub two\n3. Third"
        #expect(MarkdownExportService.markdownBody(for: entry) == expected)
    }

    @Test func boldItalicAndHighlightNestConsistently() throws {
        let entry = Entry(text: "plain bold end")
        // "bold" starts at index 6, length 4
        entry.inlineStyleData = try JSONEncoder().encode(InlineStyleDocument(ranges: [
            InlineStyleRange(location: 6, length: 4, bold: true, italic: true, underline: false, strikethrough: false, highlightIndex: 2)
        ]))
        #expect(MarkdownExportService.markdownBody(for: entry) == "plain ==***bold***== end")
    }

    @Test func monospacedWrapsAsInlineCode() throws {
        let entry = Entry(text: "let x = 1")
        entry.textStyleData = try JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: [.monospaced], indentLevels: nil))
        #expect(MarkdownExportService.markdownBody(for: entry) == "`let x = 1`")
    }

    @Test func photoTokenReplacedWithPlaceholder() {
        let entry = Entry(text: "before [[mirror-photo-0]] after")
        #expect(MarkdownExportService.markdownBody(for: entry) == "before 📷 after")
    }

    @Test func encryptedEntryUnavailableShowsPlaceholder() {
        let entry = Entry(text: "secret")
        // MirrorEncryption only treats a value as encrypted (and thus decryptable-or-
        // failed) when it carries the "mirror:v1:" prefix; a non-base64 payload after
        // that prefix deterministically fails to decrypt without touching Keychain.
        entry.encryptedText = "mirror:v1:!!!not-valid-base64!!!"
        #expect(entry.textDecryptionFailed)
        #expect(MarkdownExportService.markdownBody(for: entry) == "*Encrypted entry unavailable*")
    }

    @Test func linkWrapsAsMarkdownLinkSyntax() throws {
        let entry = Entry(text: "see this article here")
        // "article" starts at index 9, length 7
        entry.inlineStyleData = try JSONEncoder().encode(InlineStyleDocument(ranges: [
            InlineStyleRange(location: 9, length: 7, bold: false, italic: false, underline: false, strikethrough: false, highlightIndex: nil, linkURL: "https://example.com")
        ]))
        #expect(MarkdownExportService.markdownBody(for: entry) == "see this [article](https://example.com) here")
    }

    @Test func linkNestsOutsideBoldEmphasis() throws {
        let entry = Entry(text: "a bold link here")
        // "bold link" starts at index 2, length 9
        entry.inlineStyleData = try JSONEncoder().encode(InlineStyleDocument(ranges: [
            InlineStyleRange(location: 2, length: 9, bold: true, italic: false, underline: false, strikethrough: false, highlightIndex: nil, linkURL: "https://example.com")
        ]))
        #expect(MarkdownExportService.markdownBody(for: entry) == "a [**bold link**](https://example.com) here")
    }

    @Test func validatedLinkURLAcceptsHttpAndHttps() {
        #expect(validatedLinkURL(from: "https://example.com")?.absoluteString == "https://example.com")
        #expect(validatedLinkURL(from: "http://example.com")?.absoluteString == "http://example.com")
    }

    @Test func validatedLinkURLPrependsHttpsToBareDomain() {
        #expect(validatedLinkURL(from: "example.com")?.absoluteString == "https://example.com")
    }

    @Test func validatedLinkURLRejectsNonHttpSchemes() {
        #expect(validatedLinkURL(from: "javascript:alert(1)") == nil)
        #expect(validatedLinkURL(from: "file:///etc/passwd") == nil)
        #expect(validatedLinkURL(from: "mirror-photo://x") == nil)
    }

    @Test func validatedLinkURLRejectsEmptyOrNil() {
        #expect(validatedLinkURL(from: nil) == nil)
        #expect(validatedLinkURL(from: "   ") == nil)
    }

    @Test func markdownExportDoesNotFilterLinkScheme() throws {
        // MarkdownExportService renders whatever linkURL string is stored — export is
        // inert text, not a tap surface, so the scheme guard only needs to live at the
        // interactive render boundaries (editor + read view), covered above. Documents
        // that export deliberately doesn't duplicate that filtering.
        let entry = Entry(text: "click here now")
        // "here" starts at index 6, length 4
        entry.inlineStyleData = try JSONEncoder().encode(InlineStyleDocument(ranges: [
            InlineStyleRange(location: 6, length: 4, bold: false, italic: false, underline: false, strikethrough: false, highlightIndex: nil, linkURL: "javascript:alert(1)")
        ]))
        #expect(MarkdownExportService.markdownBody(for: entry) == "click [here](javascript:alert(1)) now")
    }

    @Test func inlineStyleRangeDecodesOldDataMissingLinkURLKey() throws {
        // Simulates data encoded before linkURL existed — no key present at all.
        let oldJSON = """
        {"location":0,"length":4,"bold":true,"italic":false,"underline":false,"strikethrough":false,"highlightIndex":null}
        """
        let range = try JSONDecoder().decode(InlineStyleRange.self, from: Data(oldJSON.utf8))
        #expect(range.bold)
        #expect(range.linkURL == nil)
    }

    @Test func exportJoinsMultipleEntriesWithDivider() {
        let a = Entry(text: "First entry")
        let b = Entry(text: "Second entry", mood: "Hopeful")
        let output = MarkdownExportService.export(entries: [a, b])
        #expect(output.contains("First entry"))
        #expect(output.contains("*Mood: Hopeful*"))
        #expect(output.contains("\n\n---\n\n"))
    }
}
