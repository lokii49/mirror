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
            #expect(!prompts.contains { $0.contains("informally") })
        }

        // Foundation Models picked its own register: vous/вы on Apple Intelligence phones while
        // the fixed Gemma text says tu/ты. The line is Foundation Models-only: Gemma's copy of a
        // shared prompt must not carry it (it made Gemma append ", tu ?" to French questions).
        @Test(arguments: [
            ("fr", "Aujourd'hui, la présentation chez le client a encore été repoussée à jeudi, et le soir je suis allé marcher au bord du lac avec le chien.", #""tu", never "vous""#),
            ("ru", "Сегодня презентацию у клиента опять перенесли на четверг, а вечером я гулял с собакой у озера и наконец немного отдохнул.", #""ты", never "вы""#),
        ])
        func frenchAndRussian_pinTheInformalRegister(code: String, text: String, register: String) async throws {
            let prompts = await capturedSystemPrompts(for: [Entry(text: text, mood: "Content")])
            #expect(!prompts.isEmpty, "\(code)")
            #expect(prompts.allSatisfy { $0.contains(register) }, "\(code)")

            var followUp: (system: String, plan: LocalLLMService.GemmaPlan)?
            LocalLLMService.generateInterceptForTesting = { system, _, _, plan in
                followUp = (system, plan)
                return ("?", .foundationModels)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            _ = try? await InsightService.generateFollowUp(currentText: text)
            let captured = try #require(followUp, "\(code)")
            #expect(captured.system.contains(register), "\(code)")
            guard case .ownSystemPrompt(let gemmaSystem) = captured.plan else {
                Issue.record("\(code): expected Gemma to get its own system prompt, got \(captured.plan)")
                return
            }
            #expect(!gemmaSystem.contains("informally"), "\(code)")
            #expect(gemmaSystem.contains("Respond only in"), "\(code): the language line itself stays")
        }

        @Test func germanFollowUp_keepsTheSharedPrompt() async throws {
            var plan: LocalLLMService.GemmaPlan?
            LocalLLMService.generateInterceptForTesting = { _, _, _, p in
                plan = p
                return ("?", .foundationModels)
            }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            _ = try? await InsightService.generateFollowUp(currentText: "Heute war ein langer Tag im Büro, aber am Abend bin ich mit meiner Schwester spazieren gegangen.")
            guard case .samePrompt = try #require(plan) else { Issue.record("expected .samePrompt for German"); return }
        }
    }
}
