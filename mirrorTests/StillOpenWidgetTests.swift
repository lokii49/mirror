import Foundation
import SwiftData
import Testing
@testable import mirror

/// The Still Open widget's snapshot and its queued ticks. Synthetic text only; each test uses its
/// own UserDefaults suite, never the app group.
@Suite("Still Open widget")
@MainActor
struct StillOpenWidgetTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func defaults() -> UserDefaults {
        let name = "StillOpenWidgetTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func entry(_ text: String, _ list: [NoteParagraphTextStyle], at date: Date = Date(), in context: ModelContext) -> Entry {
        let entry = Entry(text: text)
        entry.createdAt = date
        entry.textStyleData = try! JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: list, indentLevels: nil, fontChoices: nil))
        context.insert(entry)
        return entry
    }

    @Test func snapshotKeepsNewestFirstCapsAndCountsAll() {
        let older = OpenChecklistItems.Group(entryID: UUID(), createdAt: Date(timeIntervalSince1970: 0),
                                             lines: (0..<6).map { .init(index: $0, text: "Old \($0)") })
        let newer = OpenChecklistItems.Group(entryID: UUID(), createdAt: Date(),
                                             lines: (0..<5).map { .init(index: $0, text: "New \($0)") })
        let snapshot = StillOpenWidgetSync.snapshot(from: [newer, older])
        #expect(snapshot.total == 11)
        #expect(snapshot.items.count == StillOpenWidgetData.maxItems)
        #expect(snapshot.items.first?.text == "New 0")
        #expect(snapshot.items.first?.hash == StillOpenWidgetData.lineHash("New 0"))
    }

    @Test func longLinesAreClippedButHashedWhole() {
        let long = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces)
        let group = OpenChecklistItems.Group(entryID: UUID(), createdAt: Date(), lines: [.init(index: 0, text: long)])
        let item = StillOpenWidgetSync.snapshot(from: [group]).items[0]
        #expect(item.text.count <= StillOpenWidgetData.maxChars + 1)
        #expect(item.text.hasSuffix("…"))
        #expect(item.hash == StillOpenWidgetData.lineHash(long))
    }

    @Test func toggleQueuesAndUnqueues() {
        let d = defaults()
        let tick = StillOpenWidgetData.Tick(entryID: UUID(), index: 2, hash: "abc")
        StillOpenWidgetData.toggle(tick, in: d)
        #expect(StillOpenWidgetData.ticks(in: d) == [tick])
        StillOpenWidgetData.toggle(tick, in: d)
        #expect(StillOpenWidgetData.ticks(in: d).isEmpty)
        #expect(d.data(forKey: StillOpenWidgetData.ticksKey) == nil)
    }

    @Test func pendingTicksApplyOnlyToUnchangedLines() throws {
        let context = try context()
        let d = defaults()
        let item = entry("Milk\nEggs\nBread", [.checklistUnchecked, .checklistUnchecked, .checklistUnchecked], in: context)
        try context.save()
        // Eggs is still Eggs; index 2 was "Butter" when the widget drew it, the entry says Bread now.
        StillOpenWidgetData.toggle(.init(entryID: item.id, index: 1, hash: StillOpenWidgetData.lineHash("Eggs")), in: d)
        StillOpenWidgetData.toggle(.init(entryID: item.id, index: 2, hash: StillOpenWidgetData.lineHash("Butter")), in: d)
        #expect(StillOpenWidgetSync.applyPendingTicks(context: context, defaults: d) == 1)
        #expect(NoteEditorCodec.decodeTextStyleDocument(item.textStyleData)?.paragraphStyles
                == [.checklistUnchecked, .checklistChecked, .checklistUnchecked])
        #expect(StillOpenWidgetData.ticks(in: d).isEmpty, "handled once, applied or not")
        // The snapshot was rebuilt without the ticked line.
        #expect(StillOpenWidgetData.snapshot(in: d)?.items.map(\.text) == ["Milk", "Bread"])
        #expect(item.text == "Milk\nEggs\nBread", "text untouched")
    }

    @Test func syncWritesOnlyWhenSomethingChanged() throws {
        let context = try context()
        let d = defaults()
        _ = entry("Batteries", [.checklistUnchecked], in: context)
        try context.save()
        StillOpenWidgetSync.sync(context: context, force: true, defaults: d)
        let first = d.data(forKey: StillOpenWidgetData.snapshotKey)
        #expect(StillOpenWidgetData.snapshot(in: d)?.total == 1)
        #expect(!StillOpenWidgetData.write(StillOpenWidgetData.snapshot(in: d)!, in: d), "same snapshot is not rewritten")
        #expect(d.data(forKey: StillOpenWidgetData.snapshotKey) == first)
    }

    @Test func deleteEverythingClearsTheWidgetKeys() {
        #expect(WidgetBridge.journalDerivedKeys.contains(StillOpenWidgetData.snapshotKey))
        #expect(WidgetBridge.journalDerivedKeys.contains(StillOpenWidgetData.ticksKey))
    }
}
