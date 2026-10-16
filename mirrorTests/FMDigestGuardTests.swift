import Testing
import Foundation
@testable import mirror

// The structured English weekly digest on Foundation Models (tools/llmrig/fm/RUBRIC_FM.md, rounds 15-18).
// Synthetic text only.
@Suite("FM weekly digest guard")
struct FMDigestGuardTests {
    private let sources = [
        FMDailyGuard.Source(text: "Landlord emailed that the rent goes up in November. Spent an hour redoing the budget and it still doesn't add up.", mood: "Anxious"),
        FMDailyGuard.Source(text: "Second day at the new job. The team lead walked me through the codebase and it's less scary than I thought.", mood: "Hopeful"),
        FMDailyGuard.Source(text: "Ran 5k without stopping for the first time since spring.", mood: "Energized"),
    ]

    private var good: FMDigestGuard.Draft {
        FMDigestGuard.Draft(
            theme: "A week of a new job and a tight budget",
            energyQuote: "Ran 5k without stopping for the first time since spring.",
            energyRead: "You seem to want to trust your body.",
            buildingQuote: "The team lead walked me through the codebase and it's less scary than I thought.",
            buildingRead: "The new job may be turning into somewhere you can grow.",
            watchQuote: "Spent an hour redoing the budget and it still doesn't add up.",
            watchRead: "Keep an eye on how much the rent weighs on you.",
            boost: "Go through the budget with the new figures once.",
            nextWeek: "Keep checking in on how the new job feels."
        )
    }

    @Test func aGoodDraftComposesTheGemmaDigestsShape() throws {
        let v = try #require(FMDigestGuard.merge([good], sources: sources))
        #expect(v.theme == "A week of a new job and a tight budget.")
        #expect(v.energy == "You seemed most energized when you wrote, \"Ran 5k without stopping for the first time since spring.\" You seem to want to trust your body.")
        #expect(v.building.hasPrefix("You wrote, \"The team lead walked me through the codebase"))
        #expect(v.watch.hasPrefix("You wrote, \"Spent an hour redoing the budget"))
    }

    @Test func aQuoteNotInTheEntriesIsNotShown() {
        var draft = good
        draft.energyQuote = "The rain kept me inside all evening long."
        #expect(FMDigestGuard.merge([draft], sources: sources) == nil)
    }

    @Test func theThreeQuotesMustDiffer() {
        var draft = good
        draft.watchQuote = draft.energyQuote
        #expect(FMDigestGuard.merge([draft], sources: sources) == nil)
    }

    @Test func somethingGrowingIsNotQuotedFromAHardDay() {
        var draft = good
        draft.buildingQuote = "Landlord emailed that the rent goes up in November."
        #expect(FMDigestGuard.merge([draft], sources: sources) == nil)
    }

    @Test func aLineWithSceneryOrAnInventedNameIsNotShown() {
        var draft = good
        draft.boost = "Ask Marco to sit with you by the window and look at the sky."
        #expect(FMDigestGuard.merge([draft], sources: sources) == nil)
    }

    @Test func eachSectionComesFromTheFirstDraftWhereItPasses() throws {
        var first = good
        first.boost = "Light a candle and rest."
        var second = good
        second.energyRead = "The rain made you tired."
        let v = try #require(FMDigestGuard.merge([first, second], sources: sources))
        #expect(v.energy.hasSuffix("You seem to want to trust your body."))
        #expect(v.boost == "Go through the budget with the new figures once.")
    }

    @Test func theAppFillsWhatTheModelNeverGotRight() throws {
        var draft = good
        draft.watchRead = "The rain made it all heavier."
        draft.nextWeek = "Watch the sunrise and breathe."
        let a = try #require(FMDigestGuard.assemble([draft], sources: sources))
        #expect(a.fixed == [.watch, .nextWeek])
        #expect(a.verified.watch == "You wrote, \"Spent an hour redoing the budget and it still doesn't add up.\" " + (FMDigestGuard.fixedReads[.watch] ?? ""))
        #expect(a.verified.nextWeek == FMDigestGuard.fixedNextWeek)
    }

    @Test func withNoUsableDraftTheAppQuotesTheWeekItself() throws {
        let a = try #require(FMDigestGuard.assemble([], sources: sources))
        #expect(Set(a.fixed) == Set(FMDigestGuard.Section.allCases))
        // The watch quote comes from the hard day, the building quote from a day that wasn't.
        #expect(a.verified.watch.contains("Spent an hour redoing the budget and it still doesn't add up."))
        #expect(!a.verified.building.contains("budget") && !a.verified.building.contains("Landlord"))
    }

