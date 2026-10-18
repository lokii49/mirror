import Testing
import SwiftData
import Foundation
@testable import mirror

/// The background passes' cheap gates (backlog E test gaps): the monthly report's tier, last-week
/// and minimum-entry gate, and the mood alert's threshold, tier and 24h cooldown. No model runs.
/// Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct BackgroundGateTests {
        private static let cooldownKey = "mirror.lastMoodAlertSent"

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return ModelContext(try ModelContainer(for: Entry.self, Insight.self, MoodCheckIn.self, configurations: config))
        }

        private func withTier<T>(_ tier: SubscriptionTier, _ body: () async throws -> T) async rethrows -> T {
            let before = SubscriptionService.shared.tier
            SubscriptionService.shared.debugSetTier(tier)
            defer { SubscriptionService.shared.debugSetTier(before) }
            return try await body()
        }

        private static func day(_ d: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))!
        }

        // MARK: - Monthly report
        // `runMonthlyReportIfNeeded` also stops at the model and encryption checks, so a test of the
        // whole pass can't tell whether these gates held. They're checked on the pure gate.

        @Test func reportWaitsForTheLastWeekOfTheMonth() {
            #expect(!mirrorApp.monthlyReportIsDue(now: Self.day(24), monthEntryCount: 12, isDeep: true))
            #expect(mirrorApp.monthlyReportIsDue(now: Self.day(25), monthEntryCount: 12, isDeep: true))
            #expect(mirrorApp.monthlyReportIsDue(now: Self.day(31), monthEntryCount: 12, isDeep: true))
        }

        @Test func reportNeedsTheMinimumEntries() {
            let minimum = InsightService.monthlyReportMinimumEntries
            #expect(!mirrorApp.monthlyReportIsDue(now: Self.day(28), monthEntryCount: minimum - 1, isDeep: true))
            #expect(mirrorApp.monthlyReportIsDue(now: Self.day(28), monthEntryCount: minimum, isDeep: true))
        }

        @Test func reportNeedsDeep() {
            #expect(!mirrorApp.monthlyReportIsDue(now: Self.day(28), monthEntryCount: 12, isDeep: false))
        }

        // MARK: - Mood alert

        private func addMoods(_ moods: [String], to context: ModelContext) {
            for (daysAgo, mood) in moods.enumerated() {
                let e = Entry(text: "Synthetic.", mood: mood)
                e.createdAt = Date().addingTimeInterval(Double(-daysAgo) * 86_400 - 60)
                context.insert(e)
            }
            try? context.save()
        }

        /// Runs the check with the cooldown key set to `lastSent`, returns the key afterwards,
        /// and restores whatever the host had.
        private func alertCooldown(after lastSent: Date?, _ context: ModelContext) async -> Date? {
            let defaults = UserDefaults.standard
            let saved = defaults.object(forKey: Self.cooldownKey)
            defer { defaults.set(saved, forKey: Self.cooldownKey) }
            defaults.set(lastSent, forKey: Self.cooldownKey)
            await mirrorApp.checkMoodAlertIfNeeded(context: context)
            return defaults.object(forKey: Self.cooldownKey) as? Date
        }

        @Test func threeLowDaysSendAnAlert() async throws {
            let context = try makeContext()
            addMoods(["Anxious", "Sad", "Drained"], to: context)
            let start = Date()
            let sent = await withTier(.deep) { await alertCooldown(after: nil, context) }
            #expect((sent ?? .distantPast) >= start)
        }

        @Test func twoLowDaysDontAlert() async throws {
            let context = try makeContext()
            addMoods(["Anxious", "Sad", "Content"], to: context)
            let sent = await withTier(.deep) { await alertCooldown(after: nil, context) }
            #expect(sent == nil)
        }

        @Test func alertsNeedDeep() async throws {
            let context = try makeContext()
            addMoods(["Anxious", "Sad", "Drained"], to: context)
            let sent = await withTier(.core) { await alertCooldown(after: nil, context) }
            #expect(sent == nil)
        }

        @Test func atMostOneAlertPerDay() async throws {
            let context = try makeContext()
            addMoods(["Anxious", "Sad", "Drained"], to: context)
            let earlier = Date().addingTimeInterval(-3_600)
            let sent = await withTier(.deep) { await alertCooldown(after: earlier, context) }
            #expect(sent == earlier)
        }
    }
}
