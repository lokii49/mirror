import Foundation
import SwiftData

/// Settings > Delete Everything. Static so it can be tested without the view.
enum JournalErase {
    @MainActor
    static func eraseEverything(context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let checkIns = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        // Entries in Recently Deleted are still in other devices' backups.
        let trashed = (try? context.fetch(FetchDescriptor<TrashedEntry>())) ?? []
        // Synced marker so other devices' on-device backups never offer these back. Saved
        // on its own, before the deletes: exports follow save order, so another device
        // gets the marker before (or with) the deletes and never offers them back.
        if !entries.isEmpty || !checkIns.isEmpty || !trashed.isEmpty {
            let entryIDs = Array(Set(entries.map(\.id) + trashed.map(\.entryID)))
            context.insert(JournalErasure(erasedEntryIDs: entryIDs, erasedCheckInIDs: checkIns.map(\.id)))
            try? context.save()
        }
        entries.forEach { context.delete($0) }
        checkIns.forEach { context.delete($0) }
        if let all = try? context.fetch(FetchDescriptor<Insight>()) {
            all.forEach { context.delete($0) }
        }
        // Collection names and saved searches are journal data too.
        (try? context.fetch(FetchDescriptor<JournalCollection>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<SavedEntryView>()))?.forEach { context.delete($0) }
        trashed.forEach { context.delete($0) }
        try? context.save()
        MoodCheckInMigration.eraseLegacyRecords()
        JournalSafety.shared.journalWasErased()
        // An unsaved Write draft is journal text too.
        WriteView.eraseAllDraftStorage()
        // So is what the widgets and lock screen show (backlog A10).
        WidgetBridge.clearJournalDerived()
        // And the lock-screen reminder, which can quote a line of today's reflection.
        Task { await NotificationService.dropNudgePreview() }
    }
}