    /// Seen end to end on real Foundation Models (2026-10-16): the only good day went to YOUR ENERGY, so
    /// WHAT'S BUILDING could only quote a hard day, and "worth holding on to" followed "a fever and chills".
    @Test func aHardSentenceUnderWhatsBuildingGetsAPlainLine() throws {
        let flu = [
            FMDailyGuard.Source(text: "Mira dropped off groceries at the door and waved.", mood: "Grateful"),
            FMDailyGuard.Source(text: "Woke up with a fever and chills.", mood: "Drained"),
            FMDailyGuard.Source(text: "Booked an appointment because the cough won't go away.", mood: "Anxious"),
        ]
        let a = try #require(FMDigestGuard.assemble([], sources: flu))
        #expect(a.verified.building.hasSuffix(FMDigestGuard.fixedHardBuildingRead))
        #expect(!a.verified.building.contains("holding on to"))
    }

    /// Round 23: a line about the person instead of to them is dropped; one that names others and speaks to "you" stays.
    @Test func aLineThatSaysTheyInsteadOfYouIsDropped() {
        #expect(FMDigestGuard.speaksAboutThem("That moment seems to show they need space."))
        #expect(!FMDigestGuard.speaksAboutThem("They seem to lean on you, and you notice it."))
        #expect(!FMDigestGuard.speaksAboutThem("You seem to need space."))
    }

    /// Round 23: "over" is not "overwhelmed" and "numbers" is not "numb" any more.
    @Test func shortWordsNoLongerLookLikeFeelings() throws {
        let line = "Go over the budget numbers once more."
        #expect(FMDailyGuard.cleanSentences(of: line, sources: sources, maxSentences: 1)?.text == line)
        // A real feeling the entries don't carry is still dropped.
        #expect(FMDailyGuard.cleanSentences(of: "You feel overwhelmed by the budget.", sources: sources, maxSentences: 1) == nil)
    }

    /// Round 25: another person's matter given to this one is dropped; a name with an unnamed matter stays.
    @Test func aBoostThatGivesOnePersonsRequestToAnotherIsDropped() {
        let texts = [
            "Mom's knee surgery is booked for the 14th. Tara says she can take the first week but I'll need to cover the second.",
            "Asked my manager, Deepa, if I can work from Mom's place for a week. She said she'll think about it.",
            "Organic chem final is on Friday and I still don't understand the reaction mechanisms chapter.",
            "Study group with Malik in the library until 11.",
        ]
        // The simulator's name tagger finds no names, so the rule can only be checked where it does (Mac, iPhone).
        guard !FMDailyGuard.personNames(in: texts[1]).isEmpty else { return }
        #expect(!FMDigestGuard.namesStayWithTheirEntry("Talk to Tara about working from Mom's place for a week.", texts: texts))
        #expect(FMDigestGuard.namesStayWithTheirEntry("Talk to Deepa about working from Mom's place for a week.", texts: texts))
        #expect(FMDigestGuard.namesStayWithTheirEntry("Talk to Malik about the reaction mechanisms chapter.", texts: texts))
    }

