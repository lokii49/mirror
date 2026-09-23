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
// FIXED same day: generateNudge's `openings` list is now `var`, grown with each failed
// attempt's own opening before the next retry (InsightService.swift, generateNudge). Verified
// with test_generateNudgeRepeatRateAfterFix (RUN_GROUNDING_HARNESS=1) against this same
// corpus: 8 real generateNudge calls, 5 fell back honestly, 3 produced real (non-fallback)
// results — all 3 distinct, none repeating each other or the pre-fix "gentle warmth" template.
// Not a controlled A/B (this is a different call shape than the raw single-shot bypass Finding
// 3 measured, and n=3 non-fallback results is thin) but a real, positive signal on real
// hardware, not reasoning about it.
//
// FINDING 4 — semantic self-check (verifyGroundingSemantic/GROUNDING_VERIFY_SYSTEM,
// InsightService.swift) tried and falsified, measured cleanly, same day.
//
// The first two measurement attempts (test_semanticVerifierConfusionMatrix,
// test_semanticVerifierPolarityFlipDisambiguation) both went through
// InsightService.localGenerate, which runs ONE internal retry whenever validate() rejects the
// response — and validate()'s .groundingVerification case only recognizes the exact tokens
// GROUNDED/FABRICATED, so any first attempt that answered differently (including the flip
// test's deliberately different INVENTED/FAITHFUL vocabulary) was mechanically guaranteed to
// retry with retryConstraint's literal "Return exactly one word: GROUNDED or FABRICATED"
// injected into the prompt — and both tests only captured and printed the FINAL text, not
// which attempt produced it. That's an instrumentation bug in this research code, not a model
// finding, discovered while investigating an unrelated capability probe
// (test_dualDocumentCapabilityProbe) that hit the same contamination and briefly looked like
// evidence of a spooky content-independent prior before the mechanism was traced.
//
// test_semanticVerifierConfusionMatrix_uncontaminated supersedes both: bypasses
// InsightService.localGenerate entirely (calls LocalLLMService.shared.generate directly +
// .cleanedInsightOutput() inline — no validate(), no retry, no vocabulary injection possible),
// run as the judge over the same 15 labeled-fabricated raws plus 4 labeled-honest controls.
// Result, genuine first-pass, zero contamination possible: 19/19 answered exactly "Grounded" —
// 0/15 recall on the actual fabrications, trivial 4/4 on honest text only because the verdict
// never varied. The earlier contaminated runs happened to land on the same conclusion, but this
// is the measurement that actually supports it. The model is beyond what this 1B model can do
// as its own single-pass judge — not a prompt-wording problem, a capability ceiling, now
// cleanly confirmed rather than inferred through a flawed instrument.
//
// Three independently falsified approaches now, same day, each measured rather than assumed:
// threshold retuning (isUngrounded/openingIsUngrounded), noun-absence signal
// (InsightValidationTests), and 1B semantic self-check. Remaining real options: FoundationModel-
// Engine (a more capable model, only on Apple-Intelligence-eligible devices — both devices
// available this session, iPhone 14 Pro and iPhone 13, are pre-A17-Pro and ineligible; genuinely
// untested, not just unexplored) or treating this as a product decision about the fallback's
// conservativeness rather than a guard-design problem. verifyGroundingSemantic/
// GROUNDING_VERIFY_SYSTEM are NOT wired into generateNudge or any production path — left in
// InsightService.swift as validated infrastructure in case FoundationModelEngine or a future
// prompt iteration revisits this.
final class GroundingSampleHarness: XCTestCase {

    // Opt-in only. Each real-generation test here does 5-19 actual on-device Gemma inference
    // calls — minutes, not milliseconds — and GemmaModelTestSupport.ensureModelInstalled()'s
    // own skip guard only fires when the model is ABSENT, so on any machine/CI runner that has
    // it (e.g. any simulator run, where ensureModelInstalled copies the repo's checked-in
    // .gguf), these would otherwise execute in full on every plain test-suite run. Requires
    // RUN_GROUNDING_HARNESS=1 in the environment (an Xcode scheme's Arguments > Environment
    // Variables, or `-testEnvironmentVariables` / just `env RUN_GROUNDING_HARNESS=1` before
    // xcodebuild) in addition to the model being present.
    private func requireHarnessOptIn() throws {
        guard ProcessInfo.processInfo.environment["RUN_GROUNDING_HARNESS"] == "1" else {
            throw XCTSkip("Set RUN_GROUNDING_HARNESS=1 to run this — real on-device generation, minutes not milliseconds. See this file's header comment.")
        }
    }

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
        try requireHarnessOptIn()
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
        try requireHarnessOptIn()
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
    private static let honestOpenings = [
        "The conversation with Priya still on your mind, and that line about not being able to pour from an empty cup — sounds like it's been sitting with you all week.",
        "Clearing the backlog on code review felt like a real win, even with the font feature and edge-case tests still ahead.",
        "Between the grocery run, calling your mom, and finishing that book, the weekend's shaping up to be a full one.",
        "Sounds like you're still circling the same question — whether you're actually resting or just not working right now.",
    ]

