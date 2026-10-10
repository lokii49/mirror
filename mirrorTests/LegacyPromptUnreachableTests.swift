import Testing
import Foundation
@testable import mirror

// Backlog A9: `DAILY_NUDGE_LEGACY_SYSTEM` (free prose, ~0/40 faithful on Gemma) must never be sent.
// It was reachable when the entries were too short for language detection and the device language
// was one the app has no grounded reflection for. Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct LegacyPromptUnreachableTests {
        /// Each under 20 characters, so language detection skips them.
        private func shortEntries() -> [Entry] {
            let now = Date()
            return ["Long day at work.", "Ran by the river.", "Dinner with Sam."].enumerated().map { i, text in
                let e = Entry(text: text, mood: "Content")
                e.createdAt = now.addingTimeInterval(Double(-i) * 600)
                return e
            }
        }

        @Test(arguments: ["nl", "sv", "tr"])
        func unsupportedDeviceLanguageWithUndetectableEntries_neverSendsTheLegacyPrompt(language: String) async throws {
            var freeProseLegacyCalls = 0
            LocalLLMService.generateInterceptForTesting = { system, _, _, plan in
                if case .samePrompt = plan, system.contains(DAILY_NUDGE_LEGACY_SYSTEM) { freeProseLegacyCalls += 1 }
                return ("The rain outside feels heavy tonight, doesn't it?", .foundationModels)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }

            let entries = shortEntries()
            let result = try await InsightService.$deviceLanguageForTesting.withValue(language) {
                try await InsightService.generateNudge(entries: entries)
            }
            #expect(freeProseLegacyCalls == 0)
            #expect(InsightService.isUngroundedFallback(result.text))
        }

        @Test func englishDeviceWithUndetectableEntries_stillGetsTheGroundedPath() async throws {
            var legacy = 0
            LocalLLMService.generateInterceptForTesting = { system, _, _, plan in
                if case .samePrompt = plan, system.contains(DAILY_NUDGE_LEGACY_SYSTEM) { legacy += 1 }
                return ("not grounded", .gemma)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let entries = shortEntries()
            _ = try? await InsightService.$deviceLanguageForTesting.withValue("en") {
                try await InsightService.generateNudge(entries: entries)
            }
            #expect(legacy == 0)
        }
    }
}
