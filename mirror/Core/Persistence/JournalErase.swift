import Foundation
import SwiftData

/// Settings > Delete Everything. Static so it can be tested without the view.
enum JournalErase {
    @MainActor
    static func eraseEverything(context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let checkIns = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        // Synced marker so other devices' on-device backups never offer these back. Saved
        // on its own, before the deletes: exports follow save order, so another device
        // gets the marker before (or with) the deletes and never offers them back.
        if !entries.isEmpty || !checkIns.isEmpty {
            context.insert(JournalErasure(erasedEntryIDs: entries.map(\.id), erasedCheckInIDs: checkIns.map(\.id)))
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
        try? context.save()
        MoodCheckInMigration.eraseLegacyRecords()
        JournalSafety.shared.journalWasErased()
        // An unsaved Write draft is journal text too.
        WriteView.eraseAllDraftStorage()
        // So is what the widgets and lock screen show (backlog A10).
        WidgetBridge.clearJournalDerived()
    }
}