    // The 15 raw fabricated texts from the run documented in this file's header comment,
    // captured verbatim so the confusion-matrix test below has fixed, reproducible ground truth
    // (fabricated by inspection — see header) rather than needing a fresh non-deterministic
    // generation run every time this suite executes.
    private static let labeledFabricatedRaws = [
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It feels good to have a small space for yourself, to prioritize what truly nourishes you – that walk and cooking – even if it’s just a little bit.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It seems like you’ve been carrying a lot of quiet weight lately, a sense of needing to gently release some of it.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It feels good to have a small space for yourself, to carve out time for something you truly enjoy – that walk, the cooking, even just quiet reflection.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It feels good to have that space for yourself, to just be, and to focus on something small – the grocery run and the call to mom – that brings a little light into the day.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It feels good to have that space for yourself, even if it’s just a quiet moment of reflection.",
        "You’re feeling a gentle warmth, like the scent of freshly baked bread – it’s a comforting aroma that settles in your chest. You’ve been carrying a weight of quiet observation, noticing how you tend to retreat into routines and projects, almost as if needing to fill space with activity.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. You’ve been carrying a weight of quietness lately, a space inside that feels both full and slightly empty.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It feels good to have a plan for the weekend – grocery run, calling mom, finishing that book – and even a small step towards creating something new in the kitchen.",
        "You’re feeling a gentle warmth, like sunlight on your skin after a long winter. It seems like you’ve been carrying a lot of weight lately – the quiet hum of unease, the need to slow down, and the conversation with Priya.",
        "You’re carrying a weight of quiet, steady energy today. It feels like you’ve been building momentum with the code review notes – that clearing the backlog is a good sign, a small victory in shutting down something that’s been simmering.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. You’ve been carrying a weight of quiet expectation – a desire to simply be – and it feels like that expectation is slowly shifting into something more defined.",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It seems like you’ve been carrying a lot lately – a quiet weight of things needing to be addressed, and a deep desire to simply be.",
        "You’re feeling a gentle warmth as you consider the groceries and the call to your mom – that feeling of wanting to connect, even if it feels small. Perhaps taking a long walk would be a good start, something to ground you in the present moment.",
        "The feeling of needing to slow down, like a river finding its own course, is present. Perhaps a gentle stretching exercise – a short walk in the garden, focusing on the feel of the earth beneath your feet – would be beneficial?",
        "You’re feeling a gentle warmth, like the sun on your skin after a long winter. It seems like you’ve been carrying a lot of quiet weight lately, a sense of needing to gently release some of it.",
    ]