    /// Round 26: "Dr." doesn't end a sentence, in the model's lines or in the app's own quotes.
    @Test func aTitleDoesNotCutALineOrAQuote() {
        let src = [FMDailyGuard.Source(text: "Missed the grant deadline by one day. Dr. Okafor was kind about it but I felt so stupid.", mood: "Sad")]
        #expect(FMDailyGuard.cleanSentences(of: "Talk to Dr. Okafor about the grant deadline.", sources: src, maxSentences: 1)?.text
                == "Talk to Dr. Okafor about the grant deadline.")
        #expect(FMDigestGuard.quotableSentences(of: src[0].text).contains("Dr. Okafor was kind about it but I felt so stupid."))
    }

    @Test func nothingQuotableMeansNoDigest() {
        let short = [FMDailyGuard.Source(text: "tired", mood: "Drained"), FMDailyGuard.Source(text: "ok day", mood: "Content")]
        #expect(FMDigestGuard.assemble([], sources: short) == nil)
    }

    @Suite("Structured digest in InsightService")
    struct Pipeline {
        private let week = [
            Entry(text: "Landlord emailed that the rent goes up in November. Spent an hour redoing the budget and it still doesn't add up.", mood: "Anxious"),
            Entry(text: "Second day at the new job. The team lead walked me through the codebase and it's less scary than I thought.", mood: "Hopeful"),
        ]

        @Test func savedWithTheDigestLabelsAndStopsAtTheFirstFullDigest() async throws {
            var calls = 0
            let text = try #require(try await InsightService.structuredFMDigest(weekEntries: week, userMessage: "") {
                calls += 1
                if calls == 1 { throw LocalLLMError.emptyResponse }
                return FMDigestGuard.Draft(
                    theme: "starting a job while the rent goes up",
                    energyQuote: "Spent an hour redoing the budget and it still doesn't add up.",
                    energyRead: "You seem to need the budget to work.",
                    buildingQuote: "Second day at the new job.",
                    buildingRead: "The new job may be a fresh start.",
                    watchQuote: "Landlord emailed that the rent goes up in November.",
                    watchRead: "Keep an eye on the rent.",
                    boost: "Redo the budget with the new rent once.",
                    nextWeek: "Keep checking how the new job feels."
                )
            })
            #expect(calls == 2)
            let lines = text.components(separatedBy: "\n")
            #expect(lines.count == 6)
            #expect(lines[0] == "THIS WEEK'S THEME: A week of starting a job while the rent goes up.")
            #expect(lines[1].hasPrefix("YOUR ENERGY: You seemed most anxious when you wrote, \"Spent an hour"))
            #expect(lines[2].hasPrefix("WHAT'S BUILDING: You wrote, \"Second day at the new job.\""))
        }

        @Test func everyAttemptFailingStillShowsTheWeeksOwnWords() async throws {
            var calls = 0
            let text = try #require(try await InsightService.structuredFMDigest(weekEntries: week, userMessage: "") {
                calls += 1
                throw LocalLLMError.emptyResponse
            })
            #expect(calls == InsightService.structuredDigestAttempts)
            #expect(text.contains(FMDigestGuard.fixedBoost))
            #expect(text.contains("You wrote, \""))
        }

        @Test func cancellationIsRethrown() async {
            await #expect(throws: CancellationError.self) {
                _ = try await InsightService.structuredFMDigest(weekEntries: self.week, userMessage: "") { throw CancellationError() }
            }
        }

        // Outside English only the three picked sentences come from the model; matched to the week's own.
        @Test func otherLanguagesUseOnlyTheQuotesTheModelPicked() async throws {
            let options = [["Ich habe die ganze Nacht nicht geschlafen."], ["Lena hat mir Suppe gebracht."], ["Der Bericht ist immer noch nicht fertig."]]
            var calls = 0
            let text = try #require(try await InsightService.structuredFMLocalizedDigest(
                options: options,
                validator: { $0.uppercased() },
                systemPrompt: "", userMessage: ""
            ) {
                calls += 1
                return FMDigestGuard.Draft(
                    theme: "Eine erfundene Woche am Meer", energyQuote: "ich habe die ganze nacht nicht geschlafen",
                    energyRead: "Erfunden.", buildingQuote: "Lena hat mir Suppe gebracht.", buildingRead: "Erfunden.",
                    watchQuote: "Der Regen hörte nicht auf.", watchRead: "Erfunden.", boost: "Erfunden.", nextWeek: "Erfunden."
                )
            })
            // The watch quote never matched, so all attempts ran and the app picked that one itself.
            #expect(calls == InsightService.structuredDigestAttempts)
            #expect(text == "ICH HABE DIE GANZE NACHT NICHT GESCHLAFEN.\nLENA HAT MIR SUPPE GEBRACHT.\nDER BERICHT IST IMMER NOCH NICHT FERTIG.")
            #expect(!text.contains("ERFUNDEN") && !text.contains("MEER") && !text.contains("REGEN"))
        }

        @Test func otherLanguagesStillGetADigestWhenEveryAttemptFails() async throws {
            let options = [["Ich habe die ganze Nacht nicht geschlafen."], ["Lena hat mir Suppe gebracht."], ["Der Bericht ist immer noch nicht fertig."]]
            let text = try await InsightService.structuredFMLocalizedDigest(options: options, validator: { $0 }, systemPrompt: "", userMessage: "") {
                throw LocalLLMError.emptyResponse
            }
            #expect(text?.components(separatedBy: "\n") == options.map { $0[0] })
        }

        @Test func howThisWasGeneratedShowsTheFMPrompt() {
            let content = "WHAT'S BUILDING: You wrote, \"Second day at the new job.\" The new job may be a fresh start."
            #expect(InsightService.systemPrompt(for: .weeklyDigest, content: content, engine: LLMEngine.foundationModels.rawValue).body == WEEKLY_DIGEST_FM_SYSTEM)
            #expect(InsightService.systemPrompt(for: .weeklyDigest, content: content, engine: LLMEngine.gemma.rawValue).body == WEEKLY_DIGEST_GEMMA_INSTRUCTIONS)
        }
    }
}

