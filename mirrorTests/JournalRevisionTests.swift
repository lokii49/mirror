import Testing
import SwiftData
import Foundation
@testable import mirror

/// The journal change counter the list, Insights, Mood Timeline and calendar caches key on.
/// Synthetic text only.
@Suite("Journal revision")
@MainActor
struct JournalRevisionTests {
    /// A store whose main context stands in for the app's. Keep the container alive for the whole
    /// test: `mainContext` doesn't retain it, and SwiftData traps once it's gone.
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Entry.self, Insight.self, MoodCheckIn.self, configurations: config)
        container.mainContext.autosaveEnabled = false
        return container
    }

    @Test func aSaveThatChangesSomethingBumpsIt() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let revision = JournalRevision()
        revision.start(container: container)
        let before = revision.value
        context.insert(Entry(text: "A synthetic note.", mood: "Content"))
        try context.save()
        #expect(revision.value > before)
    }

    @Test func anEditToAnExistingEntryBumpsIt() throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let revision = JournalRevision()
        revision.start(container: container)
        let entry = Entry(text: "A synthetic note.", mood: "Content")
        context.insert(entry)
        try context.save()
        let before = revision.value
        entry.mood = "Anxious"
        try context.save()
        #expect(revision.value > before)
    }

    @Test func savesToAnotherStoreAreIgnored() throws {
        let mine = try makeContainer()
        let otherStore = try makeContainer()
        defer { withExtendedLifetime((mine, otherStore)) {} }
        let other = otherStore.mainContext
        let revision = JournalRevision()
        revision.start(container: mine)
        other.insert(Entry(text: "A synthetic note in another store."))
        try other.save()
        #expect(revision.value == 0)
    }

    @Test func anEmptySaveIsNotAChange() {
        #expect(!JournalRevision.changedSomething(nil))
        #expect(!JournalRevision.changedSomething([ModelContext.NotificationKey.updatedIdentifiers.rawValue: [PersistentIdentifier]()]))
    }

    /// Waits for the delayed settle bump (~400 ms) instead of a fixed sleep: on a busy CI
    /// simulator the main actor can run it well after a second.
    private func waitForChange(_ revision: JournalRevision, from value: Int) async {
        for _ in 0..<100 where revision.value == value { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func aBumpIsFollowedByOneMoreAfterMergesSettle() async throws {
        let revision = JournalRevision()
        revision.bump()
        let first = revision.value
        await waitForChange(revision, from: first)
        #expect(revision.value == first + 1)
    }

    @Test func cacheKeysDifferWhenOnlyTheRevisionMoves() {
        let a = JournalCacheKey(entries: 3, checkIns: 1, revision: 4)
        let b = JournalCacheKey(entries: 3, checkIns: 1, revision: 5)
        #expect(a != b)
    }

    @Test func aMainContextSaveGetsNoSecondBump() async throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let context = container.mainContext
        let revision = JournalRevision()
        revision.start(container: container)
        context.insert(Entry(text: "A synthetic note.", mood: "Content"))
        try context.save()
        let afterSave = revision.value
        try await Task.sleep(for: .seconds(1))
        #expect(revision.value == afterSave, "no settle bump for the main context's own save")
    }

    @Test func anotherContextsSaveGetsTheSecondBump() async throws {
        let container = try makeContainer()
        defer { withExtendedLifetime(container) {} }
        let other = ModelContext(container)
        let revision = JournalRevision()
        revision.start(container: container)
        other.insert(Entry(text: "A synthetic note from another context.", mood: "Content"))
        try other.save()
        let afterSave = revision.value
        await waitForChange(revision, from: afterSave)
        #expect(revision.value == afterSave + 1)
    }
}
