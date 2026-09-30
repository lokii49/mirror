import Testing
import SwiftData
import Foundation
@testable import mirror

// The mood race (2026-09-28): saving started mood detection fire-and-forget and, a moment later,
// the daily reflection, whose plan reads the entry's mood as it's built, so a save-triggered
// reflection usually saw none. MoodAutoDetector shares one detection per entry, the save path
// awaits it, and runDailyNudgeIfNeeded fills its source entries' moods first. Model calls go
// through LocalLLMService.generateInterceptForTesting.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct MoodAutoDetectorTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: Entry.self, Insight.self, configurations: config)
            return ModelContext(container)
        }

        private func entry(_ text: String, mood: String?, at date: Date, in context: ModelContext) -> Entry {
            let e = Entry(text: text, mood: mood)
            e.createdAt = date
            context.insert(e)
            return e
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func twoRequestsForOneEntry_shareOneDetection() async throws {
            let context = try makeContext()
            let e = entry("Could not sleep, kept going over the interview questions until three.", mood: nil, at: Date(), in: context)
            var emotionCalls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, task, _ in
                if task == .emotion { emotionCalls += 1 }
                return ("Anxious", .gemma)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let first = MoodAutoDetector.shared.detectIfNeeded(e, context: context)
            let second = MoodAutoDetector.shared.detectIfNeeded(e, context: context)
            #expect(first != nil && second != nil)
            #expect(await first?.value == true)
            _ = await second?.value
            #expect(emotionCalls == 1)
            #expect(e.mood == "Anxious")
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func aMoodPickedWhileDetectionRuns_isKept() async throws {
            let context = try makeContext()
            let e = entry("Could not sleep, kept going over the interview questions until three.", mood: nil, at: Date(), in: context)
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in ("Anxious", .gemma) }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let detection = MoodAutoDetector.shared.detectIfNeeded(e, context: context)
            e.mood = "Hopeful"
            #expect(await detection?.value == false)
            #expect(e.mood == "Hopeful")
        }

        @Test func nothingToDo_returnsNil() throws {
            let context = try makeContext()
            let withMood = entry("A calm morning with coffee on the balcony before work.", mood: "Content", at: Date(), in: context)
            let empty = entry("   ", mood: nil, at: Date(), in: context)
            #expect(MoodAutoDetector.shared.detectIfNeeded(withMood, context: context) == nil)
            #expect(MoodAutoDetector.shared.detectIfNeeded(empty, context: context) == nil)
        }

        /// Three English entries, the newest (today) without a mood.
        private func seed(_ context: ModelContext) throws -> Entry {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            _ = entry("Long walk around the lake with Bruno after work, the light was gold on the water.", mood: "Content", at: startOfToday.addingTimeInterval(-6 * 3_600), in: context)
            _ = entry("Finally fixed the dashboard bug with Omar, it was in the date parsing all along.", mood: "Hopeful", at: startOfToday.addingTimeInterval(-5 * 3_600), in: context)
            let today = entry("Could not sleep, kept going over the interview questions until three in the morning.", mood: nil, at: startOfToday.addingTimeInterval(1), in: context)
            try context.save()
            return today
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func dailyReflection_readsTheMood_detectedBeforeItsPlanIsBuilt() async throws {
            UserDefaults.standard.removeObject(forKey: mirrorApp.extraReflectionFailedAttemptKey)
            let context = try makeContext()
            let today = try seed(context)
            var calls: [LocalLLMTask] = []
            var nudgeMessage: String?
            LocalLLMService.generateInterceptForTesting = { _, user, task, plan in
                calls.append(task)
                if task == .emotion { return ("Anxious", .gemma) }
                if case .grammarConstrained(let message, _) = plan { nudgeMessage = message } else { nudgeMessage = user }
                return ("not grounded", .gemma)   // the reflection's outcome isn't the point here
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(today.mood == "Anxious")
            #expect(calls.first == .emotion, "mood detection runs before the reflection: \(calls)")
            #expect(nudgeMessage?.contains("Mood: Anxious") == true)
        }

        @Test(.enabled(if: LocalLLMService.isModelAvailable))
        func dailyReflection_joinsASaveTimeDetection_insteadOfRunningASecond() async throws {
            UserDefaults.standard.removeObject(forKey: mirrorApp.extraReflectionFailedAttemptKey)
            let context = try makeContext()
            let today = try seed(context)
            var emotionCalls = 0
            var nudgeMessage: String?
            LocalLLMService.generateInterceptForTesting = { _, user, task, plan in
                if task == .emotion { emotionCalls += 1; return ("Anxious", .gemma) }
                if case .grammarConstrained(let message, _) = plan { nudgeMessage = message } else { nudgeMessage = user }
                return ("not grounded", .gemma)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let saveTime = MoodAutoDetector.shared.detectIfNeeded(today, context: context)   // as WriteView's save does
            #expect(saveTime != nil)
            await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
            #expect(emotionCalls == 1)
            #expect(nudgeMessage?.contains("Mood: Anxious") == true)
        }
    }
}
