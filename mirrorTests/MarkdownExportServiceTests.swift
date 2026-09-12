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

    @Test func exportJoinsMultipleEntriesWithDivider() {
        let a = Entry(text: "First entry")
        let b = Entry(text: "Second entry", mood: "Hopeful")
        let output = MarkdownExportService.export(entries: [a, b])
        #expect(output.contains("First entry"))
        #expect(output.contains("*Mood: Hopeful*"))
        #expect(output.contains("\n\n---\n\n"))
    }
}
