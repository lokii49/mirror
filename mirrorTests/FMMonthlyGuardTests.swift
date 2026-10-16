import Testing
import Foundation
@testable import mirror

// The structured monthly report on Foundation Models (tools/llmrig/fm/RUBRIC_FM.md, round 19). Synthetic text only.
@Suite("FM monthly report guard")
struct FMMonthlyGuardTests {
    private let sources = [
        FMMonthlyGuard.Source(text: "Missed the grant deadline by one day. Felt so stupid about it.", mood: "Frustrated", day: "10 Oct"),
        FMMonthlyGuard.Source(text: "Second pottery class tonight. My bowl actually came out round this time.", mood: "Joyful", day: "8 Oct"),
        FMMonthlyGuard.Source(text: "Grandpa's birthday would have been today. We both cried a bit on the call.", mood: "Sad", day: "5 Oct"),
        FMMonthlyGuard.Source(text: "Signed up for the evening Spanish course after thinking about it all week.", mood: "Hopeful", day: "2 Oct"),
    ]

    private var good: FMMonthlyGuard.Draft {
        FMMonthlyGuard.Draft(
            image: "a kiln slowly warming up",
            tensionA: "the grant work", tensionB: "the pottery class",
            momentQuote: "Signed up for the evening Spanish course after thinking about it all week.",
            momentRead: "That might have shown you that you can choose something for yourself.",
            becomingQuote: "My bowl actually came out round this time.",
            becomingRest: "keeps going until the bowl comes out round",
            releaseQuote: "Missed the grant deadline by one day.",
            releaseRest: "calling yourself stupid",
            question: "What would it take to keep the pottery class going?"
        )
    }

    @Test func aGoodDraftComposesTheGemmaReportsShape() throws {
        let s = try #require(FMMonthlyGuard.merge([good], sources: sources))
        #expect(s[0] == "A kiln slowly warming up.")
        #expect(s[1] == "You seem pulled between the grant work and the pottery class.")
        #expect(s[2].hasPrefix("On 2 Oct, you wrote, \"Signed up for the evening Spanish course"))
        #expect(s[3] == "You wrote, \"My bowl actually came out round this time.\" You seem to be becoming someone who keeps going until the bowl comes out round.")
        #expect(s[4].hasPrefix("You wrote, \"Missed the grant deadline by one day.\" Maybe it's time to let go of"))
        #expect(s[5].hasSuffix("?"))
    }

    @Test func griefIsNeverQuotedUnderLetGo() {
        var draft = good
        draft.releaseQuote = "Grandpa's birthday would have been today."
        #expect(FMMonthlyGuard.merge([draft], sources: sources) == nil)
        let a = FMMonthlyGuard.assemble([draft], sources: sources)
        #expect(a?.sections[4].contains("Grandpa") == false)
    }

    @Test func becomingIsNotQuotedFromAHardDay() {
        var draft = good
        draft.becomingQuote = "Missed the grant deadline by one day."
        draft.releaseQuote = "Felt so stupid about it."
        #expect(FMMonthlyGuard.merge([draft], sources: sources) == nil)
    }

    @Test func aQuestionMustBeAQuestion() {
        var draft = good
        draft.question = "Keep the pottery class going."
        #expect(FMMonthlyGuard.merge([draft], sources: sources) == nil)
    }

    @Test func aRepeatedOpenerIsNotDoubled() throws {
        var draft = good
        draft.becomingRest = "You seem to be becoming someone who keeps going."
        let s = try #require(FMMonthlyGuard.merge([draft], sources: sources))
        #expect(s[3].hasSuffix("You seem to be becoming someone who keeps going."))
    }

    @Test func theAppFillsWhatTheModelNeverGotRight() throws {
        var draft = good
        draft.image = "a rainy window"          // scenery
        draft.momentRead = "The rain made you sad."
        let a = try #require(FMMonthlyGuard.assemble([draft], sources: sources))
        #expect(a.fixed == [.moment, .image])
        #expect(a.sections[0] == FMMonthlyGuard.fixedImage)
        #expect(a.sections[2] == "On 2 Oct, you wrote, \"Signed up for the evening Spanish course after thinking about it all week.\" " + FMMonthlyGuard.fixedMomentRead)
    }

