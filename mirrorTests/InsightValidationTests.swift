import Testing
@testable import mirror

// A1 of the 2.1.0 design plan (.claude/2.1.0-design-plan.md, Track A1): a fixture-based
// structural test harness for the on-device LLM output pipeline in InsightService.swift.
//
// This does NOT invoke the model. It exercises the exact repair-then-validate pipeline
// production code runs on real model output — `.cleanedInsightOutput()` /
// `.cleanedDigestOutput()` / `.cleanedMonthlyReportOutput()` (regex-based repair: strips
// Markdown/brackets, rewrites a subset of first-person leakage, rewrites a subset of banned
// clinical phrases) followed by `InsightService.validate(_:for:)` (the structural gate:
// section-header/length/sentence/ending checks) — against hand-written fixture strings that
// stand in for what Gemma 3 1B / Foundation Models could plausibly emit. `validate` and the
// three `cleaned*Output()` methods were bumped from `private` to internal (still same-file
// scope otherwise) specifically to give this suite a seam; see the comments at each
// declaration in InsightService.swift.
//
// Three kinds of case here:
//   - PASS  — well-formed output the pipeline should accept (regression safety net)
//   - REJECT — malformed output the pipeline should catch (regression safety net)
//   - GAP   — output that violates an explicit rule in the task's `_SYSTEM` prompt, but that
//             the current repair+validate pipeline does NOT catch. These assert the *current*
//             permissive behavior on purpose — they are diagnosis, not a claim that the gap is
//             fine. Each is Track A3 backlog material. If one of these starts failing (the
//             pipeline now rejects/repairs it), that's real progress — flip it to REJECT/PASS
//             and note the change in this file's plan doc Log.
//
// Running this requires no simulator, no bundled model, no network — pure Swift, milliseconds.
// It does NOT prove the real model's output matches these fixtures; it proves the pipeline
// behaves correctly against representative shapes. True end-to-end verification (real
// `LocalLLMService.generate` output through this same pipeline) needs a device/simulator with
// the bundled Gemma model and is out of scope here — see Track A2 in the plan doc.

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

    /// Documents a KNOWN GAP: this text violates an explicit rule in the task's `_SYSTEM`
    /// prompt, but the pipeline currently does not catch it. Passes as long as the gap is
    /// still open. If it starts failing, the gap closed — see file header.
    private func expectStillPermitted(_ text: String, _ task: LocalLLMTask, gap: String) {
        do {
            _ = try InsightService.validate(text, for: task)
        } catch {
            Issue.record("GAP CLOSED (update Track A3 in .claude/2.1.0-design-plan.md): \(gap) — this now throws \(error), promote this case to expectRejected/expectValid — text: \(text)")
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

    // GAP: cleanedInsightOutput()'s first-person repair list covers I feel/felt/work/try/
    // need/want/plan/can/could/will/would/should — it does NOT cover "I am"/"I was"/"I were",
    // and rejectsFirstPerson is hardcoded false for .dailyNudge (InsightService.swift:476).
    // So an unambiguous journal-writer-voice leak (not the prompt's sanctioned Mirror-voice
    // "I noticed") slips through the entire pipeline untouched.
    @Test func dailyNudge_gap_unrepairedFirstPersonLeak_stillPasses() {
        let text = "I was overwhelmed by the deadline but I got through it anyway."
        expectStillPermitted(
            text.cleanedInsightOutput(), .dailyNudge,
            gap: "\"I was\"/\"I was...I got\" journal-writer-voice leak — not in cleanedInsightOutput's rewrite list, and rejectsFirstPerson is false for dailyNudge"
        )
    }

    // GAP: DAILY_NUDGE_SYSTEM explicitly bans "significant" and "patterns indicate" as
    // clinical phrases; cleanedInsightOutput() only rewrites "this suggests"/"emotional
    // weariness"/"mental health"/"the source mentions" — these two are unguarded anywhere.
    @Test func dailyNudge_gap_unbannedClinicalPhrase_stillPasses() {
        let text = "This week's patterns indicate you are dealing with something significant that keeps resurfacing."
        expectStillPermitted(
            text.cleanedInsightOutput(), .dailyNudge,
            gap: "\"patterns indicate\"/\"significant\" — banned by DAILY_NUDGE_SYSTEM, not in cleanedInsightOutput's rewrite list, not checked by validate()"
        )
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

    // GAP: ASK_SYSTEM is stricter than daily nudge — "Address the person as you/your only.
    // Never use I/me/my as if you are the journal writer" — no Mirror-voice "I noticed"
    // exception at all. But .ask shares the same rejectsFirstPerson: false as dailyNudge, so
    // this leaks through identically.
    @Test func ask_gap_unrepairedFirstPersonLeak_stillPasses() {
        let text = "I was surprised you asked, but you wrote about this exact worry in three separate entries last month."
        expectStillPermitted(
            text.cleanedInsightOutput(), .ask,
            gap: "\"I was\" leak — ASK_SYSTEM has no Mirror-voice exception (unlike dailyNudge's sanctioned \"I noticed\"), yet rejectsFirstPerson is false here too"
        )
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

    // Unlike dailyNudge/ask, weeklyDigest's validator DOES call
    // containsJournalWriterFirstPerson — so a leak using a repair-covered verb ("I felt")
    // never even reaches it (cleanedInsightOutput fixes it first), but one using an
    // unrepaired conjugation ("I was") survives cleaning and IS caught here. This is the
    // inverse of the dailyNudge/ask gap cases above: same repair-list hole, but weeklyDigest's
    // validator net still catches it.
    @Test func weeklyDigest_unrepairedFirstPersonLeak_stillRejected() {
        var bodies = Self.weeklyGoodBodies
        bodies[1] = "I was most alive during the Tuesday walk and most drained during the Thursday deadline crunch."
        let text = weeklyDigestText(bodies)
        expectRejected(text.cleanedDigestOutput(), .weeklyDigest)
    }

    // GAP: same "significant"/"patterns indicate" hole as dailyNudge — WEEKLY_DIGEST_SYSTEM
    // bans "significant" explicitly; nothing in the pipeline catches it here either.
    @Test func weeklyDigest_gap_unbannedClinicalPhrase_stillPasses() {
        var bodies = Self.weeklyGoodBodies
        bodies[3] = "The late nights indicate a significant pattern in how you're managing the project deadline."
        let text = weeklyDigestText(bodies)
        expectStillPermitted(
            text.cleanedDigestOutput(), .weeklyDigest,
            gap: "\"significant\"/\"indicate a ... pattern\" — banned by WEEKLY_DIGEST_SYSTEM, unguarded"
        )
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

    // GAP (the strongest one in this file): validateMonthlyReport never calls
    // containsJournalWriterFirstPerson at all — unlike weeklyDigest, there is no validator
    // net here, only the same partial repair list. A journal-writer-voice leak using verbs
    // outside that list survives completely unguarded.
    @Test func monthlyReport_gap_firstPersonLeak_stillPasses() {
        var bodies = Self.monthlyGoodBodies
        bodies[3] = "I am someone who protects my own time as fiercely as I protect everyone else's deadlines."
        let text = monthlyReportText(bodies)
        expectStillPermitted(
            text.cleanedMonthlyReportOutput(), .monthlyReport,
            gap: "\"I am\"/\"I protect\" journal-writer-voice leak — validateMonthlyReport has zero first-person check (validateWeeklyDigest has one, this doesn't)"
        )
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
