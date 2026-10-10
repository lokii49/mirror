import Testing
import SwiftData
import Foundation
@testable import mirror

/// Backlog A10 (erase leaves widget text) and A12 (saving doesn't refresh the widgets).
/// Serialized under SharedLLMState: these touch the shared app-group defaults.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct WidgetJournalSyncTests {
        private var defaults: UserDefaults? { UserDefaults(suiteName: WidgetShared.appGroupID) }

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: Entry.self, Insight.self, MoodCheckIn.self, configurations: config)
            return ModelContext(container)
        }

        private func seedWidgetKeys() {
            for key in WidgetBridge.journalDerivedKeys { defaults?.set("synthetic", forKey: key) }
            defaults?.set("deep", forKey: "widget.tier")
        }

        @Test func clearRemovesEveryJournalDerivedKeyButKeepsSettings() {
            seedWidgetKeys()
            WidgetBridge.clearJournalDerived()
            for key in WidgetBridge.journalDerivedKeys {
                #expect(defaults?.object(forKey: key) == nil, "\(key)")
            }
            #expect(defaults?.string(forKey: "widget.tier") == "deep")
        }

        @Test func emptyJournalClearsTheWidgets() throws {
            let context = try makeContext()
            seedWidgetKeys()
            WidgetBridge.clearIfJournalEmpty(context: context)
            #expect(defaults?.object(forKey: "widget.nudge.text") == nil)
            #expect(defaults?.object(forKey: WidgetShared.digestThemeKey) == nil)
        }

        /// A check-ins-only journal: the empty-journal clear must leave its mood map.
        @Test func checkInsOnlyJournalKeepsItsMoodMap() throws {
            let context = try makeContext()
            context.insert(MoodCheckIn(mood: "Content"))
            try context.save()
            seedWidgetKeys()
            mirrorApp.updateWidgetHeatmaps(context: context)
            WidgetBridge.clearIfJournalEmpty(context: context)
            #expect(defaults?.object(forKey: "widget.mood.heatmap") != nil)
            #expect(defaults?.object(forKey: "widget.nudge.text") == nil, "the reflection text still goes")
            WidgetBridge.clearJournalDerived()
        }

        @Test func aJournalWithAnythingInItKeepsTheWidgets() throws {
            let context = try makeContext()
            context.insert(Entry(text: "A synthetic entry from yesterday."))
            try context.save()
            seedWidgetKeys()
            WidgetBridge.clearIfJournalEmpty(context: context)
            #expect(defaults?.string(forKey: "widget.nudge.text") == "synthetic")
            WidgetBridge.clearJournalDerived()
        }

        @Test func onlyEntryAndCheckInSavesRefreshTheWidgets() throws {
            let context = try makeContext()
            let entry = Entry(text: "Synthetic.")
            let insight = Insight(type: .weeklyDigest, content: "x", periodIdentifier: "2026-W41", generatedByEngine: .gemma)
            let checkIn = MoodCheckIn(mood: "Content")
            context.insert(entry); context.insert(insight); context.insert(checkIn)
            try context.save()
            func info(_ key: ModelContext.NotificationKey, _ ids: [PersistentIdentifier]) -> [AnyHashable: Any] {
                [key.rawValue: ids]
            }
            #expect(WidgetSaveRefresher.touchesJournal(info(.insertedIdentifiers, [entry.persistentModelID])))
            #expect(WidgetSaveRefresher.touchesJournal(info(.deletedIdentifiers, [entry.persistentModelID])))
            #expect(WidgetSaveRefresher.touchesJournal(info(.updatedIdentifiers, [checkIn.persistentModelID])))
            #expect(!WidgetSaveRefresher.touchesJournal(info(.insertedIdentifiers, [insight.persistentModelID])))
            #expect(!WidgetSaveRefresher.touchesJournal(nil))
        }
    }
}