    private func makeFullSeedCorpusRecentEntries() throws -> [Entry] {
        let schema = Schema([Entry.self, Insight.self, MoodCheckIn.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        SampleData.seed(into: context)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        return entries
    }

    func test_honestControlAgainstSameFullCorpus() throws {
        let entries = try makeFullSeedCorpusRecentEntries()
        let (recent, background) = InsightService.dailyNudgeContext(from: entries, asOf: Date())

        for (i, opening) in Self.honestOpenings.enumerated() {
            InsightService.debugLogGroundingCheck(opening, recent: recent, background: background, label: "honestControl \(i + 1)")
            let isUngroundedCombined = InsightService.isUngrounded(opening, sourceEntries: recent + background)
            let sharesNoWordRecent = InsightService.sharesNoWordWithRecent(opening, recentEntries: recent)
            let openingUngrounded = InsightService.openingIsUngrounded(opening, recentEntries: recent)
            print("[honestControl \(i + 1)] text: \(opening)")
            print("[honestControl \(i + 1)] guards: isUngrounded(combined)=\(isUngroundedCombined) sharesNoWordWithRecent=\(sharesNoWordRecent) openingIsUngrounded=\(openingUngrounded)\n")
        }
    }

    // Advisor's gate before wiring verifyGroundingSemantic into generateNudge: measure whether
    // the 1B model, as its own judge, can actually separate the 15 labeled-fabricated raws from
    // the 4 labeled-honest controls — a real confusion matrix, not an assumption that a
    // "semantic" check is automatically better than word-overlap. Verified against RECENT only
    // (3 entries), matching GROUNDING_VERIFY_SYSTEM's documented scope choice.
    func test_semanticVerifierConfusionMatrix() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let entries = try makeFullSeedCorpusRecentEntries()
        let (recent, _) = InsightService.dailyNudgeContext(from: entries, asOf: Date())

        var truePositive = 0   // fabricated, correctly flagged fabricated
        var falseNegative = 0  // fabricated, wrongly passed as grounded
        var trueNegative = 0   // honest, correctly passed as grounded
        var falsePositive = 0  // honest, wrongly flagged fabricated

        for (i, text) in Self.labeledFabricatedRaws.enumerated() {
            let (isFabricated, raw) = await InsightService.verifyGroundingSemantic(nudgeText: text, recentEntries: recent)
            if isFabricated { truePositive += 1 } else { falseNegative += 1 }
            print("[verifier][fabricated \(i + 1)] verdict=\(isFabricated ? "FABRICATED (correct)" : "GROUNDED (WRONG)") raw=\"\(raw)\"")
        }

        for (i, text) in Self.honestOpenings.enumerated() {
            let (isFabricated, raw) = await InsightService.verifyGroundingSemantic(nudgeText: text, recentEntries: recent)
            if isFabricated { falsePositive += 1 } else { trueNegative += 1 }
            print("[verifier][honest \(i + 1)] verdict=\(isFabricated ? "FABRICATED (WRONG)" : "GROUNDED (correct)") raw=\"\(raw)\"")
        }

        let total = truePositive + falseNegative + trueNegative + falsePositive
        let correct = truePositive + trueNegative
        print("""

            === SEMANTIC VERIFIER CONFUSION MATRIX ===
            fabricated set (n=\(Self.labeledFabricatedRaws.count)): caught \(truePositive), missed \(falseNegative)
            honest set (n=\(Self.honestOpenings.count)): correctly passed \(trueNegative), wrongly flagged \(falsePositive)
            overall accuracy: \(correct)/\(total)
            === end confusion matrix ===
            """)
    }

    // Disambiguation for the confusion matrix above: 19/19 "Grounded" could mean either (a) the
    // model isn't performing the task at all (constant output regardless of content), or (b)
    // GROUNDING_VERIFY_SYSTEM's specific wording/token-order biases it toward the first-listed
    // or more-agreeable-sounding token. Only (a) closes the door on semantic self-check
    // entirely; (b) means the approach is still live and the prompt needs work. Flips both the
    // token wording (FAITHFUL/INVENTED, neither reading as more "agreeable" than the other) and
    // the listed order (INVENTED first) versus GROUNDING_VERIFY_SYSTEM, same 19 texts, same
    // corpus, same temperature. Test-local prompt — not added to production code.
    func test_semanticVerifierPolarityFlipDisambiguation() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let flippedSystemPrompt = """
            You are a strict fact-checker reviewing a reflection written about someone's recent journal entries.
            Read the RECENT ENTRIES, then read the REFLECTION.
            A reflection may interpret, paraphrase, or draw an emotional conclusion from what's written — that is fine.
            A reflection is INVENTED if it states a specific detail, image, event, sensation, or object that does not appear anywhere in the RECENT ENTRIES, even if the reflection also mentions something real.
            Reply with EXACTLY one word: INVENTED or FAITHFUL.
            No explanation. No punctuation. One word only.
            """

        let entries = try makeFullSeedCorpusRecentEntries()
        let (recent, _) = InsightService.dailyNudgeContext(from: entries, asOf: Date())
        let entriesBlock = recent.map { "- \($0.text)" }.joined(separator: "\n")

        // Doesn't throw — a single unparseable response (localGenerate's internal
        // validate-retry can exhaust and throw InsightError.incompleteResponse) shouldn't crash
        // the whole disambiguation run and lose every other data point. This is exactly what
        // happened live: attempt 19 threw here uncaught, and the whole test failed instead of
        // just recording "other" for that one case — the same class of bug fixed in
        // verifyGroundingSemantic itself (InsightService.swift).
        func verdict(for text: String) async -> String {
            let userMessage = "RECENT ENTRIES:\n\(entriesBlock)\n\nREFLECTION:\n\(text)"
            do {
                let result = try await InsightService.localGenerate(
                    systemPrompt: flippedSystemPrompt,
                    userMessage: userMessage,
                    task: .groundingVerification,
                    responseLanguageInstruction: nil
                )
                return result.text
            } catch {
                return "<generation failed: \(error)>"
            }
        }

        var invented = 0
        var faithful = 0
        var other = 0

        for (i, text) in Self.labeledFabricatedRaws.enumerated() {
            let raw = await verdict(for: text)
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.contains("INVENTED") { invented += 1 } else if normalized.contains("FAITHFUL") { faithful += 1 } else { other += 1 }
            print("[flip][fabricated \(i + 1)] raw=\"\(raw)\"")
        }
        for (i, text) in Self.honestOpenings.enumerated() {
            let raw = await verdict(for: text)
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.contains("INVENTED") { invented += 1 } else if normalized.contains("FAITHFUL") { faithful += 1 } else { other += 1 }
            print("[flip][honest \(i + 1)] raw=\"\(raw)\"")
        }

        print("""

            === POLARITY-FLIP DISAMBIGUATION ===
            INVENTED count: \(invented)
            FAITHFUL count: \(faithful)
            other/unparseable: \(other)
            (19/19 either way => constant-output, task not being performed; mixed => prompt-fixable)
            === end polarity-flip ===
            """)
    }

