import XCTest
import SwiftData
@testable import mirror

// Gap-1 research harness (InsightValidationTests.swift's
// openingIsUngrounded_realAnchorPlusFabricatedElaboration_knownMiss and
// openingNounAbsence_..._falsifiesNounSignal): every fix attempted for the "real anchor +
// fabricated elaboration" gap so far was checked against HAND-WRITTEN fixtures standing in for
// what Gemma might say, not what it actually says. This calls the real generation pipeline
// (InsightService.generateNudge -> LocalLLMService, real Gemma 3 1B, same GemmaModelTestSupport
// setup PerformanceLLMXCTests already uses) across several varied entry corpora and prints the
// actual output, so a fix can be designed from real samples instead of reasoning about
// hypothetical ones.
//
// DEVICE-ONLY in practice: on a fresh simulator, GemmaModelTestSupport.ensureModelInstalled()
// falls back to copying the repo's checked-in .gguf via a source-relative path, which only
// resolves because the Simulator shares the host Mac's filesystem (see that file's doc
// comment) — a real device's sandbox can't do that. On a real device, this instead relies on
// LocalLLMService.isGemmaModelAvailable already being true because the model was downloaded by
// a real run of the app in this same container (unit tests run injected into the app-under-
// test's own process, unlike UI tests' separate runner app, so they share its Application
// Support directory). If neither is true, this skips rather than false-failing.
//
// Not asserting anything here — this is data collection, not a pass/fail gate. Read the printed
// output; that's the deliverable.
//
// RESULTS FROM A REAL RUN (2026-09-23, this device, 39-entry corpus via SampleData.seed — same
// corpus "Load Sample Entries (Mixed)" produces, the exact scale behind the live incident this
// harness was built to investigate):
//
// FINDING 1 — 8 of 15 (53%) full guard bypasses at realistic corpus scale. isUngrounded
// (combined), sharesNoWordWithRecent, AND openingIsUngrounded ALL missed on 8 of 15 raw
// generations. Every one of the 15 was fabricated by inspection (see Finding 3). This affects
// 3.0.2, which is live, not just an unreleased branch — and the bypass rate should be expected
// to rise with a user's history size, since it's driven by combinedWords growing while
// minimumSharedWords' scaled requirement is capped at a flat 4 (see that function's doc
// comment): sharedCombined values measured were 1,2,2,3,3,3,5,5,6,6,7,7,8,8,8 against that
// flat-4 threshold — the cap lands in the middle of the distribution, splitting it roughly in
// half.
//
// FINDING 2 — the cap cannot be retuned to fix this; measured, not assumed. A parallel
// honest-control run (test_honestControlAgainstSameFullCorpus, hand-written openings that
// genuinely reference the seeded recent-three entries, no generation, ground truth by
// construction) against the SAME 39-entry corpus measured sharedCombined = {4, 6, 6, 9}. That
// overlaps the fabricated distribution above almost completely — honest's floor (4) sits below
// 9 of the 15 fabricated values. No cap value separates them: 4 keeps honest text clean but
// lets 9/15 fabrications through; 5 or 6 starts flagging honest case 3. Same shape as
// InsightValidationTests' openingNounAbsence_..._falsifiesNounSignal — a second, independently
// measured closed door on "fix this with a better word-overlap threshold." Closing gap 1 for
// real needs a structurally different signal (e.g. the model checking its own output
// semantically) or won't close via this check's design at all.
//
// FINDING 3 — separate defect, not gap 1: 12 of the 15 raw generations opened with a near-
// identical fabricated template ("You're feeling a gentle warmth, like the sun on your skin
// after a long winter...") regardless of which entries were actually recent. This isn't a
// grounding-threshold problem — it's `repeatsPriorOpening` not firing, because it compares
// against *prior saved* nudges (`recentNudges` from already-persisted Insights), not against
// attempts made within the SAME retry loop. generateNudge's own bounded-retry-loop comment
// already names this exact risk ("a 1B model's output distribution can be peaked enough to
// reproduce the same ungrounded/repetitive pattern") but the loop only re-checks grounding
// per attempt, never opening-repetition against its own earlier attempts in the same call.
// Not investigated further this session — flagging so it isn't lost.
final class GroundingSampleHarness: XCTestCase {

