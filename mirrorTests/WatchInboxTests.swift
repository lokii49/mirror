import Foundation
import SwiftData
import Testing
@testable import mirror

/// What the Apple Watch app sends, saved on the iPhone. Synthetic text only.
@Suite("Watch inbox")
@MainActor
struct WatchInboxTests {
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    private func context() throws -> ModelContext {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        containers.all.append(container)
        container.mainContext.autosaveEnabled = false
        return container.mainContext
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "WatchInboxTests.\(UUID().uuidString)")! }

    @Test func payloadsParseAndBadOnesAreDropped() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)   // May 2026, in the past
        let mood = WatchInbox.item(from: ["id": "a", "kind": "mood", "value": "Grateful", "date": date.timeIntervalSince1970])
        #expect(mood == .init(id: "a", kind: .mood, value: "Grateful", date: date))
        #expect(WatchInbox.item(from: ["id": "b", "kind": "mood", "value": "Ecstatic", "date": 0.0]) == nil, "unknown mood")
        #expect(WatchInbox.item(from: ["id": "c", "kind": "note", "value": "   ", "date": 0.0]) == nil, "blank note")
        #expect(WatchInbox.item(from: ["kind": "note", "value": "x", "date": 0.0]) == nil, "no id")
        #expect(WatchInbox.item(from: ["id": "d", "kind": "photo", "value": "x", "date": 0.0]) == nil, "unknown kind")
        let future = WatchInbox.item(from: ["id": "e", "kind": "note", "value": "x", "date": Date().addingTimeInterval(86_400).timeIntervalSince1970])
        #expect((future?.date ?? .distantFuture) <= Date(), "never dated in the future")
    }

    @Test func aMoodBecomesACheckInAndANoteAnEntry() throws {
        let context = try context()
        let d = defaults()
        let when = Date().addingTimeInterval(-3_600)
        #expect(WatchInbox.save(.init(id: "m2", kind: .mood, value: "Grateful", date: when), in: context, defaults: d))
        #expect(WatchInbox.save(.init(id: "n1", kind: .note, value: "Synthetic note from the watch.", date: when), in: context, defaults: d))
        let checkIns = try context.fetch(FetchDescriptor<MoodCheckIn>())
        #expect(checkIns.contains { $0.decryptedMood == "Grateful" && abs($0.createdAt.timeIntervalSince(when)) < 1 })
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        #expect(entries.first?.text == "Synthetic note from the watch.")
        #expect(entries.first?.collectionID == nil, "Unfiled")
    }

    @Test func aRepeatDeliveryIsSavedOnce() throws {
        let context = try context()
        let d = defaults()
        let item = WatchInbox.Item(id: "same", kind: .note, value: "Synthetic once.", date: Date())
        #expect(WatchInbox.save(item, in: context, defaults: d))
        #expect(WatchInbox.save(item, in: context, defaults: d))
        #expect(try context.fetch(FetchDescriptor<Entry>()).count == 1)
    }
}
