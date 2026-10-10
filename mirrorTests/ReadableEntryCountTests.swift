import Testing
import SwiftData
import Foundation
@testable import mirror

// Backlog A11: the Insights cards counted every entry while the generators count only readable
// ones, so an entry with nothing readable (a failed voice transcription) made a card promise a
// reflection or digest that never came. Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct ReadableEntryCountTests {
        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: Entry.self, Insight.self, configurations: config)
            return ModelContext(container)
        }

        /// A voice note whose transcription failed: no text anywhere.
        private func unreadable(at date: Date) -> Entry {
            let e = Entry(text: "", source: .voice)
            e.voiceNoteData = Data([0, 0, 0, 0x20] + Array("ftypM4A ".utf8) + Array(repeating: 1, count: 40))
            e.voiceNoteTranscriptionFailed = true
            e.createdAt = date
            return e
        }

        private func readable(_ text: String, at date: Date) -> Entry {
            let e = Entry(text: text, mood: "Content")
            e.createdAt = date
            return e
        }

        @Test func nudgeStateNeedsOneMoreWhenOneOfThreeIsUnreadable() async throws {
            let context = try makeContext()
            let now = Date()
            let entries = [
                readable("Walked to the bakery before work this morning.", at: now),
                readable("Long meeting, then a quiet evening with a book.", at: now.addingTimeInterval(-3_600)),
                unreadable(at: now.addingTimeInterval(-7_200)),
            ]
            entries.forEach(context.insert)
            let viewModel = InsightViewModel()
            await viewModel.loadNudge(entries: entries, insights: [], context: context)
            guard case .needsMoreEntries(let n) = viewModel.nudgeState else {
                Issue.record("expected needsMoreEntries(1), got \(viewModel.nudgeState)"); return
            }
            #expect(n == 1)
        }

        @Test func digestCardCountsOnlyReadableEntries() async throws {
            let context = try makeContext()
            let sunday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
            let entries = [
                readable("Walked to the bakery before work this morning.", at: sunday.addingTimeInterval(-86_400)),
                readable("Long meeting, then a quiet evening with a book.", at: sunday.addingTimeInterval(-2 * 86_400)),
                unreadable(at: sunday.addingTimeInterval(-3 * 86_400)),
            ]
            entries.forEach(context.insert)
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let viewModel = InsightViewModel()
            await DateHelpers.$nowForTesting.withValue(sunday) {
                await viewModel.loadWeeklyDigest(entries: entries, insights: [], context: context)
            }
            #expect(calls == 0)
            guard case .notEnoughEntries(let n) = viewModel.digestState else {
                Issue.record("expected notEnoughEntries(1), got \(viewModel.digestState)"); return
            }
            #expect(n == 1)
        }
    }
}