    @Test func aMonthWithNoHardDayGetsThePlainReleaseLine() throws {
        let calm = [
            FMMonthlyGuard.Source(text: "Quiet Sunday reading on the balcony all afternoon.", mood: "Content", day: "3 Oct"),
            FMMonthlyGuard.Source(text: "Second pottery class tonight and the bowl came out round.", mood: "Joyful", day: "1 Oct"),
        ]
        let a = try #require(FMMonthlyGuard.assemble([], sources: calm))
        #expect(a.sections[4] == FMMonthlyGuard.fixedRelease)
    }

    @Suite("Structured monthly report in InsightService")
    struct Pipeline {
        /// English uses only the model's picks too (owner decision after round 19), inside `englishMonthlyText`.
        @Test func englishIsTheMonthsOwnSentencesInFixedLines() async throws {
            let hopeful = Entry(text: "Signed up for the evening Spanish course after thinking about it all week.", mood: "Hopeful")
            hopeful.createdAt = Date().addingTimeInterval(-3 * 86_400)
            let hard = Entry(text: "Missed the grant deadline by one day. Felt so stupid about it.", mood: "Frustrated")
            let english = InsightService.englishMonthlyText(month: 1)
            let parts = try #require(InsightService.groundedMonthlyParts(monthEntries: [hopeful, hard], code: "en", text: english))
            let text = try #require(try await InsightService.structuredFMLocalizedMonthly(
                options: parts.options, validator: parts.compose, systemPrompt: "", userMessage: ""
            ) {
                FMMonthlyGuard.Draft(image: "an invented storm", tensionA: "x", tensionB: "y",
                                     momentQuote: "Missed the grant deadline by one day.", momentRead: "Invented.",
                                     becomingQuote: "Signed up for the evening Spanish course after thinking about it all week.",
                                     becomingRest: "invented", releaseQuote: "Felt so stupid about it.", releaseRest: "invented", question: "Invented?")
            })
            let lines = text.components(separatedBy: "\n")
            #expect(lines.count == 6)
            #expect(lines[2].hasPrefix("A MOMENT THAT SHIFTED SOMETHING: On "))
            #expect(lines[2].contains(", you wrote, \"Missed the grant deadline by one day.\" Moments like that"))
            #expect(lines[3] == "WHAT YOU'RE BECOMING: You wrote, \"Signed up for the evening Spanish course after thinking about it all week.\" " + english.becomingSuffix)
            #expect(lines[4] == "WHAT WANTS TO BE RELEASED: You wrote, \"Felt so stupid about it.\" " + english.releaseSuffix)
            #expect(!text.lowercased().contains("invented"))
        }

        /// Two months with the same overall mood read differently (rotation by calendar month).
        @Test func consecutiveMonthsGetDifferentEnglishLines() {
            let a = InsightService.englishMonthlyText(month: 10), b = InsightService.englishMonthlyText(month: 11)
            #expect(a.monthImage[.stressed] != b.monthImage[.stressed])
            #expect(a.monthQuestion[.stressed] != b.monthQuestion[.stressed])
            #expect(a.momentSuffix != b.momentSuffix)
            #expect(InsightService.englishMonthlyText(month: 1).monthImage == InsightService.englishMonthlyText(month: 4).monthImage)
        }

        @Test func otherLanguagesUseOnlyThePickedQuotes() async throws {
            let options = [["Ich habe mich für den Spanischkurs angemeldet."], ["Die Schale ist endlich rund geworden."], []]
            let text = try await InsightService.structuredFMLocalizedMonthly(options: options, validator: { $0 }, systemPrompt: "", userMessage: "") {
                FMMonthlyGuard.Draft(image: "Erfunden", tensionA: "", tensionB: "", momentQuote: "Ich habe mich für den Spanischkurs angemeldet.",
                                     momentRead: "Erfunden.", becomingQuote: "Die Schale ist endlich rund geworden.", becomingRest: "Erfunden",
                                     releaseQuote: "", releaseRest: "", question: "Erfunden?")
            }
            #expect(text == "Ich habe mich für den Spanischkurs angemeldet.\nDie Schale ist endlich rund geworden.")
        }
    }
}

