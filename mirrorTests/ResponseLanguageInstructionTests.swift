import Testing
import Foundation
@testable import mirror

// Regression for the contradictory language line (2026-09-26): an English target used to append
// "Respond only in English. Do not use English unless quoting the user's own words." to every
// system prompt. Captured through LocalLLMService.generateInterceptForTesting, so this checks the
// exact string a model would receive, and no model runs.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct ResponseLanguageInstructionTests {

        private func capturedSystemPrompts(for entries: [Entry]) async -> [String] {
            var captured: [String] = []
            LocalLLMService.generateInterceptForTesting = { system, _, _, _ in
                captured.append(system)
                return ("You wrote about the long walk home after the late shift.", .gemma)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            _ = try? await InsightService.generateNudge(entries: entries)
            return captured
        }

        @Test func englishEntries_getNoContradictoryLanguageLine() async {
            let entries = [
                Entry(text: "Long walk home after the late shift, the streets were quiet and I felt calm for once.", mood: "Peaceful"),
            ]
            let prompts = await capturedSystemPrompts(for: entries)
            #expect(!prompts.isEmpty)
            for prompt in prompts {
                #expect(!prompt.contains("Do not use English"))
            }
        }

        @Test func germanEntries_stillGetTheirLanguageInstruction() async {
            let entries = [
                Entry(text: "Heute war ein langer Tag im Büro, aber am Abend bin ich mit meiner Schwester spazieren gegangen und habe mich endlich entspannt.", mood: "Content"),
            ]
            let prompts = await capturedSystemPrompts(for: entries)
            #expect(!prompts.isEmpty)
            #expect(prompts.allSatisfy { $0.contains("Respond only in German") })
        }
    }
}