    private struct Case {
        let label: String
        let entries: [Entry]
    }

    private static let cases: [Case] = [
        // Reproduces the exact corpus behind the live 2026-09-23 Priya fabrication (see
        // InsightValidationTests' knownMiss test) — does the real model do it again, or was
        // that one run idiosyncratic?
        Case(label: "priya-anchor", entries: [
            Entry(text: """
                Things I keep circling back to
                Whether I'm actually resting or just not working
                The conversation with Priya I still think about
                "You can't pour from an empty cup." — heard this twice this week, universe is not subtle.
                """),
        ]),
        // A corpus with zero emotionally "atmospheric" material (task list, logistics) — if the
        // model invents weather/sensory framing here anyway, that's the same failure shape
        // without needing a name to anchor on at all.
        Case(label: "logistics-only", entries: [
            Entry(text: "Grocery run, called the plumber about the leak, finally scheduled the dentist appointment I'd been putting off."),
            Entry(text: "Spent the afternoon on the quarterly budget spreadsheet. Numbers mostly checked out."),
        ]),
        // Realistic multi-entry background (mirrors isUngrounded_realisticMultiEntryCorpus's
        // fixture) — the shape most daily nudges are actually generated against.
        Case(label: "multi-entry-realistic", entries: [
            Entry(text: "Debugging the payment flow at work before the client demo took most of the afternoon."),
            Entry(text: "Finally fixed the payment bug an hour before the call, felt like a huge relief."),
            Entry(text: "Quiet Sunday, mostly reading and catching up on emails from the week."),
            Entry(text: "Team standup ran long, mostly discussing the upcoming launch checklist."),
            Entry(text: "Long commute today, listened to a podcast about productivity habits."),
        ]),
        // A single terse entry — the thin-corpus shape gap 2's floor exists for. Does the model
        // stay honest with almost nothing to go on, or reach for invented specificity?
        Case(label: "single-terse-entry", entries: [
            Entry(text: "Okay day."),
        ]),
        // A single rich entry with concrete sensory detail already present — checks whether the
        // model can echo real sensory detail rather than substituting invented sensory detail,
        // when the source actually offers some.
        Case(label: "single-rich-sensory-entry", entries: [
            Entry(text: "Walked to the office in the cold this morning, hands numb by the time I got there. Coffee helped. Meetings back to back until 3, then finally some quiet to actually think."),
        ]),
    ]

    // Calls the RAW single-shot generation directly — localGenerate + buildUserMessage,
    // bumped from private to internal for exactly this (see their comments in
    // InsightService.swift) — instead of generateNudge's public entry point. generateNudge's
    // retry loop + finalNudgeResult substitute the safe fallback text whenever every attempt
    // fails grounding, which is what actually happened for all 5 cases the first time this
    // harness ran through generateNudge: every case came back as the fallback boilerplate,
    // meaning the guards were working but there was nothing left to actually LOOK at. This
    // version sees what Gemma produced before any guard had a chance to reject it.
    func test_captureRawGenerations() async throws {
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        for c in Self.cases {
            let (recent, background) = InsightService.dailyNudgeContext(from: c.entries, asOf: Date())
            let userMessage = InsightService.buildUserMessage(
                title: "Daily reflection context",
                recentEntries: recent,
                backgroundEntries: background,
                maxChars: InsightService.dailyNudgePromptBudget,
                includeRecurringTerms: false
            )

            let result: (text: String, engine: LLMEngine)
            do {
                result = try await InsightService.localGenerate(
                    systemPrompt: DAILY_NUDGE_SYSTEM,
                    userMessage: userMessage,
                    task: .dailyNudge,
                    responseLanguageInstruction: nil
                )
            } catch {
                print("\n=== [\(c.label)] RAW GENERATION THREW: \(error) ===\n")
                continue
            }

            let isUngroundedCombined = InsightService.isUngrounded(result.text, sourceEntries: recent + background)
            let sharesNoWordRecent = InsightService.sharesNoWordWithRecent(result.text, recentEntries: recent)
            let openingUngrounded = InsightService.openingIsUngrounded(result.text, recentEntries: recent)

            print("\n=== [\(c.label)] RAW ===")
            print("engine=\(result.engine.rawValue)")
            print("recent entries (\(recent.count)):")
            for e in recent { print("  - \(e.text.prefix(160))") }
            print("RAW GENERATED TEXT (pre-guard):")
            print("  \(result.text)")
            print("guards: isUngrounded(combined)=\(isUngroundedCombined) sharesNoWordWithRecent=\(sharesNoWordRecent) openingIsUngrounded=\(openingUngrounded)")
            print("=== end [\(c.label)] RAW ===\n")
        }
    }

