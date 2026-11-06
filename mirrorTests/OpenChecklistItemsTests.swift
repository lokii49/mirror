import Foundation
import SwiftData
import Testing
@testable import mirror

/// Still open: unticked checklist lines across entries. Synthetic text only.
@Suite("Still open checklist items")
@MainActor
struct OpenChecklistItemsTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func styles(_ list: [NoteParagraphTextStyle]) -> Data {
        try! JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: list, indentLevels: nil, fontChoices: nil))
    }

    private func entry(_ text: String, _ list: [NoteParagraphTextStyle], at date: Date, in context: ModelContext) -> Entry {
        let entry = Entry(text: text)
        entry.createdAt = date
        entry.textStyleData = styles(list)
        context.insert(entry)
        return entry
    }

    @Test func onlyUncheckedNonEmptyChecklistLines() {
        let text = "Groceries\nMilk\nEggs\n\nBread\nA note"
        let data = styles([.heading, .checklistUnchecked, .checklistChecked, .checklistUnchecked, .checklistUnchecked, .body])
        let lines = OpenChecklistItems.uncheckedLines(text: text, textStyleData: data)
        #expect(lines == [.init(index: 1, text: "Milk"), .init(index: 4, text: "Bread")])
    }

    @Test func noStylesOrNoChecklistMeansNothing() {
        #expect(OpenChecklistItems.uncheckedLines(text: "Milk", textStyleData: nil).isEmpty)
        #expect(OpenChecklistItems.uncheckedLines(text: "Milk", textStyleData: styles([.bulletedList])).isEmpty)
        // Styles longer than the text (a trailing empty paragraph) don't crash or invent lines.
        #expect(OpenChecklistItems.uncheckedLines(text: "Milk", textStyleData: styles([.checklistUnchecked, .checklistUnchecked])).count == 1)
    }

    @Test func photoTokensAreLeftOutOfTheShownText() {
        let text = "Pick up [[mirror-photo-0]]prints"
        let lines = OpenChecklistItems.uncheckedLines(text: text, textStyleData: styles([.checklistUnchecked]))
        #expect(lines.first?.text == "Pick up prints")
    }

    @Test func groupsAreNewestFirstAndSkipDoneLists() throws {
        let context = try context()
        let now = Date()
        _ = entry("Call the plumber\nPay rent", [.checklistUnchecked, .checklistUnchecked], at: now.addingTimeInterval(-86_400), in: context)
        let newer = entry("Batteries", [.checklistUnchecked], at: now, in: context)
        _ = entry("Done thing", [.checklistChecked], at: now.addingTimeInterval(-3_600), in: context)
        _ = Entry(text: "Plain entry")
        try context.save()
        let groups = OpenChecklistItems.groups(in: context)
        #expect(groups.map(\.lines.count) == [1, 2])
        #expect(groups.first?.entryID == newer.id)
    }

    @Test func tickingWritesBackAndUntickingRestores() throws {
        let context = try context()
        let item = entry("Milk\nEggs", [.checklistUnchecked, .checklistUnchecked], at: Date(), in: context)
        try context.save()
        let line = OpenChecklistItems.Line(index: 1, text: "Eggs")
        #expect(OpenChecklistItems.setChecked(true, line: line, entryID: item.id, in: context))
        #expect(NoteEditorCodec.decodeTextStyleDocument(item.textStyleData)?.paragraphStyles == [.checklistUnchecked, .checklistChecked])
        #expect(OpenChecklistItems.groups(in: context).first?.lines == [.init(index: 0, text: "Milk")])
        #expect(OpenChecklistItems.setChecked(false, line: line, entryID: item.id, in: context))
        #expect(NoteEditorCodec.decodeTextStyleDocument(item.textStyleData)?.paragraphStyles == [.checklistUnchecked, .checklistUnchecked])
        #expect(item.text == "Milk\nEggs", "text untouched")
    }

    @Test func aLineEditedElsewhereIsNotTicked() throws {
        let context = try context()
        let item = entry("Milk\nOat milk", [.checklistUnchecked, .checklistUnchecked], at: Date(), in: context)
        try context.save()
        // The page loaded "Eggs" at index 1, but the entry now says "Oat milk" there.
        #expect(!OpenChecklistItems.setChecked(true, line: .init(index: 1, text: "Eggs"), entryID: item.id, in: context))
        #expect(NoteEditorCodec.decodeTextStyleDocument(item.textStyleData)?.paragraphStyles == [.checklistUnchecked, .checklistUnchecked])
        // A line that is no longer a checklist item is left alone too.
        item.textStyleData = styles([.checklistUnchecked, .body])
        try context.save()
        #expect(!OpenChecklistItems.setChecked(true, line: .init(index: 1, text: "Oat milk"), entryID: item.id, in: context))
    }
}
