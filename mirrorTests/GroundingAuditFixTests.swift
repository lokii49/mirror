import Testing
import Foundation
@testable import mirror

// Pre-release audit fixes for 3.1.3 (S3, M4, L6-L9, L15, the 10k entry-text cap). Synthetic text only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct GroundingAuditFixTests {

        // MARK: S3 — nothing quotable: the honest card on either engine, no model

        @Test(arguments: [true, false])
        func nothingQuotableGetsTheHonestCardWithoutAModel(forceGemma: Bool) async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("A quiet week of invented rain.", .foundationModels) }
            LocalLLMService.forceGemmaForTesting = forceGemma
            defer {
                LocalLLMService.generateInterceptForTesting = nil
                LocalLLMService.forceGemmaForTesting = false
            }
            let entries = ["Tired.", "Ok day.", "Gym."].map { Entry(text: $0, mood: "Content") }
            let expectedEngine: LLMEngine = LocalLLMService.prefersFoundationModels ? .foundationModels : .gemma
            let digest = try await InsightService.$deviceLanguageForTesting.withValue("en") {
                try await InsightService.generateWeeklyDigest(weekEntries: entries, allEntries: entries)
            }
            #expect(digest.text == InsightService.weeklyDigestUngroundedFallback)
            #expect(digest.engine == expectedEngine)
            let report = try await InsightService.$deviceLanguageForTesting.withValue("en") {
                try await InsightService.generateMonthlyReport(monthEntries: entries, allEntries: entries)
            }
            #expect(report.text == InsightService.monthlyReportUngroundedFallback)
            #expect(report.engine == expectedEngine)
            #expect(calls == 0, "no free-prose digest or report runs when nothing is quotable")
        }

        // MARK: M4 — every structured attempt threw: nil, so the caller shows the retryable honest card

        private let week = [
            Entry(text: "Landlord emailed that the rent goes up in November. Spent an hour redoing the budget and it still doesn't add up.", mood: "Anxious"),
            Entry(text: "Second day at the new job. The team lead walked me through the codebase and it's less scary than I thought.", mood: "Hopeful"),
        ]

        @Test func structuredDigestWithNoDraftAtAllIsNil() async throws {
            var calls = 0
            let text = try await InsightService.structuredFMDigest(weekEntries: week, userMessage: "") {
                calls += 1
                throw LocalLLMError.emptyResponse
            }
            #expect(calls == InsightService.structuredDigestAttempts)
            #expect(text == nil)
        }

        @Test func structuredDigestWhoseDraftsFailTheChecksIsStillFilledByTheApp() async throws {
            let text = try #require(try await InsightService.structuredFMDigest(weekEntries: week, userMessage: "") {
                FMDigestGuard.Draft(
                    theme: "rain", energyQuote: "The rain kept me inside all evening long.", energyRead: "Invented.",
                    buildingQuote: "Invented sentence that nobody wrote.", buildingRead: "Invented.",
                    watchQuote: "Another invented sentence nobody wrote.", watchRead: "Invented.",
                    boost: "Watch the sunrise by the window.", nextWeek: "Light a candle by the window."
                )
            })
            #expect(text.contains(FMDigestGuard.fixedBoost))
            #expect(text.contains("You wrote, \""))
        }

        @Test func localizedDigestAndReportWithNoDraftAreNil() async throws {
            let options = [["Ich habe die ganze Nacht nicht geschlafen."], ["Lena hat mir Suppe gebracht."], ["Der Bericht ist immer noch nicht fertig."]]
            let digest = try await InsightService.structuredFMLocalizedDigest(options: options, validator: { $0 }, systemPrompt: "", userMessage: "") {
                throw LocalLLMError.emptyResponse
            }
            #expect(digest == nil)
            let report = try await InsightService.structuredFMLocalizedMonthly(options: options, validator: { $0 }, systemPrompt: "", userMessage: "") {
                throw LocalLLMError.emptyResponse
            }
            #expect(report == nil)
        }

        @Test func cancellationIsStillRethrownByTheLocalizedPaths() async {
            let options = [["Ich habe die ganze Nacht nicht geschlafen."], ["Lena hat mir Suppe gebracht."], ["Der Bericht ist immer noch nicht fertig."]]
            await #expect(throws: CancellationError.self) {
                _ = try await InsightService.structuredFMLocalizedDigest(options: options, validator: { $0 }, systemPrompt: "", userMessage: "") {
                    throw CancellationError()
                }
            }
            await #expect(throws: CancellationError.self) {
                _ = try await InsightService.structuredFMLocalizedMonthly(options: options, validator: { $0 }, systemPrompt: "", userMessage: "") {
                    throw CancellationError()
                }
            }
        }

        // MARK: L6 — one sentence is quoted in one section only

        @Test func appFilledSlotsAvoidSentencesAnotherSlotUses() {
            let a = "Walked by the lake after work.", b = "Made soup for the whole week.", c = "Called my sister for an hour."
            #expect(InsightService.filledDistinctPicks([nil, nil, nil], options: [[a, b], [a, b], [c]]) == [a, b, c])
            #expect(InsightService.filledDistinctPicks([nil, a, nil], options: [[a, b], [a, b], [a, b, c]]) == [b, a, c])
            // Nothing else to choose: the list's first sentence, as before.
            #expect(InsightService.filledDistinctPicks([nil, nil, nil], options: [[a], [a], [a]]) == [a, a, a])
        }

        @Test func structuredLocalizedDigestFillsDistinctSentences() async throws {
            let a = "Ich bin mit dem Hund am See spazieren gegangen.", b = "Zum ersten Mal diese Woche fühlte ich mich leicht."
            let text = try #require(try await InsightService.structuredFMLocalizedDigest(
                options: [[a, b], [a, b], [a, b]], validator: { $0 }, systemPrompt: "", userMessage: ""
            ) {
                FMDigestGuard.Draft(theme: "", energyQuote: "Erfunden und nirgends geschrieben.", energyRead: "", buildingQuote: "",
                                    buildingRead: "", watchQuote: "", watchRead: "", boost: "", nextWeek: "")
            })
            let lines = text.components(separatedBy: "\n")
            #expect(lines[0] != lines[1])
        }

        @Test func germanDigestWithoutAHardDayQuotesBuildingAndWatchFromOtherSentences() throws {
            let first = Entry(text: "Bin nach der Arbeit mit dem Hund am See spazieren gegangen. Zum ersten Mal diese Woche fühlte ich mich leicht.", mood: "Peaceful")
            let second = Entry(text: "Habe für die ganze Woche Suppe gekocht und eingefroren. Meine Schwester hat lange mit mir telefoniert.", mood: "Grateful")
            second.createdAt = first.createdAt.addingTimeInterval(-86_400)
            let localized = try #require(InsightService.localizedGroundedDigest(weekEntries: [first, second], languageSource: [first, second]))
            let quote = "Zum ersten Mal diese Woche fühlte ich mich leicht."
            let text = try #require(try localized.validator?("\(quote)\n\(quote)\n\(quote)"))
            let lines = text.components(separatedBy: "\n")
            #expect(lines[1].contains(quote))
            #expect(!lines[2].contains(quote), "WHAT'S BUILDING takes another sentence")
            #expect(!lines[3].contains(quote), "WATCH OUT FOR takes another sentence")
            #expect(lines[2] != lines[3])
        }

        @Test func monthlyReleaseIsNotTheMomentsSentence() throws {
            let hard = Entry(text: "Missed the grant deadline by one day. Felt so stupid about it all evening.", mood: "Frustrated")
            let good = Entry(text: "Signed up for the evening Spanish course after thinking about it all week.", mood: "Hopeful")
            good.createdAt = hard.createdAt.addingTimeInterval(-86_400)
            let parts = try #require(InsightService.groundedMonthlyParts(monthEntries: [hard, good], code: "en", text: InsightService.englishMonthlyText(month: 1)))
            let moment = "Missed the grant deadline by one day."
            #expect(parts.options[2].contains(moment))
            let text = try parts.compose("\(moment)\nSigned up for the evening Spanish course after thinking about it all week.\n\(moment)")
            let lines = text.components(separatedBy: "\n")
            #expect(lines[2].contains(moment))
            #expect(!lines[4].contains(moment))
            #expect(lines[4].contains("Felt so stupid about it all evening."))
        }

        // MARK: L7 — a fragment is shown as its whole sentence (digest and Ask only)

        @Test func digestQuotesTheWholeSentenceNotAFragment() throws {
            let sources = [
                FMDailyGuard.Source(text: "Long meeting with the team today. I don't think I want to quit my job. Dinner was quiet.", mood: "Anxious"),
                FMDailyGuard.Source(text: "Second day of the pottery class and the bowl came out round.", mood: "Hopeful"),
            ]
            let draft = FMDigestGuard.Draft(
                theme: "a week of work and pottery", energyQuote: "I want to quit my job", energyRead: "Work seems to weigh on you.",
                buildingQuote: "the bowl came out round", buildingRead: "The class may be something to keep.",
                watchQuote: "Long meeting with the team today.", watchRead: "Keep an eye on how work feels.",
                boost: "Write a little more about the class.", nextWeek: "Notice how work feels next week."
            )
            let sections = FMDigestGuard.sections(from: [draft], sources: sources)
            let energy = try #require(sections[.energy])
            #expect(energy.quote == "I don't think I want to quit my job.")
            #expect(sections[.building]?.quote == "Second day of the pottery class and the bowl came out round.")
        }

        @Test func askEvidenceShowsTheWholeSentence() async throws {
            let e = Entry(text: "Long meeting with the team today. I don't think I want to quit my job. Dinner was quiet.", mood: "Anxious")
            let text = try #require(await InsightService.askEvidenceQuotes(answer: "x", askMessage: "", pool: [e], languageCode: "en") {
                ["I want to quit my job"]
            })
            #expect(text.contains("\"I don't think I want to quit my job.\""))
        }

        // MARK: L9 — a title doesn't end a quotable sentence

        @Test func quoteCandidatesDoNotSplitAfterATitle() {
            let options = InsightService.groundedNudgeQuoteCandidates(in: "Saw Dr. Okafor about the cough today. She said to rest more this week.")
            #expect(options.contains("Saw Dr. Okafor about the cough today."))
            #expect(!options.contains { $0.hasPrefix("Okafor") })
        }

        // MARK: Security rule 3 — at most 10,000 characters of entry text, oldest cut first

        private func longGermanWeek() -> [Entry] {
            let filler = String(repeating: "Heute war ein langer Tag im Büro und ich bin sehr müde. ", count: 100)
            let newest = Entry(text: "Zum ersten Mal diese Woche fühlte ich mich leicht und ruhig.", mood: "Peaceful")
            let middle = Entry(text: filler, mood: "Drained")
            middle.createdAt = newest.createdAt.addingTimeInterval(-86_400)
            let older = Entry(text: filler, mood: "Drained")
            older.createdAt = newest.createdAt.addingTimeInterval(-2 * 86_400)
            let oldest = Entry(text: filler + "Der alte Garten hinter dem Haus ist voller Unkraut.", mood: "Sad")
            oldest.createdAt = newest.createdAt.addingTimeInterval(-3 * 86_400)
            return [newest, middle, older, oldest]
        }

        @Test func localizedDigestAndReportSendAtMostTenThousandCharactersOfEntries() throws {
            let entries = longGermanWeek()
            #expect(entries.map(\.text.count).reduce(0, +) > InsightService.maxLocalLLMEntryChars)
            let digest = try #require(InsightService.localizedGroundedDigest(weekEntries: entries, languageSource: entries))
            let report = try #require(InsightService.localizedGroundedMonthly(monthEntries: entries))
            for plan in [digest.plan, report.plan] {
                guard case .grammarConstrained(let message, _) = plan else { Issue.record("expected a grammar plan"); continue }
                #expect(message.count <= InsightService.maxLocalLLMEntryChars + 1_000)
                #expect(message.contains("Zum ersten Mal diese Woche"), "the newest entry is kept")
                #expect(!message.contains("Der alte Garten"), "the oldest entry is cut first")
            }
        }

        // MARK: L15 — Ask outside the ten languages: the notice, no model

        @Test(arguments: [true, false])
        func askInAnUnsupportedLanguageIsTheNoticeWithoutAModel(forceGemma: Bool) async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("Een verzonnen antwoord.", .foundationModels) }
            LocalLLMService.forceGemmaForTesting = forceGemma
            defer {
                LocalLLMService.generateInterceptForTesting = nil
                LocalLLMService.forceGemmaForTesting = false
            }
            let pool = [
                "Vandaag twaalf dozen ingepakt en de oude bank verkocht aan de buren.",
                "Mijn zus belde en we hebben lang gepraat over de verhuizing naar Utrecht.",
                "Slecht geslapen, de hele nacht wakker gelegen van het werk.",
            ].map { Entry(text: $0, mood: "Content") }
            let (text, _) = try await InsightService.ask(question: "Hoe gaat het met de verhuizing naar Utrecht?", entries: pool)
            #expect(InsightService.isUnsupportedLanguageNotice(text))
            #expect(calls == 0)
        }
    }
}