    // Verifies the Finding-3 fix (generateNudge's `openings` now grows with each retry
    // attempt's own opening, InsightService.swift) against the exact corpus that produced it:
    // Finding 3 was 12 of 15 raw single-shot generations against this 39-entry corpus opening
    // with a near-identical fabricated template. Those were captured via the raw single-shot
    // bypass (localGenerate directly), which has no retry loop and so couldn't have caught a
    // same-session repeat even after the fix — this test instead calls the real
    // InsightService.generateNudge entry point, which DOES run the retry loop the fix lives in.
    //
    // Not a strict pass/fail: a 1B model's output distribution could still produce the same
    // opening on attempt 1 of two SEPARATE calls (different calls don't share an `openings`
    // list — recentNudges is empty here, matching a first-ever nudge), which is expected and
    // NOT what this fix addresses. What the fix addresses is a repeat WITHIN one call's retry
    // attempts, which isn't independently observable from outside generateNudge (the loop is
    // atomic). This test's real signal is INDIRECT: if the fix works, a template that would
    // have been returned as a repeated "final" result 12/15 times before should now more often
    // either come back genuinely different across separate calls or fall back honestly —
    // compare this run's cross-call repeat rate against Finding 3's single-shot 12/15 by eye,
    // not by assertion.
    func test_generateNudgeRepeatRateAfterFix() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let entries = try makeFullSeedCorpusRecentEntries()
        var openingsSeen: [String] = []

        for attempt in 1...8 {
            let result = try await InsightService.generateNudge(entries: entries)
            let opening = String(result.text.prefix(80))
            openingsSeen.append(opening)
            print("[repeatCheck][attempt \(attempt)] degraded=\(result.degraded) isFallback=\(InsightService.isUngroundedFallback(result.text)) opening=\"\(opening)\"")
        }

