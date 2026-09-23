import Testing
import Foundation
import NaturalLanguage
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

    // Was a GAP: a 1B model prepends a task acknowledgment ("Okay, you've got it.
    // Let's see what you can offer.") before the real reflection, and every gate
    // (length, first-person, complete-ending) passed it. Now `startsWithMetaPreamble`
    // in validateCompleteProse rejects it so localGenerate retries.
    @Test func dailyNudge_metaPreamble_rejected() {
        let text = "Okay, you've got it. Let's see what you can offer.\n\nThe rain outside feels like a gentle reminder of the quiet spaces you've been trying to carve out."
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    @Test func dailyNudge_bareAcknowledgmentPreamble_rejected() {
        let text = "Sure. You wrote about the missed call three times this week, each time a little shorter than the last."
        expectRejected(text.cleanedInsightOutput(), .dailyNudge)
    }

    // The negative case that matters: a real reflection whose first sentence
    // merely begins with "Okay," (and carries actual content) must still pass —
    // the preamble check keys on a SHORT meta first sentence, not the lead word.
    @Test func dailyNudge_reflectionOpeningWithOkay_stillPasses() {
        let text = "Okay, the entry about your mother's health is still sitting heavy — you wrote it in fragments, which you usually only do when something scares you."
        expectValid(text.cleanedInsightOutput(), .dailyNudge)
    }

    @Test func ask_metaPreamble_rejected() {
        let text = "Here's what I found. You wrote about feeling stretched thin at work on Monday and again on Thursday."
        expectRejected(text.cleanedInsightOutput(), .ask)
    }

    // Was a GAP: the announce line ended with ":" not ".!?", so it had no sentence
    // break before the colon — `startsWithMetaPreamble`'s ≤12-word guard saw the
    // whole first paragraph as one sentence and bailed, and length/sentence/
    // first-person all passed. Now `strippingLeadingMetaPreamble` drops the colon
    // line in repair, so the insight opens on the real observation.
    @Test func dailyNudge_colonAnnouncePreamble_stripped() {
        let text = "Okay, here's a reflection for you, your friend:\n\nIt feels like today you're wrestling with the idea of building something lasting, and that is both exhilarating and a little terrifying, isn't it?"
        let cleaned = text.cleanedInsightOutput()
        #expect(cleaned.hasPrefix("It feels like today"))
        #expect(!cleaned.localizedCaseInsensitiveContains("here's a reflection"))
        #expect(!cleaned.localizedCaseInsensitiveContains("friend"))
        expectValid(cleaned, .dailyNudge)
    }

    @Test func dailyNudge_friendVocative_stripped() {
        let text = "You've been carrying the move quietly, my friend, and the entry about the empty kitchen said more than the ones where you tried to explain it."
        let cleaned = text.cleanedInsightOutput()
        #expect(!cleaned.localizedCaseInsensitiveContains("friend"))
        expectValid(cleaned, .dailyNudge)
    }

    // Negative case: a real reflection with a legitimate mid-sentence colon (no
    // announce marker, no leading acknowledgment) must pass through untouched.
    @Test func dailyNudge_legitimateColon_notStripped() {
        let text = "One line keeps standing out: you wrote that the quiet after everyone left felt less lonely than the noise before it. That shift is worth noticing."
        let cleaned = text.cleanedInsightOutput()
        #expect(cleaned.hasPrefix("One line keeps standing out"))
        expectValid(cleaned, .dailyNudge)
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

    // MARK: - FollowUp (one short question, ephemeral, never persisted — see 1.2 in writing-roadmap.md)

    @Test func followUp_shortQuestion_passes() {
        expectValid("What's underneath that tiredness?", .followUp)
    }

    @Test func followUp_missingQuestionMark_rejected() {
        expectRejected("What's underneath that tiredness", .followUp)
    }

    @Test func followUp_twoQuestions_rejected() {
        expectRejected("What's underneath that? And what will you do about it?", .followUp)
    }

    @Test func followUp_journalWriterFirstPerson_rejected() {
        // containsJournalWriterFirstPerson matches specific verbs after "I" (feel/need/etc.),
        // not every first-person construction — use one of those verbs, not a generic one.
        expectRejected("I feel like I need to say more?", .followUp)
    }

    @Test func followUp_tooLong_rejected() {
        let longQuestion = String(repeating: "word ", count: 40) + "?"
        expectRejected(longQuestion, .followUp)
    }

    // MARK: - Shared: empty input always rejected as .emptyResponse, before any task-specific check

    @Test(arguments: [LocalLLMTask.dailyNudge, .ask, .weeklyDigest, .monthlyReport, .emotion, .followUp])
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

    // MARK: - repeatsPriorOpening: the reject-and-retry guard's detector, in isolation.
    //
    // generateNudge's prompt-side instruction ("your recent reflections already opened with...")
    // is not itself reliable enough — observed in production: Gemma 3 1B reproduced a banned
    // opener nearly verbatim even after being told the exact phrase to avoid. This is the
    // backstop that decides whether a real retry is warranted; these tests cover its matching
    // logic directly, without invoking the model.

    @Test func repeatsPriorOpening_exactSevenWordMatch_detected() {
        let openings = ["The rain outside feels like a gentle"]
        let text = "The rain outside feels like a gentle reminder of the quiet spaces you've been carving out lately."
        #expect(InsightService.repeatsPriorOpening(text, openings: openings))
    }

    @Test func repeatsPriorOpening_caseInsensitive_detected() {
        let openings = ["the rain outside feels like a gentle"]
        let text = "The Rain Outside Feels Like A Gentle echo of something else entirely."
        #expect(InsightService.repeatsPriorOpening(text, openings: openings))
    }

    @Test func repeatsPriorOpening_differentOpening_notDetected() {
        let openings = ["The rain outside feels like a gentle"]
        let text = "You mentioned the drive home from your sister's again, and how much lighter you felt."
        #expect(!InsightService.repeatsPriorOpening(text, openings: openings))
    }

    @Test func repeatsPriorOpening_noPriorOpenings_neverDetected() {
        let text = "The rain outside feels like a gentle reminder of something."
        #expect(!InsightService.repeatsPriorOpening(text, openings: []))
    }

    @Test func repeatsPriorOpening_emptyText_notDetected() {
        let openings = ["The rain outside feels like a gentle"]
        #expect(!InsightService.repeatsPriorOpening("", openings: openings))
    }

    // Only the first 7 words are compared — a later coincidental echo of the same words
    // mid-sentence shouldn't count as a repeated opening.
    @Test func repeatsPriorOpening_matchOnlyCountsAtStart() {
        let openings = ["The rain outside feels like a gentle"]
        let text = "You wrote about your morning walk, and later said the rain outside feels like a gentle memory of home."
        #expect(!InsightService.repeatsPriorOpening(text, openings: openings))
    }

    // The actual failure mode this guard exists for: a one-word swap deep in the same template.
    // An exact 7-word equality check (the first version of this guard) misses this outright —
    // this is the regression test for that gap, caught by advisor before commit.
    @Test func repeatsPriorOpening_oneWordSwappedInSameTemplate_stillDetected() {
        let openings = ["The rain outside feels like a gentle echo"]
        let text = "The rain outside feels like a soft reminder of the quiet spaces you've been carving out."
        #expect(InsightService.repeatsPriorOpening(text, openings: openings))
    }

    // Guards against the opposite failure: two openings sharing only common filler words
    // ("the", "a") shouldn't count as a repeat just because short function words overlap.
    @Test func repeatsPriorOpening_onlyFillerWordsShared_notDetected() {
        let openings = ["The rain outside feels like a gentle"]
        let text = "The quiet evening with your dad stayed with you a while."
        #expect(!InsightService.repeatsPriorOpening(text, openings: openings))
    }

    // For an opening shorter than `minSharedWords`, the threshold scales down to the opening's
    // own word count — so a short opening still needs to be (almost) fully repeated to flag.
    @Test func repeatsPriorOpening_shortOpeningRequiresFullOverlap() {
        let openings = ["Okay you got it"]
        let fullRepeat = "Okay you got it, let's see what else you can offer this week."
        let partialOverlap = "Okay so today felt different in a way you named directly."
        #expect(InsightService.repeatsPriorOpening(fullRepeat, openings: openings))
        #expect(!InsightService.repeatsPriorOpening(partialOverlap, openings: openings))
    }

    // MARK: - isUngrounded: the second reject-and-retry guard, catching fabricated content
    // that repeatsPriorOpening can't — a *differently*-worded invention is just as disconnected
    // from the entries as a repeated one, and the opener guard alone would let it through.

    // The actual production case that motivated this guard: Gemma 3 1B generated a nudge about
    // rain and "quiet spaces" against entries about a Timer app launch and download counts —
    // zero shared vocabulary. Confirmed via the app's own on-device X-ray (InsightSignalSource)
    // reading the real entries behind that nudge.
    @Test func isUngrounded_fabricatedContent_detected() {
        let entries = [
            Entry(text: "Surprised to see 10 downloads the week the Timer app got released."),
            Entry(text: "1. Learn new things 2. Focus on building things 3. Explore new ideas 4. Keep managing well."),
            Entry(text: "Going in a good phase!"),
        ]
        let nudge = "The rain outside feels like a gentle reminder of the quiet spaces you've been carving out lately."
        #expect(InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    @Test func isUngrounded_sharesRealDetail_notDetected() {
        let entries = [
            Entry(text: "Drove home from my sister's place tonight and finally told her about the promotion. Felt lighter after."),
        ]
        let nudge = "You mentioned the drive home from your sister's, and how much lighter you felt once you finally said it."
        #expect(!InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // The real user report that motivated the 2-word threshold: "lots of generic assumptions
    // when I gave specific information." A nudge that shares exactly one coincidental content
    // word with a detail-rich entry — and is otherwise generic filler — used to pass this guard
    // outright. The source here has well over 4 content words, so the 2-word minimum applies.
    @Test func isUngrounded_oneCoincidentalWordAgainstDetailedEntry_nowDetected() {
        let entries = [
            Entry(text: "Spent the whole afternoon debugging the payment flow at work before the client demo. Finally fixed it an hour before the call."),
        ]
        let nudge = "Work has a way of testing us. Trust the process and give yourself grace today."
        #expect(InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // The short-entry fallback the 2-word threshold is guarded against breaking: a terse entry
    // genuinely can't supply 2 real content words, so the original 1-word threshold still
    // applies and a real, if thin, connection still passes.
    @Test func isUngrounded_shortEntrySingleSharedWord_stillNotDetected() {
        let entries = [Entry(text: "Going in a good phase!")]
        let nudge = "This phase you're in sounds like it's finally clicking into place."
        #expect(!InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // "How about long entries?" — a flat 2-word minimum has the exact same weak-signal problem
    // the original flat 1-word minimum had, just at a higher source-vocabulary size: a long
    // entry hands the model far more words to coincidentally land 2 of without the rest of the
    // reflection being any more specific. This entry has ~23 content words (>15), so the
    // requirement scales to 3; the nudge below shares only 2 ("client", "pricing") and is
    // otherwise generic — used to slip through the flat-2 version of this guard.
    @Test func isUngrounded_longEntryTwoCoincidentalWords_nowDetected() {
        let entries = [
            Entry(text: "Spent hours today rewriting the onboarding flow after user complaints about confusing pricing. Reviewed analytics dashboards, sketched three new wireframes, then walked the dog before joining a late client call about the roadmap timeline."),
        ]
        let nudge = "Client relationships and pricing decisions can feel like a lot to hold. Give yourself grace this week."
        #expect(InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // Same long entry, but a nudge that's genuinely grounded — 5 real shared words, comfortably
    // over the scaled minimum of 3 — still passes. The scaling shouldn't punish an honestly
    // specific reflection just because the source entry happens to be long.
    @Test func isUngrounded_longEntryGenuinelyGrounded_notDetected() {
        let entries = [
            Entry(text: "Spent hours today rewriting the onboarding flow after user complaints about confusing pricing. Reviewed analytics dashboards, sketched three new wireframes, then walked the dog before joining a late client call about the roadmap timeline."),
        ]
        let nudge = "Sounds like today's onboarding rewrite and the client call about the roadmap took a lot out of you — hope walking the dog after helped you reset."
        #expect(!InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // The actual regression from a live device (screenshot, 2026-09-17): a real account's
    // `recent + background` for a daily nudge is up to ~23 entries, not the single-entry
    // fixtures above — hundreds of unique content words. Under the pre-fix scaling
    // (`min(scaled, nudgeWordCount)`, no ceiling on `scaled` itself), `scaled` for a corpus
    // this size (2 + 300/15 = 22) blew straight past a ~25-30-word nudge's own content-word
    // count, so the cap became the practical requirement — near-total word-for-word overlap,
    // which no paraphrased reflection (and none of MirrorNotes' own voice words) can produce.
    // That's what surfaced live as the "couldn't find today's reflection" fallback ~8/10 times.
    // A genuinely grounded nudge naming one specific entry's details must still pass here.
    @Test func isUngrounded_realisticMultiEntryCorpus_genuinelyGroundedNudge_notDetected() {
        let entries = [
            Entry(text: "Surprised to see 10 downloads the week the Timer app got released."),
            Entry(text: "Spent hours today rewriting the onboarding flow after user complaints about confusing pricing."),
            Entry(text: "Reviewed analytics dashboards, sketched three new wireframes for the settings screen."),
            Entry(text: "Walked the dog before joining a late client call about the roadmap timeline."),
            Entry(text: "Debugging the payment flow at work before the client demo took most of the afternoon."),
            Entry(text: "Finally fixed the payment bug an hour before the call, felt like a huge relief."),
            Entry(text: "Quiet Sunday, mostly reading and catching up on emails from the week."),
            Entry(text: "Team standup ran long, mostly discussing the upcoming launch checklist."),
            Entry(text: "Cooked dinner for friends, first time hosting since moving into the new apartment."),
            Entry(text: "Long commute today, listened to a podcast about productivity habits."),
            Entry(text: "Gym session felt good, finally back to a regular routine after weeks off."),
            Entry(text: "Called my sister to catch up, she's doing well with the new job."),
            Entry(text: "Wrote a draft of the quarterly report, still needs more data from marketing."),
            Entry(text: "Rainy afternoon, stayed in and organized the garage for a few hours."),
            Entry(text: "Tried a new recipe for dinner, turned out better than expected."),
            Entry(text: "Reviewed pull requests most of the morning, one had a tricky merge conflict."),
            Entry(text: "Took the afternoon off to relax after a stressful week at work."),
            Entry(text: "Planned next month's budget, need to cut back on eating out."),
            Entry(text: "Read a few chapters of a new book before bed, really enjoying it."),
            Entry(text: "Short entry today, just tired and ready for the weekend."),
        ]
        let nudge = "That payment bug you finally fixed before the client demo sounds like it took a real weight off — hope the relief carried into the rest of your week."
        #expect(!InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // The real device case that motivated checking `recent` alone, not just `recent +
    // background` (isUngrounded_fabricatedContent_detected already proves the combined check
    // fires against a small corpus — this proves the loophole that opens once background grows
    // to ~20 entries). `recentEntries` below are the verbatim real entries behind the 2026-09-19
    // report (self-control/anger, a Timer app work session, MirrorNotes feedback) — user
    // confirmed no entry anywhere mentions "rain". `backgroundEntries` is a representative
    // 20-entry filler corpus standing in for the unseen real one; it isn't the user's actual
    // data, just plausible generic journaling that happens to land a few coincidental words
    // ("quiet", "moments", "space", "present") the fabricated nudge also uses.
    @Test func isUngrounded_fabricationClearsCombinedPool_recentAloneStillCatchesIt() {
        let recentEntries = [
            Entry(text: "Few things I shouldn't repeat again, because those make my confidence low. Self control is the so much important, I should stick to few things. As I woke up late, came back from Saikiran room to PG, After Freshup then started working on Timer app, really hoping people will love it. Along with this, watched a good movie, had good conversation with Arthy. More importantly other than self control, I should also control my anger. Let sarcasm come first, let cool talk come first before any argument. Anger will the last thing."),
            Entry(text: "Got a feedback about MirrorNotes, even though it's a complaint I felt happy because people are using the app & a user reported an issue. I got confidence on the product I'm building. I would myself dedicate certain time for MirrorNotes & improve this. MirrorNotes will definitely be successful."),
            Entry(text: "Came home, Having a good feeling that everything is going to be alright! Hoping for the best!"),
        ]
        let backgroundEntries = [
            Entry(text: "Quiet start to the morning, took a few moments before getting out of bed."),
            Entry(text: "Found some space in the day to just sit with my thoughts for once."),
            Entry(text: "Trying to stay present instead of rushing through every task today."),
            Entry(text: "Long call with a friend, mostly just catching up on small things."),
            Entry(text: "Cleaned the room a bit, felt good to clear some space out."),
            Entry(text: "Skipped the gym today, just wasn't feeling it."),
            Entry(text: "Read a bit before bed, nothing major happened today."),
            Entry(text: "Worked through a backlog of small tasks, nothing exciting."),
            Entry(text: "Caught up on messages I'd been putting off for a while."),
            Entry(text: "Tried to plan out next week a little, still figuring it out."),
            Entry(text: "Watched some videos, didn't do much else."),
            Entry(text: "Ate out with a friend, decent conversation."),
            Entry(text: "Slow day overall, mostly just resting."),
            Entry(text: "Did some laundry and other small chores."),
            Entry(text: "Checked in on a few old projects, nothing new."),
            Entry(text: "Short walk in the evening, nice weather."),
            Entry(text: "Spent time organizing notes from the week."),
            Entry(text: "Nothing major today, fairly ordinary."),
            Entry(text: "Talked with family for a bit in the evening."),
            Entry(text: "Wrapped up a few small errands around the house."),
        ]
        let nudge = "The scent of rain outside feels like a gentle reminder of the quiet moments you've been craving – a small, steady rhythm against the backdrop of your thoughts. It's a comforting feeling, and it pulls at a part of you that wants to simply be in the present, without needing to chase after anything else. Perhaps taking a few deep breaths, focusing on the sensation of the rain, could help you reconnect with that quiet space within yourself."

        // The bug: checking the combined pool alone lets this slip through once "quiet",
        // "moments", "space", and "present" each land once across 20 background entries —
        // exactly the coincidental-overlap failure mode isUngrounded_oneCoincidentalWordAgainst-
        // DetailedEntry already backstops for a single entry, reopened here at corpus scale.
        #expect(!InsightService.isUngrounded(nudge, sourceEntries: recentEntries + backgroundEntries))
        // The fix: the flat sharesNoWordWithRecent backstop against `recent` alone (small,
        // on-topic, can't be diluted) still catches it — zero real overlap with the entries the
        // prompt actually requires this nudge to be grounded in. Not isUngrounded(recent) — that
        // was the first version of this fix and it regressed live (see sharesNoWordWithRecent's
        // doc comment and isUngrounded_genuinelyGroundedAgainstRealRecentThree_notDetected below).
        #expect(InsightService.sharesNoWordWithRecent(nudge, recentEntries: recentEntries))
    }

    // The live regression this locks in: the FIRST version of the recent-only fix reused
    // isUngrounded's scaled threshold against `recent` alone, and real device testing
    // (2026-09-20) showed the groundingFallback card on every attempt, for entries that ARE the
    // user's real recent three (self-control/Timer app, MirrorNotes feedback, "came home
    // hopeful"). These four nudges are plausible MirrorNotes-voice reflections a human would
    // call genuinely grounded — each echoes real specifics but paraphrases the rest, the way an
    // on-device 1B model actually writes — and the scaled threshold flagged them anyway (this
    // test failed against the old `isUngrounded(text, sourceEntries: recentEntries)` call before
    // the fix). `sharesNoWordWithRecent` is the fix: flat, not scaled, so it can't reject a
    // reflection over sharing "only" one or two real words.
    @Test func isUngrounded_genuinelyGroundedAgainstRealRecentThree_notDetected() {
        let recentEntries = [
            Entry(text: "Few things I shouldn't repeat again, because those make my confidence low. Self control is the so much important, I should stick to few things. As I woke up late, came back from Saikiran room to PG, After Freshup then started working on Timer app, really hoping people will love it. Along with this, watched a good movie, had good conversation with Arthy. More importantly other than self control, I should also control my anger. Let sarcasm come first, let cool talk come first before any argument. Anger will the last thing."),
            Entry(text: "Got a feedback about MirrorNotes, even though it's a complaint I felt happy because people are using the app & a user reported an issue. I got confidence on the product I'm building. I would myself dedicate certain time for MirrorNotes & improve this. MirrorNotes will definitely be successful."),
            Entry(text: "Came home, Having a good feeling that everything is going to be alright! Hoping for the best!"),
        ]
        let plausibleNudges = [
            "The Timer app work and that MirrorNotes feedback landing the same week seem to have given you something real to hold onto.",
            "You noticed your own pattern with anger today, choosing cool talk over sarcasm before it turns into an argument.",
            "That complaint about MirrorNotes stung less because it meant someone out there is actually using what you built.",
            "Coming home hopeful tonight, after a day split between self control and the Timer app, sounds like real progress.",
        ]
        for text in plausibleNudges {
            #expect(!InsightService.sharesNoWordWithRecent(text, recentEntries: recentEntries), "wrongly flagged as ungrounded: \(text)")
        }
    }

    @Test func isUngrounded_noSourceText_notDetected() {
        // Nothing to compare against (e.g. entries whose decryption failed, all resolving to
        // empty text) shouldn't be treated as proof of fabrication — there's no ground truth
        // to check against either way.
        let entries = [Entry(text: "")]
        let nudge = "The rain outside feels like a gentle reminder."
        #expect(!InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    @Test func isUngrounded_emptyNudgeText_notDetected() {
        // Empty output is InsightService.validate()'s job to reject, not this guard's.
        let entries = [Entry(text: "Went for a long walk by the river today.")]
        #expect(!InsightService.isUngrounded("", sourceEntries: entries))
    }

    // Two texts sharing only common filler/short words ("the", "was", "like", "much") but no
    // real content word are still ungrounded — the stopword list exists for exactly this.
    // Deliberately does NOT reuse "quiet"/"gentle"/"reminder"/etc. from the fabrication fixture
    // above on the entry side: those are ordinary content words (not filler), so an entry that
    // genuinely mentions them SHOULD count as grounding — advisor caught an earlier version of
    // this test that put "quiet" in the entry too, which made it fail once "quiet" was correctly
    // removed from the stopword list (see groundingStopwords' comment) — that failure was the
    // guard behaving correctly, not a bug; the test's fixture was wrong.
    @Test func isUngrounded_onlyFillerWordsShared_stillDetected() {
        let entries = [Entry(text: "The evening was long and I felt like resting well, though nothing much happened.")]
        let nudge = "The rain outside feels like a gentle reminder of the quiet spaces you've been carving out."
        #expect(InsightService.isUngrounded(nudge, sourceEntries: entries))
    }

    // MARK: - openingIsUngrounded: catches a fabricated OPENING riding through on genuine
    // words later in the response (see its doc comment in InsightService.swift). Zero test
    // coverage existed for this function before this section — it's called exactly once, in
    // generateNudge's retry-loop guard, and had never been exercised directly.

    // The documented production case (InsightService.swift:327-330) this check was written to
    // catch: an invented weather opening, with the only shared words ("walk", "book") arriving
    // later in the response, from entries the opening itself never touches.
    @Test func openingIsUngrounded_fabricatedWeatherOpening_detected() {
        let entries = [
            // Deliberately none of the opening's own content words (rain, outside, gentle,
            // echo, quiet, space, trying, create) appear here — an earlier version of this
            // fixture had "outside" in this entry too, which coincidentally matched the
            // fabricated opening's "outside" and made the guard correctly report grounded.
            Entry(text: "Went for a walk this afternoon, first time in weeks. Felt good to move again."),
            Entry(text: "Finally finished the book I've been reading on and off for a month."),
        ]
        let nudge = "The rain outside feels like a gentle echo of the quiet space you've been trying to create. You're planning a walk later, and finishing that book sounds like exactly what you need."
        #expect(InsightService.openingIsUngrounded(nudge, recentEntries: entries))
    }

    // KNOWN MISS, not yet fixed — pinned here so the gap is tracked mechanically instead of only
    // in prose. Reproduces a live 2026-09-23 case from "Load Sample Entries (Mixed)": the source
    // entry genuinely contains "The conversation with Priya I still think about" (a later line
    // in a multi-line entry — see SampleData.swift's richEntries), so "conversation" and "priya"
    // are real shared words, not coincidental filler. But "scent", "rain", "pavement", "window",
    // "familiar", "ache", and "shoulders" — the sensory narrative the opening actually leads
    // with — appear nowhere in this entry or any other in the seed set. The model anchored a
    // fully invented sentence on two real nouns.
    //
    // openingIsUngrounded's flat "shares >= 1 real word" bar can't catch this: 2 shared words
    // clears it same as 20 would. Two fixes were tried and both were empirically falsified
    // against real fixtures, not just reasoned about — see the two tests directly below this
    // one for the actual numbers:
    //
    // 1. A stricter bar on raw shared-word count/density: rejected because this repo's word-
    //    matching is exact-string (no stemming: "rewriting" doesn't match "rewrite"), so honest
    //    paraphrase erodes the shared-word count on its own — same failure mode
    //    `minimumSharedWords`'s doc comment already warns is fragile to tune blind.
    //
    // 2. Restricting the absence-count to NOUNS only (via NLTagger, excluding verbs/adjectives
    //    so irregular verb forms like drive/drove can't cause false positives): looked promising
    //    on this fixture and one other, then falsified by a THIRD fixture — an honest reflection
    //    using interpretive/figurative nouns absent from the source ("weight off", "rest of your
    //    week") scored a higher unmatched-noun count than an actual fabrication. See
    //    `openingNounAbsence_honestFigurativeLanguageOutscoresActualFabrication_falsifiesNounSignal`.
    //
    // Bag-of-words overlap — noun-restricted or not — cannot structurally distinguish "real
    // anchor + honest paraphrase/interpretation" from "real anchor + invented elaboration."
    // Closing this needs either real Gemma generation samples to calibrate a genuinely different
    // signal against, or semantic verification (the model checking its own output), not another
    // word-set heuristic. Not attempted this pass — this is the fifth pass on this guard in six
    // days, and each of the previous four fixed one observed case by introducing a new
    // false-positive failure mode elsewhere; this pass adds a second falsified idea to that list
    // instead of a sixth blind attempt.
    @Test func openingIsUngrounded_realAnchorPlusFabricatedElaboration_knownMiss() {
        let entries = [
            Entry(text: """
                Things I keep circling back to
                Whether I'm actually resting or just not working
                The conversation with Priya I still think about
                "You can't pour from an empty cup." — heard this twice this week, universe is not subtle.
                """),
        ]
        let nudge = "The scent of rain on the pavement outside your window, a familiar ache in your shoulders, brought you back to that conversation with Priya."
        #expect(!InsightService.openingIsUngrounded(nudge, recentEntries: entries))
    }

    // Records why the noun-restricted absence-count idea (see comment above) was rejected,
    // as an executable fact rather than a claim in prose — so it fails loudly if someone later
    // changes `contentWords`'/the stopword list in a way that would flip the conclusion, instead
    // of silently going stale. Self-contained (its own noun-extraction + stopword filter, not
    // production code) since the idea was never wired into InsightService.
    //
    // Real NLTagger output (not hand-guessed) on five fixtures, filtered to nouns of 4+ letters
    // excluding this file's own stopword list, counting opening nouns absent from the entry's
    // noun set:
    //   fabricated (Priya case, above):              6 unmatched
    //   fabricated (original rain/quiet-spaces case): 3 unmatched
    //   honest (drive/sister paraphrase):             2 unmatched
    //   honest (onboarding/rewrite paraphrase):       2 unmatched
    //   honest (payment-bug realistic corpus):        4 unmatched  <- higher than a fabrication
    // The payment-bug case's "sounds", "rest", "week", "weight" are legitimate reflective/
    // figurative language ("took a weight off", "the rest of your week") that a genuine
    // grounded reflection can use without any of those exact nouns appearing in the source —
    // indistinguishable, by absence-from-corpus alone, from "pavement"/"scent"/"shoulders" being
    // genuinely invented. (NLTagger also mistagged "sounds" as a noun here, adding tagger noise
    // on top of the structural problem.) No threshold separates 4 (honest) from 3 (fabricated).
    @Test func openingNounAbsence_honestFigurativeLanguageOutscoresActualFabrication_falsifiesNounSignal() {
        func unmatchedNounCount(opening: String, corpus: String) -> Int {
            func nouns(in text: String) -> Set<String> {
                let tagger = NLTagger(tagSchemes: [.lexicalClass])
                tagger.string = text
                var result: Set<String> = []
                tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
                    if tag == .noun {
                        let w = String(text[range]).lowercased()
                        if w.count >= 4 && !Self.openingNounAbsenceStopwords.contains(w) {
                            result.insert(w)
                        }
                    }
                    return true
                }
                return result
            }
            return nouns(in: opening).subtracting(nouns(in: corpus)).count
        }

        let fabricatedUnmatched = unmatchedNounCount(
            opening: "The rain outside feels like a gentle reminder of the quiet spaces you've been carving out lately.",
            corpus: """
                Surprised to see 10 downloads the week the Timer app got released.
                1. Learn new things 2. Focus on building things 3. Explore new ideas 4. Keep managing well.
                Going in a good phase!
                """
        )
        let honestUnmatched = unmatchedNounCount(
            opening: "That payment bug you finally fixed before the client demo sounds like it took a real weight off — hope the relief carried into the rest of your week.",
            corpus: """
                Debugging the payment flow at work before the client demo took most of the afternoon.
                Finally fixed the payment bug an hour before the call, felt like a huge relief.
                """
        )

        // The falsification: an HONEST reflection scores >= an ACTUAL fabrication's unmatched
        // count. If this ever fails, the noun signal may have become viable — but check what
        // changed (contentWords, stopwords, or NLTagger behavior) before trusting a threshold.
        #expect(honestUnmatched >= fabricatedUnmatched)
    }

    private static let openingNounAbsenceStopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "in", "on", "at", "to", "from", "with", "for", "by",
        "is", "are", "was", "were", "be", "been", "being", "it", "its", "this", "that", "these", "those",
        "i", "me", "my", "mine", "you", "your", "yours", "we", "our", "ours",
        "he", "she", "they", "them", "his", "her", "their", "theirs",
        "feels", "feel", "felt", "feeling", "like", "likes", "liked",
        "still", "just", "really", "very", "so", "too", "also",
        "more", "most", "much", "many", "some", "any", "all", "each", "every", "other", "another", "such",
        "no", "not", "only", "own", "same", "than", "then", "once", "here", "there", "when", "where", "why",
        "how", "what", "which", "who", "whom", "having", "do", "does", "did", "doing",
        "would", "could", "should", "might", "must", "can", "will", "shall", "have", "has", "had",
        "about", "again", "further", "out", "up", "down", "over", "under", "off", "into", "onto",
        "if", "as", "because", "while", "during", "before", "after", "something", "someone", "things", "thing",
    ]

    @Test func openingIsUngrounded_emptyOpening_notDetected() {
        let entries = [Entry(text: "Went for a long walk by the river today.")]
        #expect(!InsightService.openingIsUngrounded("", recentEntries: entries))
    }

    // FIXED — was the opposite-direction known gap from the Priya case above. Now mirrors
    // sharesNoWordWithRecent's `recentWords.count >= 4` floor (InsightService.swift:403): below
    // it, this check defers entirely to isUngrounded's combined-pool check rather than judging
    // an honest opening against a recent corpus too thin to fairly supply grounding words. Safe
    // to add without a live thin-corpus opening sample (unlike a raised threshold): a floor only
    // makes the check MORE lenient, so the worst case is a fabrication slipping through on a
    // corpus with almost no vocabulary to fabricate against either — not a new false positive.
    @Test func openingIsUngrounded_thinRecentCorpus_deferToCombinedPoolInstead() {
        let entries = [Entry(text: "Okay day.")]
        let nudge = "Sounds like today had its moments, one way or another."
        #expect(!InsightService.openingIsUngrounded(nudge, recentEntries: entries))
    }

    @Test func openingIsUngrounded_genuinelyGroundedOpening_notDetected() {
        let entries = [
            Entry(text: "Drove home from my sister's place tonight and finally told her about the promotion. Felt lighter after."),
        ]
        let nudge = "You mentioned the drive home from your sister's, and how much lighter you felt once you finally said it."
        #expect(!InsightService.openingIsUngrounded(nudge, recentEntries: entries))
    }

    // MARK: - ungroundedDailyNudges: the retroactive audit over already-generated nudges.
    // Reuses isUngrounded and dailyNudgeContext, so these tests are really checking the
    // reconstruction (asOf-relative window, filtering out entries written after the nudge) is
    // wired correctly — the detection logic itself is already covered above.

    private func nudge(_ content: String, generatedAt: Date) -> Insight {
        let insight = Insight(type: .dailyNudge, content: content, periodIdentifier: "test")
        insight.generatedAt = generatedAt
        return insight
    }

    private func entry(_ text: String, createdAt: Date) -> Entry {
        let e = Entry(text: text)
        e.createdAt = createdAt
        return e
    }

    // The actual production pair this whole guard exists for: two real nudges (Sep 4, Sep 11),
    // confirmed fabricated via the app's own on-device X-ray reading the real entries behind
    // each one — this reproduces that finding as a regression test.
    @Test func ungroundedDailyNudges_flagsTheProductionCase() {
        let sep1 = entry("Have many dreams, many promises myself! I'm believing in myself.", createdAt: makeDate(2026, 9, 1))
        let sep4Entry = entry("The continuous thoughts of how to make it happen! How the life I desire.", createdAt: makeDate(2026, 9, 4))
        let sep7 = entry("1. Learn new things 2. Focus on building 3. Explore new ideas 4. Keep managing.", createdAt: makeDate(2026, 9, 7))
        let sep9 = entry("Surprised to see 10 downloads the week the Timer app got released.", createdAt: makeDate(2026, 9, 9))
        let sep10 = entry("Going in a good phase!", createdAt: makeDate(2026, 9, 10))

        let sep4Nudge = nudge(
            "The rain outside feels like a gentle echo of the quiet spaces you've been carving out lately, doesn't it?",
            generatedAt: makeDate(2026, 9, 4, hour: 18, minute: 45)
        )
        let sep11Nudge = nudge(
            "The rain outside feels like a gentle reminder of the quiet spaces you've been carving out lately.",
            generatedAt: makeDate(2026, 9, 11, hour: 18, minute: 27)
        )

        let allEntries = [sep1, sep4Entry, sep7, sep9, sep10]
        let flagged = InsightService.ungroundedDailyNudges(among: [sep4Nudge, sep11Nudge], allEntries: allEntries)
        #expect(flagged.count == 2)
    }

    @Test func ungroundedDailyNudges_grounded_notFlagged() {
        let sisterEntry = entry(
            "Drove home from my sister's place tonight and finally told her about the promotion. Felt lighter after.",
            createdAt: makeDate(2026, 9, 4)
        )
        let grounded = nudge(
            "You mentioned the drive home from your sister's, and how much lighter you felt once you finally said it.",
            generatedAt: makeDate(2026, 9, 5)
        )
        let flagged = InsightService.ungroundedDailyNudges(among: [grounded], allEntries: [sisterEntry])
        #expect(flagged.isEmpty)
    }

    // An entry written AFTER the nudge was generated couldn't have been read by it — including
    // it in the reconstruction would let a later, unrelated entry falsely "ground" an old
    // fabrication. This is exactly the asOf-filtering `dailyNudgeContext`/`ungroundedDailyNudges`
    // exist to get right.
    @Test func ungroundedDailyNudges_ignoresEntriesWrittenAfterGeneration() {
        let before = entry("Went for a long walk by the river today.", createdAt: makeDate(2026, 9, 1))
        let after = entry("The rain outside feels like a gentle reminder of the quiet spaces I've carved out.", createdAt: makeDate(2026, 9, 10))
        let oldNudge = nudge(
            "The rain outside feels like a gentle reminder of the quiet spaces you've been carving out lately.",
            generatedAt: makeDate(2026, 9, 2)
        )
        let flagged = InsightService.ungroundedDailyNudges(among: [oldNudge], allEntries: [before, after])
        #expect(flagged.count == 1)
    }

    // Exercises the dual check through the actual call path generation and the cleanup pass both
    // use — isUngrounded_fabricationClearsCombinedPool_recentAloneStillCatchesIt only asserts the
    // two isUngrounded() calls in isolation, so it would keep passing even if generateNudge (or
    // this audit) stopped combining them with ||. This locks in that they're actually combined.
    @Test func ungroundedDailyNudges_fabricationDilutedByLargeBackground_stillFlagged() {
        let recentEntries = [
            entry("Few things I shouldn't repeat again, because those make my confidence low. Self control is the so much important, I should stick to few things. As I woke up late, came back from Saikiran room to PG, After Freshup then started working on Timer app, really hoping people will love it.", createdAt: makeDate(2026, 9, 19)),
            entry("Got a feedback about MirrorNotes, even though it's a complaint I felt happy because people are using the app & a user reported an issue. I got confidence on the product I'm building.", createdAt: makeDate(2026, 9, 17)),
            entry("Came home, Having a good feeling that everything is going to be alright! Hoping for the best!", createdAt: makeDate(2026, 9, 11)),
        ]
        let backgroundEntries = (1...20).map { i in
            entry("Quiet moment number \(i), spent some time in the present with small ordinary space to think.", createdAt: makeDate(2026, 8, min(i, 28)))
        }
        let fabricated = nudge(
            "The scent of rain outside feels like a gentle reminder of the quiet moments you've been craving – a small, steady rhythm against the backdrop of your thoughts. Perhaps taking a few deep breaths could help you reconnect with that quiet space within yourself.",
            generatedAt: makeDate(2026, 9, 19, hour: 21, minute: 57)
        )
        let flagged = InsightService.ungroundedDailyNudges(among: [fabricated], allEntries: recentEntries + backgroundEntries)
        #expect(flagged.count == 1)
    }

    @Test func ungroundedDailyNudges_ignoresNonDailyNudgeInsights() {
        let riverEntry = entry("Went for a long walk by the river today.", createdAt: makeDate(2026, 9, 1))
        let fabricatedDigest = Insight(type: .weeklyDigest, content: "The rain outside feels like a gentle reminder.", periodIdentifier: "2026-W36")
        fabricatedDigest.generatedAt = makeDate(2026, 9, 2)
        let flagged = InsightService.ungroundedDailyNudges(among: [fabricatedDigest], allEntries: [riverEntry])
        #expect(flagged.isEmpty)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return Calendar.current.date(from: components)!
    }

    // MARK: - dailyNudgeContext: the recent/background split every nudge is generated from
    // (live) and every retroactive audit result is reconstructed from (historical). Exercised
    // above only indirectly through ungroundedDailyNudges — these test the split itself.

    @Test func dailyNudgeContext_withinWindow_takesUpToThreeRecentRestGoesToBackground() {
        let asOf = makeDate(2026, 9, 15)
        let entries = (1...5).map { entry("Entry \($0) about a specific unrepeatable topic.", createdAt: makeDate(2026, 9, 10 + $0)) }
        let (recent, background) = InsightService.dailyNudgeContext(from: entries, asOf: asOf)
        #expect(recent.count == 3)
        #expect(background.count == 2)
        // Most recent three, not an arbitrary three.
        #expect(Set(recent.map(\.createdAt)) == Set(entries.suffix(3).map(\.createdAt)))
    }

    @Test func dailyNudgeContext_emptyWithinWindow_fallsBackToSingleMostRecentEntry() {
        let asOf = makeDate(2026, 9, 15)
        // Both entries are older than the 14-day window but still exist — the "nothing written
        // recently" case generateNudge still needs at least something to reflect on.
        let old = entry("An entry from a month ago.", createdAt: makeDate(2026, 8, 1))
        let older = entry("An entry from two months ago.", createdAt: makeDate(2026, 7, 1))
        let (recent, background) = InsightService.dailyNudgeContext(from: [old, older], asOf: asOf)
        #expect(recent.count == 1)
        #expect(recent.first?.createdAt == old.createdAt)
        #expect(background.count == 1)
    }

    @Test func dailyNudgeContext_backgroundCappedAtTwenty() {
        let asOf = makeDate(2026, 9, 15)
        let recentEntries = (1...3).map { entry("Recent \($0)", createdAt: makeDate(2026, 9, 12 + $0)) }
        let oldEntries = (1...25).map { entry("Old \($0)", createdAt: makeDate(2026, 8, $0)) }
        let (recent, background) = InsightService.dailyNudgeContext(from: recentEntries + oldEntries, asOf: asOf)
        #expect(recent.count == 3)
        #expect(background.count == 20)
    }

    // MARK: - isUngrounded applied to weekly digests. generateWeeklyDigest reuses the exact
    // same detector as generateNudge, checked against the whole six-section digest text rather
    // than per-section — these confirm it behaves correctly on that longer, structured shape,
    // not just a 2-3 sentence nudge.

    @Test func isUngrounded_weeklyDigestFabricated_detected() {
        let entries = [
            Entry(text: "Shipped the launch today after three weeks of late nights. Team was relieved."),
            Entry(text: "Slept badly again, kept replaying the client call in my head."),
        ]
        let digest = weeklyDigestText([
            "The rain outside feels like a gentle echo of the quiet spaces you've been carving out.",
            "You seemed most alive on rainy afternoons, most drained during quiet evenings.",
            "Something gentle is building in the quiet spaces of your days.",
            "Watch out for letting the quiet moments slip away unnoticed.",
            "Sit by a rainy window for ten minutes with nothing else to do.",
            "Keep carving out those gentle, quiet spaces next week too.",
        ])
        #expect(InsightService.isUngrounded(digest, sourceEntries: entries))
    }

    @Test func isUngrounded_weeklyDigestGrounded_notDetected() {
        let entries = [
            Entry(text: "Shipped the launch today after three weeks of late nights. Team was relieved."),
            Entry(text: "Slept badly again, kept replaying the client call in my head."),
        ]
        let digest = weeklyDigestText([
            "This week was dominated by the launch finally shipping after three weeks of late nights.",
            "You were most alive when the launch went out, most drained replaying the client call at night.",
            "The relief from finally shipping is building into something steadier.",
            "Watch out for the late nights becoming a habit even after the launch is behind you.",
            "Send the team a thank-you for the three weeks of late nights.",
            "Let the sleep catch up now that the launch and the client call are behind you.",
        ])
        #expect(!InsightService.isUngrounded(digest, sourceEntries: entries))
    }
}
