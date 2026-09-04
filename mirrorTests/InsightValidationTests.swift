import Testing
import Foundation
@testable import mirror

// A1 of the 2.1.0 design plan (.claude/2.1.0-design-plan.md, Track A1): a fixture-based
// structural test harness for the on-device LLM output pipeline in InsightService.swift.
//
// This does NOT invoke the model. It exercises the exact repair-then-validate pipeline
// production code runs on real model output — `.cleanedInsightOutput()` /
// `.cleanedDigestOutput()` / `.cleanedMonthlyReportOutput()` (regex-based repair: strips
// Markdown/brackets, rewrites first-person leakage and banned clinical phrases) followed by
// `InsightService.validate(_:for:)` (the structural gate: section-header/length/sentence/
// ending/first-person checks) — against hand-written fixture strings that stand in for what
// Gemma 3 1B / Foundation Models could plausibly emit. `validate` and the three
// `cleaned*Output()` methods were bumped from `private` to internal (still same-file scope
// otherwise) specifically to give this suite a seam; see the comments at each declaration in
// InsightService.swift.
//
// This suite originally found five gaps (see plan doc Log for the full account) — dailyNudge/
// ask permitted unrepaired "I am/was/were" journal-writer-voice leaks, monthlyReport had zero
// first-person enforcement, and "significant"/"patterns indicate" were unguarded anywhere. All
// five are now closed in InsightService.swift (repair-list additions +
// `FirstPersonPolicy`/`containsJournalWriterFirstPerson(allowMirrorNoticed:)` +
// `validateMonthlyReport`'s new first-person check) and the tests below assert the fix, not
// just the previous gap. If a NEW gap like this turns up later, add a case documented the same
// way these used to be: assert the pipeline's current (undesired) permissive behavior with a
// comment explaining which prompt rule it violates and why the pipeline doesn't catch it yet,
// so it's tracked as a passing, mechanically-verifiable backlog item rather than prose.
//
// Running this requires no simulator, no bundled model, no network — pure Swift, milliseconds.
// It does NOT prove the real model's output matches these fixtures; it proves the pipeline
// behaves correctly against representative shapes. True end-to-end verification (real
// `LocalLLMService.generate` output through this same pipeline) needs a device/simulator with
// the bundled Gemma model and is out of scope here.

@Suite("InsightService validation pipeline")
struct InsightValidationTests {

    // MARK: - Helpers

    private func expectValid(_ text: String, _ task: LocalLLMTask) {
        do {
            _ = try InsightService.validate(text, for: task)
        } catch {
            Issue.record("expected valid for \(task), but validate() threw \(error) — text: \(text)")
        }
    }

    private func expectRejected(_ text: String, _ task: LocalLLMTask) {
        do {
            _ = try InsightService.validate(text, for: task)
            Issue.record("expected validate() to reject this \(task) text, but it passed — text: \(text)")
        } catch {
            // expected
        }
    }

    private static let weeklyLabels = InsightService.weeklyDigestSectionLabels.map { $0["en"]! }
    private static let monthlyLabels = InsightService.monthlyReportSectionLabels.map { $0["en"]! }

    private func weeklyDigestText(_ bodies: [String]) -> String {
        zip(Self.weeklyLabels, bodies).map { "\($0): \($1)" }.joined(separator: "\n")
    }

    private func monthlyReportText(_ bodies: [String]) -> String {
        zip(Self.monthlyLabels, bodies).map { "\($0): \($1)" }.joined(separator: "\n")
    }

    // MARK: - Daily nudge (validateCompleteProse: 45-char min, 120-word max, 1-4 sentences)

    @Test func dailyNudge_wellFormed_passes() {
        let text = "You mentioned the quiet drive home from your sister's on Tuesday, and how much lighter you felt once you finally said what you'd been holding back. That kind of honesty costs something in the moment, but it tends to pay you back for weeks."
        expectValid(text.cleanedInsightOutput(), .dailyNudge)
    }

    @Test func dailyNudge_tooShort_rejected() {
        expectRejected("You're tired.".cleanedInsightOutput(), .dailyNudge)
    }