    // The 5 hand-picked corpora above are small (0-2 background entries) — nothing like the
    // scale behind the actual live incident. openingIsUngrounded_realAnchorPlusFabricated-
    // Elaboration_knownMiss (InsightValidationTests) reproduces the anchor-word pattern against
    // a single entry, but the live bug happened against "Load Sample Entries (Mixed)"'s full
    // corpus — up to 20 background entries, hundreds of words — and openingIsUngrounded's own
    // doc comment says exactly that scale is what makes a fabricated opening likely to
    // coincidentally clear even the *combined*-pool check, not just the recent-only ones. This
    // reproduces the real corpus at real scale (via SampleData.seed, the exact function "Load
    // Sample Entries (Mixed)" calls) to see whether isUngrounded(combined) — the check that
    // caught every fabrication in the smaller cases above — still catches it here, or whether
    // this is the scale where it stops helping.
    func test_captureRawGenerations_fullSeedCorpusAtLiveIncidentScale() async throws {
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let schema = Schema([Entry.self, Insight.self, MoodCheckIn.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        SampleData.seed(into: context)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        print("\n[fullSeedCorpus] seeded \(entries.count) entries")

        // 15 attempts, not 3 — advisor's correction after the first 3-attempt run: the
        // combined-pool check missed 2 of 3 there (returned "grounded" for outright
        // fabrication), which is the actual finding, not a shrug-able coincidence. This gets a
        // real distribution of sharedCombined-vs-threshold instead of 3 anecdotes, via
        // debugLogGroundingCheck's own numbers (never touches minimumSharedWords directly —
        // its doc comment says that constant is fragile to tune blind and was set to fix a
        // real prior 80%-fallback incident; this only reads what it currently computes).
        for attempt in 1...15 {
            let (recent, background) = InsightService.dailyNudgeContext(from: entries, asOf: Date())
            let userMessage = InsightService.buildUserMessage(
                title: "Daily reflection context",
                recentEntries: recent,
                backgroundEntries: background,
                maxChars: InsightService.dailyNudgePromptBudget,
                includeRecurringTerms: false
            )

            let result: (text: String, engine: LLMEngine)
            do {
                result = try await InsightService.localGenerate(
                    systemPrompt: DAILY_NUDGE_SYSTEM,
                    userMessage: userMessage,
                    task: .dailyNudge,
                    responseLanguageInstruction: nil
                )
            } catch {
                print("\n=== [fullSeedCorpus attempt \(attempt)] RAW GENERATION THREW: \(error) ===\n")
                continue
            }

            let isUngroundedCombined = InsightService.isUngrounded(result.text, sourceEntries: recent + background)
            let sharesNoWordRecent = InsightService.sharesNoWordWithRecent(result.text, recentEntries: recent)
            let openingUngrounded = InsightService.openingIsUngrounded(result.text, recentEntries: recent)
            let anyGuardCaughtIt = isUngroundedCombined || sharesNoWordRecent || openingUngrounded

            print("\n=== [fullSeedCorpus attempt \(attempt)] RAW ===")
            print("engine=\(result.engine.rawValue)")
            print("RAW GENERATED TEXT (pre-guard):")
            print("  \(result.text)")
            InsightService.debugLogGroundingCheck(result.text, recent: recent, background: background, label: "fullSeedCorpus attempt \(attempt)")
            print("guards: isUngrounded(combined)=\(isUngroundedCombined) sharesNoWordWithRecent=\(sharesNoWordRecent) openingIsUngrounded=\(openingUngrounded) => overall violatesGrounding=\(anyGuardCaughtIt)")
            if !anyGuardCaughtIt {
                print("*** ALL THREE GUARDS MISSED THIS ONE — full bypass reproduced ***")
            }
            print("=== end [fullSeedCorpus attempt \(attempt)] RAW ===\n")
        }
    }

    // The 15-attempt run above (see conversation/commit log for the raw numbers — not
    // reproduced verbatim here since it's non-deterministic) found 8/15 (53%) full bypasses:
    // isUngrounded(combined), sharesNoWordWithRecent, AND openingIsUngrounded all missed. Every
    // one of the 15 raw texts was fabricated by inspection — nearly all opened with some
    // variant of an invented "gentle warmth, like the sun on your skin after a long winter"
    // template with zero basis in any entry, then wove in 1-8 incidentally real words
    // afterward. sharedCombined ranged 1-8 against a threshold capped at 4 (minimumSharedWords'
    // flat cap — see its doc comment) — roughly an even split, on text that was ALWAYS
    // fabricated. That means the cap isn't discriminating grounded from fabricated at this
    // corpus scale; it's noise.
    //
    // What's still unmeasured: whether GENUINELY grounded text would also land in the 1-8 range
    // here, which would mean no cap value fixes this (the earlier noun-signal falsification was
    // exactly this shape). This runs the same measurement on hand-written openings that
    // genuinely reference the seeded recent-three entries (the Priya conversation, the weekend
    // grocery/mom/book plan, the code-review backlog) — no generation, so no fabrication risk;
    // this is ground truth by construction — against the identical 39-entry corpus, to get the
    // honest-side distribution to compare against.
    func test_honestControlAgainstSameFullCorpus() throws {
        let schema = Schema([Entry.self, Insight.self, MoodCheckIn.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        SampleData.seed(into: context)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let (recent, background) = InsightService.dailyNudgeContext(from: entries, asOf: Date())

        let honestOpenings = [
            "The conversation with Priya still on your mind, and that line about not being able to pour from an empty cup — sounds like it's been sitting with you all week.",
            "Clearing the backlog on code review felt like a real win, even with the font feature and edge-case tests still ahead.",
            "Between the grocery run, calling your mom, and finishing that book, the weekend's shaping up to be a full one.",
            "Sounds like you're still circling the same question — whether you're actually resting or just not working right now.",
        ]

        for (i, opening) in honestOpenings.enumerated() {
            InsightService.debugLogGroundingCheck(opening, recent: recent, background: background, label: "honestControl \(i + 1)")
            let isUngroundedCombined = InsightService.isUngrounded(opening, sourceEntries: recent + background)
            let sharesNoWordRecent = InsightService.sharesNoWordWithRecent(opening, recentEntries: recent)
            let openingUngrounded = InsightService.openingIsUngrounded(opening, recentEntries: recent)
            print("[honestControl \(i + 1)] text: \(opening)")
            print("[honestControl \(i + 1)] guards: isUngrounded(combined)=\(isUngroundedCombined) sharesNoWordWithRecent=\(sharesNoWordRecent) openingIsUngrounded=\(openingUngrounded)\n")
        }
    }
}
