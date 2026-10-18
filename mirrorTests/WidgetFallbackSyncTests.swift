import Testing
import SwiftData
import Foundation
@testable import mirror

/// The widget syncs skip fallbacks, and clear text from the same period once it has only
/// fallbacks (UngroundedInsightCleanup can turn a shown digest or reflection into one).
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct WidgetFallbackSyncTests {
        private var defaults: UserDefaults? { UserDefaults(suiteName: WidgetShared.appGroupID) }

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return ModelContext(try ModelContainer(for: Entry.self, Insight.self, configurations: config))
        }

        private let realDigest = "THIS WEEK'S THEME: A synthetic week of walks.\nYOUR ENERGY: Steady."

        @Test func digestFallbackClearsThisWeeksStoredTheme() throws {
            let context = try makeContext()
            let week = DateHelpers.digestWeekIdentifier(for: Date())
            context.insert(Insight(type: .weeklyDigest, content: InsightService.weeklyDigestUngroundedFallback, periodIdentifier: week))
            try context.save()
            defaults?.set("Invented theme.", forKey: WidgetShared.digestThemeKey)
            defaults?.set(week, forKey: WidgetShared.digestWeekKey)
            WidgetBridge.syncWeeklyDigest(from: context)
            #expect(defaults?.object(forKey: WidgetShared.digestThemeKey) == nil)
        }

        @Test func aNewerFallbackDoesntHideTheRealDigest() throws {
            let context = try makeContext()
            let week = DateHelpers.digestWeekIdentifier(for: Date())
            let real = Insight(type: .weeklyDigest, content: realDigest, periodIdentifier: week)
            real.generatedAt = Date(timeIntervalSinceNow: -3_600)
            context.insert(real)
            context.insert(Insight(type: .weeklyDigest, content: InsightService.weeklyDigestUngroundedFallback, periodIdentifier: week))
            try context.save()
            defaults?.removeObject(forKey: WidgetShared.digestThemeKey)
            WidgetBridge.syncWeeklyDigest(from: context)
            #expect(defaults?.string(forKey: WidgetShared.digestThemeKey) == "A synthetic week of walks.")
            WidgetBridge.clearJournalDerived()
        }

        @Test func todaysFallbackClearsTodaysReflectionLineButNotYesterdays() throws {
            let context = try makeContext()
            let today = DateHelpers.dayIdentifier(for: Date())
            context.insert(Insight(type: .dailyNudge, content: InsightService.dailyNudgeUngroundedFallback, periodIdentifier: today))
            try context.save()

            defaults?.set("Invented line.", forKey: "widget.nudge.text")
            defaults?.set(today, forKey: "widget.nudge.date")
            mirrorApp.syncNudgeToWidget(context: context)
            #expect(defaults?.object(forKey: "widget.nudge.text") == nil)

            let yesterday = DateHelpers.dayIdentifier(for: Date(timeIntervalSinceNow: -86_400))
            defaults?.set("Yesterday's line.", forKey: "widget.nudge.text")
            defaults?.set(yesterday, forKey: "widget.nudge.date")
            mirrorApp.syncNudgeToWidget(context: context)
            #expect(defaults?.string(forKey: "widget.nudge.text") == "Yesterday's line.")
            WidgetBridge.clearJournalDerived()
        }
    }
}
