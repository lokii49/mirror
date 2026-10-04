#if DEBUG
import Foundation
import SwiftData

/// DEBUG `--seedCloudKitSchema`: makes CloudKit's Development environment learn the `CD_JournalErasure`
/// record type without running "Delete Everything". Inserts two erase markers holding only random UUIDs
/// (never real entry IDs): a small one, which creates the scalar fields, and one over 1 MB, which makes
/// NSPersistentCloudKitContainer store the blob as an asset and so creates the `_ckAsset` companion
/// fields too. Once they've exported, Deploy Schema Changes in CloudKit Console copies them to
/// Production. Run on a simulator signed into iCloud: a development build syncs to the Development
/// environment, so it must not run against a store that holds real data. The markers are harmless:
/// restore only skips the IDs they list, and these match no entry.
enum CloudKitSchemaSeed {
    static var isRequested: Bool { CommandLine.arguments.contains("--seedCloudKitSchema") }

    @MainActor
    static func run(context: ModelContext) {
        let small = JournalErasure(erasedEntryIDs: [UUID()], erasedCheckInIDs: [UUID()])
        let big = (0..<70_000).map { _ in UUID() }   // 70,000 × 16 bytes ≈ 1.1 MB
        let large = JournalErasure(erasedEntryIDs: big, erasedCheckInIDs: big)
        context.insert(small)
        context.insert(large)
        try? context.save()
        NSLog("CloudKitSchemaSeed: inserted 2 JournalErasure markers; keep the app open ~2 minutes so they export")
    }
}
#endif