    @Test func dailyNudge_noEndingPunctuation_rejected() {
        let text = "You've been carrying a lot lately and it shows in small ways you might not notice yourself"
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    @Test func dailyNudge_danglingEnding_rejected() {
        let text = "Something happened this week that mattered, though it's hard to explain, and now you're just sitting with it, thinking about."
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    @Test func dailyNudge_tooManyWords_rejected() {
        let text = "You " + Array(repeating: "kept", count: 130).joined(separator: " ") + " going."
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    @Test func dailyNudge_tooManySentences_rejected() {
        let text = "You noticed it. You named it. You sat with it. You let it pass. You wrote it down."
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    // DAILY_NUDGE_SYSTEM explicitly sanctions "I noticed ..." as Mirror's own voice — this is
    // the regression test proving that carve-out (FirstPersonPolicy.strictExceptMirrorNoticed)
    // actually works, not just that first-person is blocked in general.
    @Test func dailyNudge_mirrorVoiceINoticed_stillPasses() {
        let text = "I noticed you kept circling back to the launch even in entries that weren't about work at all. That kind of repetition usually means something is still unresolved."
        expectValid(text.cleanedInsightOutput(), .dailyNudge)
    }

    // Was a GAP (cleanedInsightOutput's repair list didn't cover "I am"/"I was"/"I were");
    // now closed — the repair step rewrites it to second person before validate() ever runs.
    @Test func dailyNudge_firstPersonLeak_nowRepaired() {
        let raw = "I was struck by how much lighter you felt once you finally said what you'd been holding back."
        let cleaned = raw.cleanedInsightOutput()
        #expect(cleaned.contains("you were struck"))
        #expect(!cleaned.localizedCaseInsensitiveContains("I was"))
        expectValid(cleaned, .dailyNudge)
    }

    // A leak using a verb the repair list still doesn't cover (e.g. "think") — proves the
    // validator-level FirstPersonPolicy.strictExceptMirrorNoticed backstop, not just the repair
    // step, actually rejects what repair alone can't fix.
    @Test func dailyNudge_unrepairableFirstPersonLeak_nowRejected() {
        let text = "I think this week wore you down more than you let yourself admit, even on the days you tried to push through it."
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    // Was a GAP ("significant"/"patterns indicate" unguarded); now closed via repair rewrite.
    // The "significant" rewrite is deliberately scoped to "something significant"/"significant
    // pattern" (see the comment at its declaration) rather than a global word replace — every
    // prompt also tells the model to quote the writer's own words, and "significant" is an
    // ordinary word people use unprompted, unlike the other clinical phrases here.
    @Test func dailyNudge_clinicalPhrase_nowRepaired() {
        let raw = "Patterns indicate you're dealing with something significant that keeps resurfacing."
        let cleaned = raw.cleanedInsightOutput()
        #expect(!cleaned.localizedCaseInsensitiveContains("significant"))
        #expect(!cleaned.localizedCaseInsensitiveContains("patterns indicate"))
        expectValid(cleaned, .dailyNudge)
    }

    // Regression for the scoping decision above: a genuine quote from the entry ("this felt
    // significant to me") must survive untouched — it isn't one of the two clinical
    // collocations, so the word-level rewrite must NOT fire on it.
    @Test func dailyNudge_quotedSignificant_isNotRewritten() {
        let raw = "You wrote \"this felt significant to me\" on Tuesday, right after the call ended."
        let cleaned = raw.cleanedInsightOutput()
        #expect(cleaned.contains("this felt significant to me"))
    }

    // MARK: - Ask (validateCompleteProse: 35-char min, 140-word max, 1-6 sentences, or exact no-answer phrase)

    @Test func ask_wellFormed_passes() {
        let text = "You wrote about feeling stretched thin during the week of the launch, especially in the entries where you mentioned skipping meals to keep working."
        expectValid(text.cleanedInsightOutput(), .ask)
    }

    @Test func ask_tooShort_rejected() {
        expectRejected("Nothing.".cleanedInsightOutput(), .ask)
    }

    // The exact-match no-answer fast path bypasses validateCompleteProse entirely (including
    // its 35-char minimum) — proven here with a deliberately short custom phrase that would
    // fail the length check on its own.
    @Test func ask_exactNoAnswerPhrase_bypassesLengthCheck() {
        let shortPhrase = "No entries about this."
        do {
            let result = try InsightService.validate(shortPhrase, for: .ask, askNoAnswerPhrase: shortPhrase)
            #expect(result == shortPhrase)
        } catch {
            Issue.record("expected the exact-match no-answer phrase to bypass validateCompleteProse, threw \(error)")
        }
    }

    // ASK_SYSTEM grants no Mirror-voice exception at all ("Address the person as you/your
    // only") — unlike dailyNudge, .ask uses FirstPersonPolicy.strict, so even "I noticed" (the
    // one phrase dailyNudge explicitly allows) is rejected here. This is the test proving the
    // two policies genuinely differ, not just that ask blocks *some* first person.
    @Test func ask_mirrorVoiceINoticed_isRejectedUnlikeDailyNudge() {
        let text = "I noticed you wrote about this exact worry in three separate entries last month."
        expectRejected(text.cleanedInsightOutput(), .ask)
    }

    // Was a GAP; a verb the repair list doesn't cover ("think") now correctly rejected by
    // FirstPersonPolicy.strict.
    @Test func ask_unrepairableFirstPersonLeak_nowRejected() {
        let text = "I think you wrote about this exact worry in three separate entries last month."
        expectRejected(text.cleanedInsightOutput(), .ask)
    }

    // MARK: - Weekly digest (six sections, 20-400 chars each, first-person leak IS checked)

    private static let weeklyGoodBodies = [
        "Settling into the new apartment dominated your week, and you kept circling back to it in almost every entry.",
        "You were most alive during the Tuesday walk and most drained during the Thursday deadline crunch.",
        "A quieter kind of confidence is building in how you talk about the project now.",
        "The late nights are quietly costing you sleep you keep saying you'll catch up on later.",
        "Take the fifteen minutes you mentioned wanting for the balcony coffee tomorrow morning.",
        "Give yourself permission to protect one evening this week the way you protected Tuesday's walk."
    ]

    @Test func weeklyDigest_wellFormed_passes() {
        let text = weeklyDigestText(Self.weeklyGoodBodies)
        expectValid(text.cleanedDigestOutput(), .weeklyDigest)
    }

    @Test func weeklyDigest_missingSection_rejected() {
        // Drop the WATCH OUT FOR line entirely.
        var bodies = Self.weeklyGoodBodies
        bodies.remove(at: 3)
        let labels = Array(Self.weeklyLabels.prefix(3)) + Array(Self.weeklyLabels.suffix(2))
        let text = zip(labels, bodies).map { "\($0): \($1)" }.joined(separator: "\n")
        expectRejected(text.cleanedDigestOutput(), .weeklyDigest)
    }

    @Test func weeklyDigest_sectionTooShort_rejected() {
        var bodies = Self.weeklyGoodBodies
        bodies[0] = "Change."
        let text = weeklyDigestText(bodies)
        expectRejected(text.cleanedDigestOutput(), .weeklyDigest)
    }

    // "I was" is now repaired to second person before validateWeeklyDigest ever sees it —
    // same fix as dailyNudge_firstPersonLeak_nowRepaired, checked here for the digest pipeline.
    @Test func weeklyDigest_firstPersonLeak_nowRepairedBeforeValidatorRuns() {
        var bodies = Self.weeklyGoodBodies
        bodies[1] = "I was most alive during the Tuesday walk and most drained during the Thursday deadline crunch."
        let text = weeklyDigestText(bodies)
        let cleaned = text.cleanedDigestOutput()
        #expect(!cleaned.localizedCaseInsensitiveContains("I was"))
        expectValid(cleaned, .weeklyDigest)
    }

    // Unlike dailyNudge/ask, weeklyDigest's validator has always called
    // containsJournalWriterFirstPerson directly — so a leak using a verb the repair list still
    // doesn't cover ("think") is caught by the validator, independent of the repair-list fix
    // above.
    @Test func weeklyDigest_unrepairableFirstPersonLeak_stillRejected() {
        var bodies = Self.weeklyGoodBodies
        bodies[1] = "I think you were most alive during the Tuesday walk and most drained during the Thursday deadline crunch."
        let text = weeklyDigestText(bodies)
        expectRejected(text.cleanedDigestOutput(), .weeklyDigest)
    }

    // Was a GAP; now closed via repair rewrite (same fix as dailyNudge_clinicalPhrase_nowRepaired).
    @Test func weeklyDigest_clinicalPhrase_nowRepaired() {
        var bodies = Self.weeklyGoodBodies
        bodies[3] = "Patterns indicate something significant building in how you're managing the project deadline."
        let text = weeklyDigestText(bodies)
        let cleaned = text.cleanedDigestOutput()
        #expect(!cleaned.localizedCaseInsensitiveContains("significant"))
        #expect(!cleaned.localizedCaseInsensitiveContains("patterns indicate"))
        expectValid(cleaned, .weeklyDigest)
    }

    // MARK: - Monthly report (six sections, 15-350 chars, closing section must end "?")

    private static let monthlyGoodBodies = [
        "A house with every light on and no one home, waiting for someone who already left.",
        "The pull between finishing the launch and actually resting kept resurfacing all month.",
        "The Wednesday you finally said no to another late call quietly shifted how you protect your evenings.",
        "Someone who protects their own time as fiercely as they protect everyone else's deadlines.",
        "The idea that rest has to be earned before it's allowed.",
        "What would this month look like if you trusted rest as much as you trust effort?"
    ]

    @Test func monthlyReport_wellFormed_passes() {
        let text = monthlyReportText(Self.monthlyGoodBodies)
        expectValid(text.cleanedMonthlyReportOutput(), .monthlyReport)
    }

    @Test func monthlyReport_missingSection_rejected() {
        var bodies = Self.monthlyGoodBodies
        bodies.remove(at: 4)
        let labels = Array(Self.monthlyLabels.prefix(4)) + Array(Self.monthlyLabels.suffix(1))
        let text = zip(labels, bodies).map { "\($0): \($1)" }.joined(separator: "\n")
        expectRejected(text.cleanedMonthlyReportOutput(), .monthlyReport)
    }

    @Test func monthlyReport_closingSectionMissingQuestionMark_rejected() {
        var bodies = Self.monthlyGoodBodies
        bodies[5] = "What would this month look like if you trusted rest as much as you trust effort."
        let text = monthlyReportText(bodies)
        expectRejected(text.cleanedMonthlyReportOutput(), .monthlyReport)
    }

    @Test func monthlyReport_sectionTooLong_rejected() {
        var bodies = Self.monthlyGoodBodies
        bodies[1] = "The pull between finishing the launch and actually resting kept resurfacing all month. "
            + String(repeating: "It kept resurfacing again and again in different forms. ", count: 6)
            + "It finally settled by the end of the month."
        let text = monthlyReportText(bodies)
        expectRejected(text.cleanedMonthlyReportOutput(), .monthlyReport)
    }

    // Was the strongest GAP found: validateMonthlyReport never called
    // containsJournalWriterFirstPerson at all. Now closed — this section body ("I think...")
    // uses a verb the repair list doesn't cover, so it reaches the validator's new check and
    // is rejected, matching the other three tasks' unrepairable-leak behavior.
    @Test func monthlyReport_firstPersonLeak_nowRejected() {
        var bodies = Self.monthlyGoodBodies
        bodies[3] = "I think you protect your own time as fiercely as you protect everyone else's deadlines."
        let text = monthlyReportText(bodies)
        expectRejected(text.cleanedMonthlyReportOutput(), .monthlyReport)
    }

    // MARK: - Emotion (single word from MirrorTheme.moodOptions, case/punctuation-tolerant)

    @Test func emotion_exactMatch_passes() {
        expectValid("Anxious", .emotion)
    }

    // Documents validate()'s actual contract, not an assumption: recognizedEmotion() tolerates
    // case and trailing punctuation when deciding whether to accept, but validate() returns
    // the raw trimmed input as-is on success — it does NOT canonicalize casing itself.
    // Canonicalization happens one level up, in InsightService.normalizeEmotion (called by
    // detectEmotion after validate already ran) — not exercised by this test.
    @Test func emotion_lowercaseWithPunctuation_passesButIsNotCanonicalized() {
        do {
            let result = try InsightService.validate("anxious.", for: .emotion)
            #expect(result == "anxious.")
        } catch {
            Issue.record("expected \"anxious.\" to be recognized despite case/punctuation, threw \(error)")
        }
    }

    @Test func emotion_notAMoodWord_rejected() {
        expectRejected("I feel great today", .emotion)
    }

    // MARK: - Shared: empty input always rejected as .emptyResponse, before any task-specific check

    @Test(arguments: [LocalLLMTask.dailyNudge, .ask, .weeklyDigest, .monthlyReport, .emotion])
    func emptyInput_alwaysThrowsEmptyResponse(_ task: LocalLLMTask) {
        do {
            _ = try InsightService.validate("", for: task)
            Issue.record("expected empty input to throw for \(task)")
        } catch InsightError.emptyResponse {
            // expected
        } catch {
            Issue.record("expected InsightError.emptyResponse for \(task), got \(error)")
        }
    }
}