// Real Foundation Models, end to end through generateWeeklyDigest. Skipped unless HARNESS_REAL_FM is set
// (TEST_RUNNER_HARNESS_REAL_FM=1) and the device has Apple Intelligence. Synthetic weeks only.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct RealFMDigestTests {
        @Test func realFoundationModelsDigestIsGroundedAndComplete() async throws {
            guard ProcessInfo.processInfo.environment["HARNESS_REAL_FM"] != nil, LocalLLMService.prefersFoundationModels else { return }
            func week(_ texts: [(String, String)]) -> [Entry] {
                texts.enumerated().map { i, item in
                    let e = Entry(text: item.0, mood: item.1)
                    e.createdAt = Date().addingTimeInterval(-Double(i) * 3_600)
                    return e
                }
            }
            let german = week([
                ("Ich habe die ganze Nacht nicht geschlafen, weil der Bericht morgen fällig ist.", "Anxious"),
                ("Lena hat mir nach der Arbeit Suppe gebracht und wir haben lange geredet.", "Grateful"),
                ("Der Bericht ist immer noch nicht fertig und Jonas will ihn am Montag sehen.", "Overwhelmed"),
                ("Heute bin ich zum ersten Mal seit Wochen wieder gelaufen.", "Energized"),
            ])
            let japanese = week([
                ("今日は一日中会議で、とても疲れた。", "Drained"),
                ("ユキと久しぶりに電話で話して、気持ちが軽くなった。", "Grateful"),
                ("引っ越しの準備がまだ全然終わっていない。", "Overwhelmed"),
                ("週末は家でゆっくり本を読んだ。", "Peaceful"),
            ])
            let weeks = GroundingSampleHarness.digestRigWeeks.filter { ["wk_caregiver", "wk_hard", "wk_neutral"].contains($0.label) }
                + GroundingSampleHarness.digestHeldOutWeeks.filter { ["ho_move", "ho_flu"].contains($0.label) }
                + [("de_week", german), ("ja_week", japanese)]
            var out: [String] = []
            for (label, entries) in weeks {
                let started = Date()
                let (text, engine) = try await InsightService.generateWeeklyDigest(weekEntries: entries, allEntries: entries)
                let seconds = Int(Date().timeIntervalSince(started))
                #expect(engine == .foundationModels)
                #expect(text != InsightService.weeklyDigestUngroundedFallback, "\(label) fell back")
                let lines = text.components(separatedBy: "\n")
                #expect(lines.count == 6, "\(label): \(lines.count) lines")
                // Every quote shown is the week's own words.
                let weekText = entries.map(\.text).joined(separator: "\n")
                for line in lines {
                    guard let open = line.range(of: "wrote, \""), let close = line.range(of: "\" ", range: open.upperBound..<line.endIndex) else { continue }
                    let quote = String(line[open.upperBound..<close.lowerBound])
                    #expect(weekText.contains(quote), "\(label): quote not in the week: \(quote)")
                }
                out.append("== \(label) (\(seconds)s)\n\(text)")
            }
            print("[realfm-digest]\n" + out.joined(separator: "\n"))
        }
    }
}

// A language with no grounded digest or report gets the daily reflection's notice, and no model runs.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct UnsupportedLanguageDigestTests {
        private let dutch = [
            "Vandaag twaalf dozen ingepakt en de oude bank verkocht aan de buren.",
            "Mijn zus belde en we hebben lang gepraat over de verhuizing naar Utrecht.",
            "Slecht geslapen, de hele nacht wakker gelegen van het werk.",
            "Een lange wandeling gemaakt met de hond langs het kanaal.",
        ].map { Entry(text: $0, mood: "Content") }

        @Test func aDigestInAnUnsupportedLanguageIsTheNotice() async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let (text, _) = try await InsightService.generateWeeklyDigest(weekEntries: dutch, allEntries: dutch)
            #expect(text == InsightService.dailyNudgeUnsupportedLanguageNotice)
            #expect(InsightService.isUnsupportedLanguageNotice(text))
            #expect(calls == 0)
        }

        @Test func aMonthlyReportInAnUnsupportedLanguageIsTheNotice() async throws {
            var calls = 0
            LocalLLMService.generateInterceptForTesting = { _, _, _, _ in calls += 1; return ("x", .foundationModels) }
            defer { LocalLLMService.generateInterceptForTesting = nil }
            let (text, _) = try await InsightService.generateMonthlyReport(monthEntries: dutch, allEntries: dutch)
            #expect(text == InsightService.dailyNudgeUnsupportedLanguageNotice)
            #expect(calls == 0)
        }
    }
}
