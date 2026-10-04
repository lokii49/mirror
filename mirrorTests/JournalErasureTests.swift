import Testing
import Foundation
import SwiftData
@testable import mirror

@Suite("JournalErasure")
struct JournalErasureTests {
    @Test func idsRoundTripThroughStorage() {
        let ids = (0..<500).map { _ in UUID() }
        let erasure = JournalErasure(erasedEntryIDs: ids)
        #expect(erasure.erasedEntryIDsStorage?.count == 500 * 16)
        #expect(erasure.erasedEntryIDs == Set(ids))
    }

    @Test @MainActor func checkInIDsAreRecordedSeparately() throws {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let entry = UUID(), checkIn = UUID()
        container.mainContext.insert(JournalErasure(erasedEntryIDs: [entry], erasedCheckInIDs: [checkIn]))
        try container.mainContext.save()
        #expect(JournalErasure.allErasedEntryIDs(in: container.mainContext) == [entry])
        #expect(JournalErasure.allErasedCheckInIDs(in: container.mainContext) == [checkIn])
    }

    @Test func emptyOrTruncatedStorageDecodesSafely() {
        #expect(JournalErasure.decode(nil).isEmpty)
        #expect(JournalErasure.decode(Data(repeating: 1, count: 15)).isEmpty)
        let one = UUID()
        var data = JournalErasure.encode([one])
        data.append(contentsOf: [0, 1, 2])   // partial trailing UUID is ignored
        #expect(JournalErasure.decode(data) == [one])
    }

    @Test @MainActor func erasedIDsUnionAcrossDevices() throws {
        let config = ModelConfiguration(schema: MirrorModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: MirrorModelContainer.schema, configurations: [config])
        let context = container.mainContext
        let a = [UUID(), UUID()], b = [UUID()]
        context.insert(JournalErasure(erasedEntryIDs: a))
        context.insert(JournalErasure(erasedEntryIDs: b))   // e.g. synced from another device
        try context.save()
        #expect(JournalErasure.allErasedEntryIDs(in: context) == Set(a + b))
    }
}
