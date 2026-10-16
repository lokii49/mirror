import Testing
import Foundation
@testable import mirror

// The person's own sentences under a Foundation Models Ask answer (tools/llmrig/fm/RUBRIC_FM.md, round 21).
// Synthetic text only.
@Suite("Ask evidence quotes")
struct AskEvidenceQuotesTests {
    private func entry(_ text: String, daysAgo: Double) -> Entry {
        let e = Entry(text: text, mood: "Peaceful")
        e.createdAt = Date().addingTimeInterval(-daysAgo * 86_400)
        return e
    }

    @Test func aVerbatimPickIsShownWithItsDate() async throws {
        let call = entry("Called Mom tonight. She sounded calmer than me about the whole thing.", daysAgo: 2)
        let text = try #require(await InsightService.askEvidenceQuotes(
            answer: "Your mom sounded calm.", askMessage: "", pool: [entry("Long day at work.", daysAgo: 1), call], languageCode: "en"
        ) { ["She sounded calmer than me about the whole thing.", ""] })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        #expect(text == "The closest things you've written: On \(formatter.string(from: call.createdAt)), you wrote, \"She sounded calmer than me about the whole thing.\"")
    }

    @Test func aParaphraseIsNotShown() async {
        let pool = [entry("Called Mom tonight. She sounded calmer than me about the whole thing.", daysAgo: 2)]
        let text = await InsightService.askEvidenceQuotes(answer: "x", askMessage: "", pool: pool, languageCode: "en") {
            ["You mentioned your mom sounded calmer than you.", "The rain kept you inside."]
        }
        #expect(text == nil)
    }

    @Test func theSameSentenceIsShownOnce() async throws {
        let pool = [entry("Packed eleven boxes of books today. Probably selling the couch.", daysAgo: 1)]
        let text = try #require(await InsightService.askEvidenceQuotes(answer: "x", askMessage: "", pool: pool, languageCode: "en") {
            ["Packed eleven boxes of books today.", "packed eleven boxes of books today"]
        })
        #expect(text.components(separatedBy: "you wrote,").count == 2)
    }

    @Test func otherGroundedLanguagesUseTheirOwnAskLines() async throws {
        let pool = [entry("Ich habe heute zwölf Kisten gepackt. Wahrscheinlich verkaufen wir das Sofa.", daysAgo: 1)]
        let text = try #require(await InsightService.askEvidenceQuotes(answer: "x", askMessage: "", pool: pool, languageCode: "de") {
            ["ich habe heute zwölf Kisten gepackt", ""]
        })
        let loc = try #require(InsightService.groundedLocales["de"])
        #expect(text.hasPrefix(loc.askPrefix))
        #expect(text.contains(loc.open + "Ich habe heute zwölf Kisten gepackt." + loc.close))
    }

    @Test func aLanguageWithoutAskLinesGetsNoQuotes() async {
        let pool = [entry("Vandaag twaalf dozen ingepakt.", daysAgo: 1)]
        let text = await InsightService.askEvidenceQuotes(answer: "x", askMessage: "", pool: pool, languageCode: "nl") {
            ["Vandaag twaalf dozen ingepakt.", ""]
        }
        #expect(text == nil)
    }

    @Test func aFailedPickLeavesTheAnswerAlone() async {
        let pool = [entry("Called Mom tonight.", daysAgo: 1)]
        let text = await InsightService.askEvidenceQuotes(answer: "x", askMessage: "", pool: pool, languageCode: "en") {
            throw LocalLLMError.emptyResponse
        }
        #expect(text == nil)
    }
}

// Real Foundation Models, end to end through InsightService.ask. Skipped unless HARNESS_REAL_FM is set.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct RealFMAskTests {
        @Test func realFoundationModelsAskKeepsTheAnswerAndAddsTheirSentences() async throws {
            guard ProcessInfo.processInfo.environment["HARNESS_REAL_FM"] != nil, LocalLLMService.prefersFoundationModels else { return }
            let pool = try #require(GroundingSampleHarness.digestRigMonths.first { $0.label == "mo_caregiver_hard" }?.entries)
            var out: [String] = []
            for question in ["How is my mom doing?", "Have I been sleeping well?", "Did I go on any trips?"] {
                let (text, engine) = try await InsightService.ask(question: question, entries: pool)
                #expect(engine == .foundationModels)
                let all = pool.map(\.text).joined(separator: "\n")
                if let range = text.range(of: "The closest things you've written: ") {
                    for part in text[range.upperBound...].components(separatedBy: "you wrote, \"").dropFirst() {
                        let quote = part.components(separatedBy: "\"")[0]
                        #expect(all.contains(quote), "quote not in the journal: \(quote)")
                    }
                }
                out.append("Q: \(question)\n\(text)")
            }
            print("[realfm-ask]\n" + out.joined(separator: "\n---\n"))
        }
    }
}
