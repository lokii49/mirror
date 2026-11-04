import Testing
import SwiftData
import Foundation
@testable import mirror

/// The journal change counter the list, Insights, Mood Timeline and calendar caches key on.
/// Synthetic text only.
@Suite("Journal revision")
@MainActor
struct JournalRevisionTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Entry.self, Insight.self, MoodCheckIn.self, configurations: config)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @Test func aSaveThatChangesSomethingBumpsIt() throws {
        let revision = JournalRevision()
        revision.start()
        let context = try makeContext()
        let before = revision.value
        context.insert(Entry(text: "A synthetic note.", mood: "Content"))
        try context.save()
        #expect(revision.value > before)
    }

    @Test func anEditToAnExistingEntryBumpsIt() throws {
        let revision = JournalRevision()
        revision.start()
        let context = try makeContext()
        let entry = Entry(text: "A synthetic note.", mood: "Content")
        context.insert(entry)
        try context.save()
        let before = revision.value
        entry.mood = "Anxious"
        try context.save()
        #expect(revision.value > before)
    }

    @Test func anEmptySaveIsNotAChange() {
        #expect(!JournalRevision.changedSomething(nil))
        #expect(!JournalRevision.changedSomething([ModelContext.NotificationKey.updatedIdentifiers.rawValue: [PersistentIdentifier]()]))
    }

    @Test func aBumpIsFollowedByOneMoreAfterMergesSettle() async throws {
        let revision = JournalRevision()
        revision.bump()
        let first = revision.value
        try await Task.sleep(for: .milliseconds(700))
        #expect(revision.value == first + 1)
    }

    @Test func cacheKeysDifferWhenOnlyTheRevisionMoves() {
        let a = JournalCacheKey(entries: 3, checkIns: 1, revision: 4)
        let b = JournalCacheKey(entries: 3, checkIns: 1, revision: 5)
        #expect(a != b)
    }
}