// Real Foundation Models, end to end through generateMonthlyReport. Skipped unless HARNESS_REAL_FM is set.
extension SharedLLMState {
    @Suite(.serialized)
    @MainActor
    struct RealFMMonthlyTests {
        @Test func realFoundationModelsMonthlyIsGroundedAndComplete() async throws {
            guard ProcessInfo.processInfo.environment["HARNESS_REAL_FM"] != nil, LocalLLMService.prefersFoundationModels else { return }
            var out: [String] = []
            for (label, entries) in GroundingSampleHarness.digestRigMonths.filter({ ["mo_caregiver_hard", "mo_ho_volunteer_flu"].contains($0.label) }) {
                let (text, engine) = try await InsightService.generateMonthlyReport(monthEntries: entries, allEntries: entries)
                #expect(engine == .foundationModels)
                #expect(text != InsightService.monthlyReportUngroundedFallback, "\(label) fell back")
                let lines = text.components(separatedBy: "\n")
                #expect(lines.count == 6, "\(label): \(lines.count) lines")
                let monthText = entries.map(\.text).joined(separator: "\n")
                for line in lines {
                    guard let open = line.range(of: "wrote, \""), let close = line.range(of: "\" ", range: open.upperBound..<line.endIndex) else { continue }
                    let quote = String(line[open.upperBound..<close.lowerBound])
                    #expect(monthText.contains(quote), "\(label): quote not in the month: \(quote)")
                }
                out.append("== \(label)\n\(text)")
            }
            print("[realfm-monthly]\n" + out.joined(separator: "\n"))
        }
    }
}

// Monthly variety outside English (2026-10-16): the other languages' fixed lines rotate by month too.
@Suite("Localized monthly rotation")
struct LocalizedMonthlyRotationTests {
    @Test func consecutiveMonthsReadDifferentlyButStayRecognizable() throws {
        let de = try #require(InsightService.groundedLocales["de"])
        let october = de.monthlyText(month: 10), november = de.monthlyText(month: 11)
        #expect(october.monthImage[.stressed] != november.monthImage[.stressed])
        #expect(october.monthQuestion[.good] != november.monthQuestion[.good])
        #expect(october.momentSuffix != november.momentSuffix)
        // Saved reports are recognized by these, so they never rotate.
        #expect(october.becomingSuffix == november.becomingSuffix)
        #expect(october.releaseFallback == november.releaseFallback)
        #expect(de.monthlyText(month: 1).monthImage == de.monthImage)
    }

    @Test func everyLanguageHasTwoAlternatesForEveryMood() {
        for (code, loc) in InsightService.groundedLocales {
            for bucket in [GroundedMoodBucket.tired, .stressed, .sad, .good, .neutral] {
                #expect(loc.monthImageMore[bucket]?.count == 2, "\(code) image \(bucket)")
                #expect(loc.monthTensionMore[bucket]?.count == 2, "\(code) tension \(bucket)")
                #expect(loc.monthQuestionMore[bucket]?.count == 2, "\(code) question \(bucket)")
            }
            #expect(loc.momentSuffixMore.count == 2 && loc.releaseSuffixMore.count == 2, "\(code) suffixes")
        }
    }

    @Test func theLanguageCardSaysWhatToDo() {
        let message = InsightService.unsupportedLanguageCardMessage(InsightService.dailyNudgeUnsupportedLanguageNotice)
        #expect(message.hasPrefix(InsightService.dailyNudgeUnsupportedLanguageNotice))
        #expect(message.count > InsightService.dailyNudgeUnsupportedLanguageNotice.count + 10)
    }
}