// MARK: L7 / L8 — pure text, no shared LLM state

@Suite("FM quote sentence and Ask capitalization fixes")
struct QuoteSentenceAndCapitalizationTests {
    @Test func locateSentenceWidensAFragmentToItsSentence() {
        let texts = ["Long meeting with the team today. I don't think I want to quit my job. Dinner was quiet."]
        // The daily reflection's matcher is unchanged (rig-measured).
        #expect(FMDailyGuard.locate(quote: "I want to quit my job", in: texts)?.quote == "I want to quit my job")
        #expect(FMDailyGuard.locateSentence(quote: "I want to quit my job", in: texts)?.quote == "I don't think I want to quit my job.")
        #expect(FMDailyGuard.locateSentence(quote: "I don't think I want to quit my job.", in: texts)?.quote == "I don't think I want to quit my job.")
        #expect(FMDailyGuard.locateSentence(quote: "The rain kept me inside all evening.", in: texts) == nil)
    }

    @Test func locateSentenceStopsAtALineBreakAndNotAtATitle() {
        let texts = ["Groceries\nsaw Dr. Okafor about the cough and she was kind\nlaundry"]
        #expect(FMDailyGuard.locateSentence(quote: "about the cough and she was kind", in: texts)?.quote == "saw Dr. Okafor about the cough and she was kind")
    }