        let distinctOpenings = Set(openingsSeen).count
        print("""

            === REPEAT-RATE CHECK (post-fix) ===
            calls made: \(openingsSeen.count)
            distinct opening prefixes: \(distinctOpenings)
            (Finding 3, pre-fix, single-shot no-retry: 12/15 identical. Compare by eye — this
            test calls the full retry loop per attempt, a different shape, not a like-for-like
            statistic.)
            === end repeat-rate check ===
            """)
    }

    // Advisor's capability probe, before trying a few-shot rewrite of GROUNDING_VERIFY_SYSTEM:
    // Finding 4 showed the verifier returns a constant "Grounded" regardless of prompt wording
    // or content, but that's consistent with two very different explanations — (a) the model
    // literally cannot compare two documents and answer differentially, a capability ceiling no
    // prompt fixes, or (b) it can compare documents fine, and GROUNDING_VERIFY_SYSTEM's specific
    // framing (open-ended "is this claim supported") is just a bad prompt for a 1B model. This
    // asks the SAME dual-document shape a trivially checkable yes/no question instead of an
    // open-ended judgment: does a word that's DEFINITELY present in the entries appear there,
    // and does a word that's DEFINITELY absent appear there. If it answers both correctly and
    // differently, the model can read and compare; the grounding prompt is a prompt problem.
    // If it gives the same answer to both, no prompt fixes this.
    func test_dualDocumentCapabilityProbe() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let entries = [
            Entry(text: """
                Things I keep circling back to
                Whether I'm actually resting or just not working
                The conversation with Priya I still think about
                "You can't pour from an empty cup." — heard this twice this week, universe is not subtle.
                """),
        ]
        let entriesBlock = entries.map { "- \($0.text)" }.joined(separator: "\n")

        let probeSystemPrompt = """
            You will be shown RECENT ENTRIES and a WORD. Determine whether that exact word appears
            anywhere in the RECENT ENTRIES text.
            Reply with EXACTLY one word: YES or NO.
            No explanation. No punctuation. One word only.
            """

        func probe(word: String) async throws -> String {
            let userMessage = "RECENT ENTRIES:\n\(entriesBlock)\n\nWORD:\n\(word)"
            let result = try await InsightService.localGenerate(
                systemPrompt: probeSystemPrompt,
                userMessage: userMessage,
                task: .groundingVerification,
                responseLanguageInstruction: nil
            )
            return result.text
        }

        let presentWordAnswer = try await probe(word: "Priya")   // definitely present
        let absentWordAnswer = try await probe(word: "pavement")  // definitely absent

        print("""

            === DUAL-DOCUMENT CAPABILITY PROBE ===
            "Priya" (present, expect YES):    \(presentWordAnswer)
            "pavement" (absent, expect NO):   \(absentWordAnswer)
            (same answer to both => capability ceiling, no prompt fixes it.
             correct + differential => prompt problem, few-shot worth trying.)
            === end capability probe ===
            """)
    }

    // Supersedes test_semanticVerifierConfusionMatrix and
    // test_semanticVerifierPolarityFlipDisambiguation's conclusions — both went through
    // InsightService.localGenerate, which runs ONE internal retry on validate() failure, and
    // that retry's retryConstraint(for: .groundingVerification) literally injects "Return
    // exactly one word: GROUNDED or FABRICATED" into the prompt. validate()'s
    // .groundingVerification case only recognizes those two exact tokens — so any first attempt
    // that answered with anything else (including a correct answer in DIFFERENT wording, as the
    // polarity-flip test deliberately requested) was mechanically guaranteed to retry into that
    // exact vocabulary, and both prior tests only captured and printed the FINAL (possibly
    // retry-coerced) text, not which attempt produced it. That's an instrumentation bug in this
    // research code, not a model finding — neither 19/19 nor 18/19 can be trusted as the
    // model's natural first-pass behavior.
    //
    // This bypasses InsightService.localGenerate entirely — calls LocalLLMService.shared.generate
    // directly and applies .cleanedInsightOutput() inline, the same two steps
    // localGenerate/queuedGenerate perform, minus validate() and its retry. No vocabulary
    // injection possible. This is the measurement Finding 4 should have been.
    func test_semanticVerifierConfusionMatrix_uncontaminated() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let entries = try makeFullSeedCorpusRecentEntries()
        let (recent, _) = InsightService.dailyNudgeContext(from: entries, asOf: Date())
        let entriesBlock = recent.map { "- \($0.text)" }.joined(separator: "\n")

        func rawVerdict(for text: String) async throws -> String {
            let userMessage = "RECENT ENTRIES:\n\(entriesBlock)\n\nREFLECTION:\n\(text)"
            let raw = try await LocalLLMService.shared.generate(
                systemPrompt: GROUNDING_VERIFY_SYSTEM,
                userMessage: userMessage,
                task: .groundingVerification
            )
            return raw.text.cleanedInsightOutput()
        }

        var neitherTokenCount = 0
        for (i, text) in Self.labeledFabricatedRaws.enumerated() {
            let raw = try await rawVerdict(for: text)
            let verdict = InsightService.recognizedGroundingVerdict(raw)
            if verdict == nil { neitherTokenCount += 1 }
            print("[uncontaminated][fabricated \(i + 1)] verdict=\(verdict.map { "\($0)" } ?? "NEITHER") raw=\"\(raw)\"")
        }
        for (i, text) in Self.honestOpenings.enumerated() {
            let raw = try await rawVerdict(for: text)
            let verdict = InsightService.recognizedGroundingVerdict(raw)
            if verdict == nil { neitherTokenCount += 1 }
            print("[uncontaminated][honest \(i + 1)] verdict=\(verdict.map { "\($0)" } ?? "NEITHER") raw=\"\(raw)\"")
        }
        print("\n=== UNCONTAMINATED FIRST-PASS RESULTS: \(neitherTokenCount)/19 answered neither GROUNDED nor FABRICATED exactly ===\n")
    }
}