    @Test func wordsInsideQuotationMarksAreNeverChanged() {
        #expect(InsightService.capitalizedSentenceStarts("you wrote, \"i want to quit. maybe not.\" that sounds hard.")
                == "You wrote, \"i want to quit. maybe not.\" that sounds hard.")
        #expect(InsightService.capitalizedSentenceStarts("you wrote, \u{201C}tired. so tired.\u{201D} rest helps.")
                == "You wrote, \u{201C}tired. so tired.\u{201D} rest helps.")
        #expect(InsightService.capitalizedSentenceStarts("du schriebst \u{201E}ich bin müde. sehr.\u{201C} das zählt.", locale: Locale(identifier: "de"))
                == "Du schriebst \u{201E}ich bin müde. sehr.\u{201C} das zählt.")
        #expect(InsightService.capitalizedSentenceStarts("tu as écrit « je suis fatigué. » c'est dur.", locale: Locale(identifier: "fr"))
                == "Tu as écrit « je suis fatigué. » c'est dur.")
        #expect(InsightService.capitalizedSentenceStarts("「疲れた。」と書いた。") == "「疲れた。」と書いた。")
    }

    @Test func moreAbbreviationsDoNotStartASentence() {
        #expect(InsightService.capitalizedSentenceStarts("you went to bed at 2 a.m. tomorrow you rest.") == "You went to bed at 2 a.m. tomorrow you rest.")
        #expect(InsightService.capitalizedSentenceStarts("you listed chores, groceries etc. and more.") == "You listed chores, groceries etc. and more.")
        #expect(InsightService.capitalizedSentenceStarts("you saw Prof. lee. then you rested.") == "You saw Prof. lee. Then you rested.")
    }

    @Test func upperCasingFollowsTheAnswersLanguage() {
        #expect(InsightService.capitalizedSentenceStarts("iyi bir gün. iyi uyudun.", locale: Locale(identifier: "tr")) == "İyi bir gün. İyi uyudun.")
        #expect(InsightService.capitalizedSentenceStarts("iyi bir gün.") == "Iyi bir gün.")
    }
}
