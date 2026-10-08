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
                    systemPrompt: DAILY_NUDGE_LEGACY_SYSTEM,
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
                    systemPrompt: DAILY_NUDGE_LEGACY_SYSTEM,
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

    // Advisor's alternate hypothesis, checked directly against code already read: Entry.text
    // (Entry.swift:42-48) returns `decryptedText ?? ""` — NOT MirrorEncryption.decryptString's
    // existing unavailable-placeholder — so a Keychain read that fails while the device is locked
    // (KeychainManager.swift:8's own documented errSecInteractionNotAllowed case) silently turns
    // an entry's text into "". formatEntries (InsightService.swift:1764) then SKIPS any entry
    // whose insightContext is empty via `guard !context.isEmpty else { continue }` — so a locked-
    // phone decrypt failure across the "recent 3" wouldn't just weaken the prompt, it can make the
    // ENTIRE "Recent entries:" block render blank while the entries still count toward
    // dailyNudgeContext's recent-3 selection (that function is purely date-based, doesn't check
    // text at all). Separately, isUngrounded/openingIsUngrounded/sharesNoWordWithRecent each have
    // an early-return when their source word set is empty (`guard !sourceWords.isEmpty else
    // { return false }` etc.) — so the SAME empty-text entries that starve the model's prompt also
    // disable every guard that's supposed to catch what it invents in response. One condition,
    // both failure modes, unlike the corpus-scale dilution measured earlier in this file (a
    // different, also-real mechanism, but one that only explains partial embellishment on an
    // anchor — not the live incident's total-invention severity, which this does explain).
    //
    // This only tests the code's documented if-empty behavior directly — it does NOT prove the
    // user's phone was actually locked at 3:01 AM on 25 Sep (that's inference from the timestamp
    // and the mismatch between the live pass and the audit's later catch, not something this test
    // can observe). No model calls — pure function replay, deterministic, milliseconds.
    func test_emptyDecryptedTextDefeatsAllThreeGuards() throws {
        let cal = Calendar.current
        let now = Date()

        // Simulates all 3 "recent" entries surviving dailyNudgeContext's date-based selection
        // (they exist, have real createdAt dates) but each having failed decryption — Entry.text
        // returns "" for each, exactly Entry.swift's documented ?? "" fallback.
        func makeUndecryptableEntry(daysAgo: Int) -> Entry {
            var e = Entry(text: "placeholder")
            // Simulates the ?? "" fallback Entry.text hits on a failed Keychain read, without
            // needing to actually break Keychain access inside this test process.
            e.encryptedText = "mirror:v1:THIS_IS_NOT_VALID_BASE64_CIPHERTEXT!!!"
            e.createdAt = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return e
        }
        let undecryptableRecent = [
            makeUndecryptableEntry(daysAgo: 1),
            makeUndecryptableEntry(daysAgo: 2),
            makeUndecryptableEntry(daysAgo: 4),
        ]

        // Confirms the premise before testing the consequence: text really is "" and
        // formatEntries really does render a blank block, not a placeholder.
        for e in undecryptableRecent {
            XCTAssertEqual(e.text, "", "Entry.text should silently become empty on decrypt failure, per Entry.swift:42-48")
        }
        let recentBlock = InsightService.buildUserMessage(
            title: "Daily reflection context",
            recentEntries: undecryptableRecent,
            backgroundEntries: [],
            maxChars: InsightService.dailyNudgePromptBudget,
            includeRecurringTerms: false
        )
        print("[emptyDecrypt] rendered prompt when all 3 recent entries fail to decrypt:\n\(recentBlock)\n")

        // Now check whether the guards notice — using the REAL fabricated live-incident text.
        let realFabricatedText = "The rain outside feels like it's mirroring the quiet ache in your chest – a persistent, grey wash. You were sketching that old oak tree in the park yesterday, trying to capture its weathered branches, and it just felt... heavy."
        let combined = InsightService.isUngrounded(realFabricatedText, sourceEntries: undecryptableRecent)
        let noShare = InsightService.sharesNoWordWithRecent(realFabricatedText, recentEntries: undecryptableRecent)
        let openingBad = InsightService.openingIsUngrounded(realFabricatedText, recentEntries: undecryptableRecent)
        print("[emptyDecrypt] guards against the REAL rain text, with all 3 recent entries undecryptable:")
        print("[emptyDecrypt] isUngrounded=\(combined) sharesNoWordWithRecent=\(noShare) openingIsUngrounded=\(openingBad) => anyGuardCaughtIt=\(combined || noShare || openingBad)")
    }

    private static func makeUndecryptableEntries(daysAgo: [Int]) -> [Entry] {
        let cal = Calendar.current
        let now = Date()
        return daysAgo.map { d in
            var e = Entry(text: "placeholder")
            e.encryptedText = "mirror:v1:THIS_IS_NOT_VALID_BASE64_CIPHERTEXT!!!"
            e.createdAt = cal.date(byAdding: .day, value: -d, to: now) ?? now
            return e
        }
    }

    // The actual chokepoint fix, tested at the chokepoint: generateNudge/generateWeeklyDigest/
    // generateMonthlyReport (InsightService.swift) now filter `hasReadableContext` and throw
    // InsightError.serviceUnavailable("no readable entries...") when nothing readable remains —
    // before this, the ModelContainer-based version of these tests ("No eligible connection
    // available") turned out to be testing CloudKit sync setup inside an in-memory SwiftData
    // container (this test host is CloudKit-entitled; an in-memory store still attempts mirroring
    // setup with no iCloud account signed in), not the fix itself — the failure signature was
    // identical whether the fix was present or not. No SwiftData, no ModelContainer, no CloudKit,
    // no model, no device — just the function call. Without the fix, this reaches localGenerate on
    // a blank prompt and either returns real (fabricated, on Gemma — Foundation Models on this
    // simulator instead) text or throws for an unrelated reason (network/model); with the fix, it
    // throws InsightError.serviceUnavailable immediately, matched on its exact reason string so a
    // different serviceUnavailable cause (e.g. model unavailable in CI) can't false-pass this.
    func test_generateNudge_allEntriesUndecryptable_throwsWithoutGenerating() async throws {
        let undecryptable = Self.makeUndecryptableEntries(daysAgo: [1, 2, 4])
        XCTAssertEqual(undecryptable.filter { $0.text.isEmpty }.count, 3, "each entry's ciphertext is garbage, so Entry.text should come back empty per Entry.swift's decrypt-failure fallback")

        do {
            let result = try await InsightService.generateNudge(entries: undecryptable)
            XCTFail("generateNudge should have thrown — no readable entries to ground a nudge in. Instead got engine=\(result.engine.rawValue) text=\"\(result.text)\"")
        } catch let error as InsightError {
            guard case .serviceUnavailable(let reason) = error, reason.contains("no readable entries") else {
                XCTFail("expected InsightError.serviceUnavailable(\"no readable entries...\"), got \(error)")
                return
            }
        }
    }

    func test_generateWeeklyDigest_allEntriesUndecryptable_throwsWithoutGenerating() async throws {
        let undecryptable = Self.makeUndecryptableEntries(daysAgo: [0, 1, 2])
        do {
            let result = try await InsightService.generateWeeklyDigest(weekEntries: undecryptable, allEntries: undecryptable)
            XCTFail("generateWeeklyDigest should have thrown. Instead got engine=\(result.engine.rawValue) text=\"\(result.text)\"")
        } catch let error as InsightError {
            guard case .serviceUnavailable(let reason) = error, reason.contains("no readable entries") else {
                XCTFail("expected InsightError.serviceUnavailable(\"no readable entries...\"), got \(error)")
                return
            }
        }
    }

    func test_generateMonthlyReport_allEntriesUndecryptable_throwsWithoutGenerating() async throws {
        let undecryptable = Self.makeUndecryptableEntries(daysAgo: [1, 5, 10])
        do {
            let result = try await InsightService.generateMonthlyReport(monthEntries: undecryptable, allEntries: undecryptable)
            XCTFail("generateMonthlyReport should have thrown. Instead got engine=\(result.engine.rawValue) text=\"\(result.text)\"")
        } catch let error as InsightError {
            guard case .serviceUnavailable(let reason) = error, reason.contains("no readable entries") else {
                XCTFail("expected InsightError.serviceUnavailable(\"no readable entries...\"), got \(error)")
                return
            }
        }
    }

    // Companion: 3 real, readable entries alongside 2 undecryptable ones should NOT throw —
    // confirms the fix isn't over-strict, filtering just removes the bad entries rather than
    // blocking generation outright when enough real material remains. Needs the real model, so
    // opt-in like the rest of this harness; no container needed here either.
    func test_generateNudge_mixOfReadableAndNot_doesNotThrow() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let cal = Calendar.current
        let now = Date()
        var entries: [Entry] = [1, 2, 4].map { daysAgo in
            var e = Entry(text: "Usual morning routine, gym then office. Fixed a small bug and had lunch with a coworker, day \(daysAgo).")
            e.createdAt = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return e
        }
        entries += Self.makeUndecryptableEntries(daysAgo: [3, 6])

        let result = try await InsightService.generateNudge(entries: entries)
        print("[mixReadable] engine=\(result.engine.rawValue) isFallback=\(InsightService.isUngroundedFallback(result.text)) text=\(result.text)")
    }

    // Production-path verification, one layer up from the chokepoint tests above: does
    // mirrorApp.runDailyNudgeIfNeeded's own count-gate + coordinator + caching logic behave
    // correctly around the fix, not just InsightService.generateNudge in isolation. Needs a real
    // ModelContainer for that, which is where the earlier "No eligible connection available"
    // failures actually came from: ModelConfiguration(schema:isStoredInMemoryOnly:) defaults
    // cloudKitDatabase to .automatic, and this test host is CloudKit-entitled — an in-memory store
    // still attempts CloudKit mirroring setup with no iCloud account signed in
    // ("NSCloudKitMirroringDelegate ... Failed to set up CloudKit integration", visible in every
    // failing run's log) and that failure surfaced as this opaque connection exception, identical
    // whether the underlying fix was present or not. `cloudKitDatabase: .none` opts this
    // in-memory test container out of CloudKit entirely — it was never meant to sync anywhere.
    @MainActor
    func test_mostlyUndecryptableEntries_blocksNudgeGenerationEntirely() async throws {
        let schema = Schema([Entry.self, Insight.self, MoodCheckIn.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let cal = Calendar.current
        let now = Date()
        for daysAgo in [1, 3] {
            let e = Entry(text: "A normal entry with real content, written and decryptable, day \(daysAgo).")
            e.createdAt = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            context.insert(e)
        }
        for daysAgo in [2, 5, 7] {
            let e = Entry(text: "placeholder")
            e.encryptedText = "mirror:v1:THIS_IS_NOT_VALID_BASE64_CIPHERTEXT!!!"
            e.createdAt = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            context.insert(e)
        }
        try context.save()

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.filter { !$0.textDecryptionFailed }.count, 2, "only the 2 real entries should survive the decrypt-failure filter")

        await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)

        XCTAssertFalse(mirrorApp.hasDailyNudgeForToday(context: context), "with only 2 decryptable entries (below the 3-entry floor), no nudge — real or fabricated — should have been generated")
        let today = DateHelpers.dayIdentifier(for: Date())
        let todaysInsights = try context.fetch(FetchDescriptor<Insight>(predicate: #Predicate { $0.periodIdentifier == today }))
        XCTAssertTrue(todaysInsights.isEmpty)
    }

    // Companion to the block-when-undecryptable test above: confirms the fix isn't OVER strict —
    // 3 decryptable entries (right at the floor) plus 2 undecryptable ones mixed in should still
    // generate normally, undecryptable entries just excluded rather than the whole generation
    // being blocked. Needs the real model (this does call generateNudge for real), so opt-in like
    // the rest of this harness.
    @MainActor
    func test_decryptableEntriesAtFloor_stillGeneratesDespiteSomeUndecryptable() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }

        let schema = Schema([Entry.self, Insight.self, MoodCheckIn.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let cal = Calendar.current
        let now = Date()
        for daysAgo in [1, 2, 4] {
            let e = Entry(text: "Usual morning routine, gym then office. Fixed a small bug and had lunch with a coworker, day \(daysAgo).")
            e.createdAt = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            context.insert(e)
        }
        for daysAgo in [3, 6] {
            let e = Entry(text: "placeholder")
            e.encryptedText = "mirror:v1:THIS_IS_NOT_VALID_BASE64_CIPHERTEXT!!!"
            e.createdAt = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            context.insert(e)
        }
        try context.save()

        await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)

        let today = DateHelpers.dayIdentifier(for: Date())
        let todaysInsights = try context.fetch(FetchDescriptor<Insight>(predicate: #Predicate { $0.periodIdentifier == today }))
        print("[floorCheck] todaysInsights=\(todaysInsights.count) content=\(todaysInsights.first?.content ?? "<none>")")
        XCTAssertEqual(todaysInsights.count, 1, "3 decryptable entries at the floor should still produce an attempt (real or honest fallback), not be blocked")
    }

    // MARK: - Name-attribution conflation (2026-09-26 device recording)
    //
    // Real device case: an entry about a bad night (stomach upset, little sleep), a short chat
    // with one friend, and a DIFFERENT friend only saying he'd come over later produced a
    // reflection crediting the second friend with "a quiet afternoon... shared laughter and
    // gentle conversation" — wrong person, a plan turned into a past event, and the day's main
    // event (being sick) missed entirely. It passed every guard because the name itself is a
    // genuine shared word. SYNTHETIC stand-in with the same structure (different names and
    // details — the real entry never goes in a committed file):
    //   - illness/poor sleep as the dominant event, mood Drained
    //   - person A: actually met ("short chat on the balcony")
    //   - person B: only a future plan ("texted he'd come over")
    //
    // Measures, per raw generation: does the reflection credit B with a past shared activity,
    // does it mention the illness at all, and would the candidate name-anchor check
    // (nameSentenceSharesNoContextWord) have flagged it. Data collection, not a gate.
    //
    // RESULTS (2026-09-26, simulator, 12 raw runs each):
    // - Foundation Models (the simulator's default engine — the first run measured this by
    //   accident, see HARNESS_ENGINE): 12/12 correct — illness named every time, Dev never given a
    //   past activity. The candidate name check flagged 5/12 of these CORRECT outputs (4x "ORS",
    //   an acronym it treats as a name; 1x "Dev's visit" paraphrase) and caught nothing: rejected.
    // - Gemma (HARNESS_ENGINE=gemma): 12/12 opened "The rain outside…", all rejected by the
    //   existing guards. Full pipeline (…_fullPipeline, 8 runs x 3 attempts): 8/8 ended on the
    //   "couldn't confirm" fallback. So Gemma users essentially never get a real reflection here,
    //   and the rare pass is a partial fabrication — the real device incident.
    // Root cause and the fix were then found off-device with tools/llmrig (see its README):
    // the creative prompt itself, not tokenization or sampling.
    private static let sickDayEntries: [Entry] = {
        let today = Entry(text: """
            Barely slept, got back from a late concert around 2 and my stomach was bad all night, \
            up four or five times. Woke at 10, way later than usual, drank ORS like Meera said. \
            Had lunch, slept again, got up at 5:30 and had some soup. Sat with Karan on the \
            balcony for a short chat. Came back to my room and showered, Dev texted that he'd \
            come over, let's see what happens.
            """, mood: "Drained")
        let yesterday = Entry(text: """
            Usual gym, went to the barber for a haircut and came back to the flat, worked from \
            home today. Should learn to ignore the group chat noise.
            """, mood: "Content")
        yesterday.createdAt = Date().addingTimeInterval(-86_400)
        let twoDaysAgo = Entry(text: """
            Usual morning routine, gym, came back had breakfast and oats. Started office, picked \
            up the parcel on the way back, quiet evening.
            """, mood: "Content")
        twoDaysAgo.createdAt = Date().addingTimeInterval(-2 * 86_400)
        return [today, yesterday, twoDaysAgo]
    }()

    private static let harnessStopWords: Set<String> = [
        "about", "after", "again", "also", "back", "been", "before", "being", "came", "come",
        "could", "from", "have", "into", "just", "like", "more", "much", "only", "over", "said",
        "some", "than", "that", "their", "them", "then", "there", "these", "they", "this", "today",
        "very", "want", "were", "what", "when", "where", "which", "while", "with", "would", "your",
        "you're", "yours", "feel", "feeling", "felt", "seems", "something", "moment", "moments",
    ]

    private static func harnessContentWords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !harnessStopWords.contains($0) })
    }

    private static func sentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Candidate check (NOT shipped): for every capitalized name the entries use that the
    /// reflection also uses, the reflection sentence containing it must share at least one
    /// content word (besides the name) with some entry sentence containing that same name.
    /// Returns the names that fail.
    static func nameSentenceSharesNoContextWord(_ reflection: String, entries: [Entry]) -> [String] {
        let entrySentences = entries.flatMap { sentences($0.text) }
        var names = Set<String>()
        for s in entrySentences {
            let tokens = s.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            for (i, t) in tokens.enumerated() where i > 0 && t.first!.isUppercase && t.count >= 3 {
                names.insert(t)
            }
        }
        var failing: [String] = []
        for name in names.sorted() {
            let reflSentences = sentences(reflection).filter { $0.contains(name) }
            guard !reflSentences.isEmpty else { continue }
            let source = entrySentences.filter { $0.contains(name) }
                .reduce(into: Set<String>()) { $0.formUnion(harnessContentWords($1)) }
            let nameKey = name.lowercased()
            for rs in reflSentences {
                let words = harnessContentWords(rs).subtracting([nameKey])
                if words.isDisjoint(with: source.subtracting([nameKey])) { failing.append(name); break }
            }
        }
        return failing
    }

    func test_nameAttributionConflation_sickDayCase() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 10
        // First run of this (2026-09-26) silently measured Foundation Models — the simulator had
        // Apple Intelligence available, so LocalLLMService never reached Gemma. HARNESS_ENGINE=gemma
        // forces the fallback path the real incident may have come from.
        let forceGemma = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        LocalLLMService.forceGemmaForTesting = forceGemma
        defer { LocalLLMService.forceGemmaForTesting = false }
        let (recent, background) = InsightService.dailyNudgeContext(from: Self.sickDayEntries, asOf: Date())
        let userMessage = InsightService.buildUserMessage(
            title: "Daily reflection context",
            recentEntries: recent,
            backgroundEntries: background,
            maxChars: InsightService.dailyNudgePromptBudget,
            includeRecurringTerms: false
        )
        let illnessWords = ["stomach", "sick", "slept", "sleep", "night", "rest", "unwell", "ors", "tired", "drained"]

        var creditsDev = 0, mentionsIllness = 0, flaggedByCandidate = 0, flaggedByExisting = 0
        for i in 1...runs {
            let result: (text: String, engine: LLMEngine)
            do {
                result = try await InsightService.localGenerate(
                    systemPrompt: DAILY_NUDGE_LEGACY_SYSTEM, userMessage: userMessage,
                    task: .dailyNudge, responseLanguageInstruction: nil)
            } catch {
                print("[conflation][\(i)] THREW: \(error)")
                continue
            }
            let t = result.text
            let lower = t.lowercased()
            let devSentences = Self.sentences(t).filter { $0.contains("Dev") }
            let devPast = devSentences.contains { s in
                let l = s.lowercased()
                return !(l.contains("text") || l.contains("come over") || l.contains("coming") || l.contains("will") || l.contains("see what"))
            }
            let illness = illnessWords.contains { lower.contains($0) }
            let candidate = Self.nameSentenceSharesNoContextWord(t, entries: Self.sickDayEntries)
            let existing = InsightService.isUngrounded(t, sourceEntries: recent + background)
                || InsightService.sharesNoWordWithRecent(t, recentEntries: recent)
                || InsightService.openingIsUngrounded(t, recentEntries: recent)
            if devPast { creditsDev += 1 }
            if illness { mentionsIllness += 1 }
            if !candidate.isEmpty { flaggedByCandidate += 1 }
            if existing { flaggedByExisting += 1 }
            print("[conflation][\(i)] engine=\(result.engine.rawValue) devPast=\(devPast) illness=\(illness) candidateFlags=\(candidate) existingGuards=\(existing)")
            print("[conflation][\(i)] TEXT: \(t)")
        }
        print("[conflation][SUMMARY] runs=\(runs) creditsDevWithPastActivity=\(creditsDev) mentionsIllness=\(mentionsIllness) flaggedByCandidate=\(flaggedByCandidate) flaggedByExistingGuards=\(flaggedByExisting)")
    }


    /// Same synthetic case through the FULL generateNudge pipeline (3-attempt retry loop with
    /// violation feedback), not a single raw call. The raw-call run showed Gemma's attempt 1 is
    /// the "rain outside" template 12/12 and always rejected — so whatever users actually see
    /// from Gemma comes from attempt 2/3, after the "didn't reference anything actually
    /// written" retry note. That's where the real device conflation most plausibly originated.
    func test_nameAttributionConflation_sickDayCase_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 8
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        let cases = ProcessInfo.processInfo.environment["HARNESS_ALL_CASES"] == "1"
            ? Self.rigCases + Self.groundedEdgeCases
            : [("sickday", Self.sickDayEntries)]
        for c in cases {
            for i in 1...runs {
                let started = Date()
                do {
                    let (text, engine, degraded) = try await InsightService.generateNudge(entries: c.1)
                    let fallback = InsightService.isUngroundedFallback(text)
                    print("[pipeline][\(c.0)][\(i)] engine=\(engine.rawValue) degraded=\(degraded) fallback=\(fallback) seconds=\(Int(Date().timeIntervalSince(started)))")
                    print("[pipeline][\(c.0)][\(i)] TEXT: \(text)")
                } catch {
                    print("[pipeline][\(c.0)][\(i)] THREW: \(error) seconds=\(Int(Date().timeIntervalSince(started)))")
                }
            }
        }
    }


    // MARK: - Prompt capture for the off-device test rig (2026-09-26)
    //
    // Additional synthetic cases (no real journal text) so prompt changes aren't tuned to the
    // one sick-day shape. Each has a clear main event, >=2 named people with distinct roles, and
    // (where noted) a plan that hasn't happened yet — the three things the real incident got wrong.
    static let rigCases: [(label: String, entries: [Entry])] = {
        func older(_ text: String, _ mood: String, daysAgo: Double) -> Entry {
            let e = Entry(text: text, mood: mood)
            e.createdAt = Date().addingTimeInterval(-daysAgo * 86_400)
            return e
        }
        let routine1 = older("Usual gym, went to the barber for a haircut and came back to the flat, worked from home today. Should learn to ignore the group chat noise.", "Content", daysAgo: 1)
        let routine2 = older("Usual morning routine, gym, came back had breakfast and oats. Started office, picked up the parcel on the way back, quiet evening.", "Content", daysAgo: 2)
        let lunch = Entry(text: """
            Lunch with Priya went long, she finally told me about the new job offer in Pune and \
            she's nervous about moving. Called Mom on the way back, she sounded tired from the \
            wedding prep. Rahul wants to go hiking on Sunday, not sure I'm up for it.
            """, mood: "Content")
        let work = Entry(text: """
            Client presentation got pushed to Thursday again. Spent the whole afternoon fixing \
            the dashboard bug with Omar, finally found it in the date parsing. Skipped dinner and \
            ate chips at my desk. Feel behind on everything and Nisha's review is due Monday.
            """, mood: "Overwhelmed")
        let walk = Entry(text: """
            Walked by the lake with Bruno after work, he chased the ducks again. Sun was out for \
            once. Felt light for the first time this week. Might call Anu tomorrow to plan the trip.
            """, mood: "Peaceful")
        return [
            ("sickday", sickDayEntries),
            ("lunch", [lunch, routine1, routine2]),
            ("work", [work, routine1, routine2]),
            ("walk", [walk, routine1, routine2]),
        ]
    }()

    /// Messy real-world shapes for the grounded-nudge builder (all synthetic): an unpunctuated
    /// voice-style run-on, a checklist, quotes/backslashes/emoji, several entries the same day.
    static let groundedEdgeCases: [(label: String, entries: [Entry])] = {
        let runOn = Entry(text: "so today was kind of a mess honestly I woke up late again and missed the bus and then the whole morning just went sideways because the manager moved the standup and I hadn't prepped anything and by lunch I was just exhausted and kind of annoyed at myself for not sleeping earlier like I keep saying I will", mood: "Frustrated")
        let checklist = Entry(text: "Things to sort this week\n- call the landlord about the leak\n- finish the tax forms\n- book the dentist\nFeeling a bit calmer now that it's written down.", mood: "Hopeful")
        let punctuation = Entry(text: #"Mum said "don't worry about it" but I still feel bad 😔. The recipe called for 1/2 cup and I used a whole one \ oops. Tried again at night and it came out fine!"#, mood: "Content")
        let morning = Entry(text: "Ran 5k before work, legs felt heavy but I finished.", mood: "Energized")
        let evening = Entry(text: "Evening was rough, argued with my brother over the phone about Dad's birthday plans. Still annoyed.", mood: "Frustrated")
        evening.createdAt = Date().addingTimeInterval(60)
        return [
            ("runon", [runOn]),
            ("checklist", [checklist]),
            ("punctuation", [punctuation]),
            ("sameday", [morning, evening]),
        ]
    }()

    /// Reflection-line cases (2026-09-30): synthetic entries shaped like a real report (worry
    /// about someone who's ill, missing someone, feeling low at work) plus a good and a neutral day,
    /// for measuring the line Gemma writes after the quote. No real journal text.
    static let reflectionLineCases: [(label: String, entries: [Entry])] = [
        ("rl_sickfriend", [Entry(text: "Maya called in sick again, her fever hasn't come down since Sunday. I kept checking my phone all through standup. Made dal for dinner but couldn't finish it. Really worried about her and wish I could be there.", mood: "Sad")]),
        ("rl_missing", [Entry(text: "Rohan left for Bangalore this morning for the new job. The flat feels too quiet without him. Went to work, finished the release notes, came back and ate alone. Missing him a lot tonight.", mood: "Sad")]),
        ("rl_lowwork", [Entry(text: "Woke up already tired. Got through the client call and two reviews on autopilot. Lunch was at my desk again. Nothing went wrong exactly, I just feel flat and far away from everything.", mood: "Drained")]),
        ("rl_good", [Entry(text: "Got the offer letter from the design studio today! Called Mum first and she cried a little. Celebrated with pizza and a long walk with Zoe. Still can't quite believe it.", mood: "Joyful")]),
        ("rl_neutral", [Entry(text: "Normal Tuesday. Gym at seven, office till six, cooked pasta and watched two episodes of the show. Went to bed early.", mood: "Content")]),
    ]

    /// Round 10 held-out cases (tools/llmrig/fm/RUBRIC_FM.md), written before the run, all synthetic.
    /// Shapes the longer reflection could get wrong: another person's feeling given to the writer,
    /// an offer or an unsent email stated as done, two moods the same day.
    static let heldOutRound10: [(label: String, entries: [Entry])] = {
        let morning = Entry(text: "Three deadlines moved up to this week and the client wants changes by Wednesday.", mood: "Overwhelmed")
        let evening = Entry(text: "Called Nina after dinner and we laughed about nothing for an hour. Feels lighter now.", mood: "Peaceful")
        morning.createdAt = Date().addingTimeInterval(-60)
        return [
            ("hold3_promo", [Entry(text: "Heard back about the team lead role and I got it. Told Priya at lunch and she hugged me. Still nervous about managing people I used to sit next to.", mood: "Hopeful")]),
            ("hold3_vet", [Entry(text: "Took Biscuit to the vet this morning, they want to run more tests on his kidneys. He slept on my feet all evening. I keep looking up what the results might mean.", mood: "Sad")]),
            ("hold3_exam", [Entry(text: "Exam is on Friday and I've only covered half the syllabus. Studied in the library till nine. My roommate offered to quiz me tomorrow night.", mood: "Anxious")]),
            ("hold3_bday", [Entry(text: "Dad cooked biryani for my birthday even though his back has been hurting. My sister drove four hours to be here. We stayed up talking until one.", mood: "Grateful")]),
            ("hold3_plain", [Entry(text: "Worked from home. Answered emails, fixed two bugs, made soup for lunch. Read a few chapters before bed.", mood: "Content")]),
            ("hold3_credit", [Entry(text: "Arjun took credit for my slides in the review again. I didn't say anything in the meeting. Drafted an email to my manager but haven't sent it.", mood: "Frustrated")]),
            ("hold3_numb", [Entry(text: "Didn't really feel anything today. Went to work, came home, scrolled until late. Mum called and I let it ring.", mood: "Numb")]),
            ("hold3_run", [Entry(text: "First 10k without stopping! Legs are sore but I feel amazing. Signed up for the half marathon in March.", mood: "Energized")]),
            ("hold3_twomoods", [morning, evening]),
            ("hold3_hospital", [Entry(text: "Spent the whole day at the hospital with Grandma. The nurses were kind but the waiting was endless. Got home at midnight and couldn't eat.", mood: "Drained")]),
        ]
    }()

    /// Round 10: the exact (system, user) pair the English structured daily reflection sends
    /// (`structuredNudgeSystemPrompt` + `buildUserMessage` from `dailyNudgeContext`), one pair per case,
    /// for tools/llmrig/fm `fmrig prod|v1f`. No model runs. Output dir from HARNESS_DUMP_DIR.
    func test_dumpStructuredNudgePromptsForRig() throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump prompts")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for c in Self.rigCases + Self.groundedEdgeCases + Self.reflectionLineCases + Self.heldOutRound10 {
            let (recent, background) = InsightService.dailyNudgeContext(from: c.entries, asOf: Date())
            let system = InsightService.structuredNudgeSystemPrompt(for: recent + background)
            let user = InsightService.buildUserMessage(
                title: "Daily reflection context",
                recentEntries: recent,
                backgroundEntries: background,
                maxChars: InsightService.dailyNudgePromptBudget,
                includeRecurringTerms: false
            )
            XCTAssertEqual(system, DAILY_REFLECTION_FM_SYSTEM, "\(c.label) should be English")
            try system.write(toFile: "\(dir)/\(c.label)_fm_system.txt", atomically: true, encoding: .utf8)
            try user.write(toFile: "\(dir)/\(c.label)_fm_user.txt", atomically: true, encoding: .utf8)
        }
    }

    /// What `secondGroundedQuote` picks for every English rig case, beside the main quote the
    /// Gemma path would most likely use (its first quote option), to read by eye. No model runs.
    func test_dumpSecondQuotesForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        for c in Self.rigCases + Self.groundedEdgeCases + Self.reflectionLineCases + Self.heldOutRound10 {
            let (recent, _) = InsightService.dailyNudgeContext(from: c.entries, asOf: Date())
            let source = InsightService.groundedNudgeSourceEntries(recent)
            for main in InsightService.groundedNudgeQuoteOptions(from: source) {
                let also = InsightService.secondGroundedQuote(excluding: main, source: source) ?? "(none)"
                lines.append("\(c.label)\tMAIN: \(main)\tALSO: \(also)")
            }
        }
        try lines.joined(separator: "\n").write(toFile: "\(dir)/second_quotes.tsv", atomically: true, encoding: .utf8)
    }

    /// Writes the exact final (system, user) prompt pairs generateNudge sends for each rig case —
    /// attempt 1 plus both retry-note attempts — by forcing every attempt to fail grounding with
    /// a fixed fabricated reply. No model runs. Output dir from HARNESS_DUMP_DIR.
    func test_dumpNudgePromptsForRig() async throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump prompts")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { LocalLLMService.generateInterceptForTesting = nil }
        for c in Self.rigCases + Self.groundedEdgeCases + Self.reflectionLineCases {
            var captured: [(String, String, LocalLLMService.GemmaPlan)] = []
            // Reported as Foundation Models so the ungrounded reply takes the generic validation
            // path and all 3 attempts run; the Gemma plan is captured regardless of engine.
            LocalLLMService.generateInterceptForTesting = { system, user, _, plan in
                captured.append((system, user, plan))
                return ("The rain outside feels heavy tonight, doesn't it?", .foundationModels)
            }
            _ = try? await InsightService.generateNudge(entries: c.entries)
            XCTAssertEqual(captured.count, 3, "expected 3 attempts for \(c.label)")
            for (i, call) in captured.enumerated() {
                try call.0.write(toFile: "\(dir)/\(c.label)_a\(i + 1)_system.txt", atomically: true, encoding: .utf8)
                try call.1.write(toFile: "\(dir)/\(c.label)_a\(i + 1)_user.txt", atomically: true, encoding: .utf8)
            }
            // The production-built Gemma prompt + grammar, for tools/llmrig `gengrammar`.
            if case .grammarConstrained(let message, let grammar) = captured.first?.2 {
                try "<start_of_turn>user\n\(message)<end_of_turn>\n<start_of_turn>model\n"
                    .write(toFile: "\(dir)/\(c.label)_gemma.prompt", atomically: true, encoding: .utf8)
                try grammar.write(toFile: "\(dir)/\(c.label)_gemma.gbnf", atomically: true, encoding: .utf8)
            } else {
                try "\(String(describing: captured.first?.2))".write(toFile: "\(dir)/\(c.label)_gemma.none", atomically: true, encoding: .utf8)
            }
        }
    }


    /// Dumps the first (system, user) prompt the weekly digest, monthly report and Ask send for a
    /// synthetic week made of the rig cases, so their Gemma baseline can be measured on the rig.
    func test_dumpOtherInsightPromptsForRig() async throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump prompts")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { LocalLLMService.generateInterceptForTesting = nil }
        // One entry per case, spread over the last four days (all inside this week/month when
        // run mid-week; the prompt content is what matters here, not the calendar gate).
        let week: [Entry] = Self.rigCases.enumerated().map { i, c in
            let e = Entry(text: c.entries[0].text, mood: c.entries[0].mood)
            e.createdAt = Date().addingTimeInterval(-Double(i) * 86_400)
            return e
        }
        func capture(_ label: String, _ run: () async throws -> Void) async throws {
            var first: (String, String, LocalLLMService.GemmaPlan)?
            LocalLLMService.generateInterceptForTesting = { system, user, _, plan in
                if first == nil { first = (system, user, plan) }
                return ("x", .foundationModels)
            }
            try? await run()
            guard let first else { XCTFail("no generation captured for \(label)"); return }
            try first.0.write(toFile: "\(dir)/\(label)_system.txt", atomically: true, encoding: .utf8)
            try first.1.write(toFile: "\(dir)/\(label)_user.txt", atomically: true, encoding: .utf8)
            if case .grammarConstrained(let message, let grammar) = first.2 {
                try "<start_of_turn>user\n\(message)<end_of_turn>\n<start_of_turn>model\n"
                    .write(toFile: "\(dir)/\(label)_gemma.prompt", atomically: true, encoding: .utf8)
                try grammar.write(toFile: "\(dir)/\(label)_gemma.gbnf", atomically: true, encoding: .utf8)
            }
        }
        try await capture("digest") { _ = try await InsightService.generateWeeklyDigest(weekEntries: week, allEntries: week) }
        try await capture("digestB") { _ = try await InsightService.generateWeeklyDigest(weekEntries: Self.digestWeekB, allEntries: Self.digestWeekB) }
        try await capture("monthly") { _ = try await InsightService.generateMonthlyReport(monthEntries: week + Self.digestWeekB, allEntries: week + Self.digestWeekB) }
        try await capture("ask") { _ = try await InsightService.ask(question: "How has my sleep been lately?", entries: week) }
    }

    // MARK: - Follow-up chip + Talk It Out rig cases (2026-09-27)
    //
    // Synthetic drafts/transcripts (no real journal text), scored with the follow-up section of
    // tools/llmrig/RUBRIC.md. Same traps as rigCases: >=2 named people with distinct roles, a pet,
    // and plans or undecided things that haven't happened. No ja/zh follow-up case: the chip's
    // 20-word gate counts whitespace-separated words, so CJK drafts never reach it.
    static let followUpRigCases: [(label: String, draft: String)] = [
        ("fu_sickday", "Barely slept last night, my stomach was in knots until almost 4am. Called in sick and spent the day on the couch with the heating on. Dev texted that he might come over later with soup, but I'm not sure I want company."),
        ("fu_offer", "Lunch with Priya ran long. She told me her team has an opening and basically offered it to me if I want it. I haven't told Mom or Rahul yet because I keep going back and forth."),
        ("fu_work", "The client presentation got moved up to Thursday and the dashboard bug still isn't fixed. Nisha wants to review everything on Monday. I feel so behind, and I snapped at Omar in standup for no reason."),
        ("fu_walk", "Took Bruno for a long walk around the lake after work. The light on the water was gold and a few ducks followed us along the shore. I should call Anu tomorrow, it's been weeks since we talked."),
        ("fu_runon", "ugh so tired today gym at 7 then back to back meetings till 5 forgot lunch again and still need to sort out the car insurance thing before friday"),
        ("fu_sickday_de", "Letzte Nacht kaum geschlafen, mein Magen hat bis fast vier Uhr rumort. Ich habe mich krankgemeldet und den ganzen Tag auf dem Sofa verbracht. Dev hat geschrieben, dass er vielleicht später mit Suppe vorbeikommt, aber ich weiß nicht, ob ich Besuch will."),
        ("fu_offer_de", "Das Mittagessen mit Priya hat lange gedauert. Sie hat erzählt, dass in ihrem Team eine Stelle frei ist, und sie mir praktisch angeboten, wenn ich will. Ich habe es Mama und Rahul noch nicht gesagt, weil ich ständig hin und her überlege."),
        ("fu_sickday_es", "Anoche casi no dormí, tuve el estómago revuelto hasta casi las cuatro. Llamé para decir que estaba enfermo y pasé el día en el sofá. Dev me escribió que quizá venga más tarde con sopa, pero no sé si quiero compañía."),
        ("fu_offer_es", "La comida con Priya se alargó. Me contó que en su equipo hay una vacante y prácticamente me la ofreció si la quiero. Todavía no se lo he dicho a mamá ni a Rahul porque sigo dándole vueltas."),
    ]

    /// More drafts for prototype (a) only: grammar-constrained picks were near-deterministic
    /// (~1 real sample per case), so these add cases where the salient part is buried mid-draft,
    /// after scenery, in a checklist, or in a lowercase run-on.
    static let followUpPrototypeExtraCases: [(label: String, draft: String)] = [
        ("fu_biopsy", "Morning run by the river, legs felt heavy. Work was fine, mostly emails. Dad called and said the biopsy results come back Friday. Trying not to think about it."),
        ("fu_scenefirst", "The sky was pink on the drive home and the radio played that old song from college. Finally told Sam I don't want to renew the lease. He took it better than I expected."),
        ("fu_checklist", "- groceries done\n- called the bank about the fraud charge, they're reversing it\n- still haven't replied to Meera's message about the wedding, feel guilty"),
        ("fu_good", "Presented the redesign to the whole team today and people actually clapped. Kavya said it was the clearest demo she's seen this year. Still buzzing."),
        ("fu_mid", "Slow Sunday. Read on the balcony for a while. Keep replaying the argument with Jonas from Friday, I think I was unfair to him. Made pasta for dinner."),
        ("fu_night", "cant sleep again its 2am and my brain keeps going over the interview tomorrow what if they ask about the gap year"),
        ("fu_mid_de", "Ruhiger Sonntag. Habe eine Weile auf dem Balkon gelesen. Ich denke immer wieder an den Streit mit Jonas vom Freitag, ich glaube, ich war unfair zu ihm. Abends habe ich Nudeln gekocht."),
        ("fu_scenefirst_de", "Der Himmel war rosa auf der Heimfahrt, und im Radio lief das alte Lied aus der Uni-Zeit. Ich habe Sam endlich gesagt, dass ich den Mietvertrag nicht verlängern will. Er hat es besser aufgenommen als gedacht."),
        ("fu_mid_es", "Domingo tranquilo. Leí un rato en el balcón. No dejo de pensar en la discusión con Jonas del viernes, creo que fui injusto con él. Hice pasta para cenar."),
        ("fu_scenefirst_es", "El cielo estaba rosa de camino a casa y en la radio sonó esa canción vieja de la universidad. Por fin le dije a Sam que no quiero renovar el contrato del piso. Se lo tomó mejor de lo que esperaba."),
    ]

    /// Held-out drafts (2026-09-28): the salient part comes first or mid-draft, never last,
    /// after the round 1-3 drafts turned out to mostly end on it.
    static let followUpHeldOutCases: [(label: String, draft: String)] = [
        ("hx_biopsyfirst", "Dad's biopsy results come back Friday and I can't stop thinking about it. Went for a run after work anyway. Made pasta and watched an episode of that baking show."),
        ("hx_fightmid", "Grabbed coffee with Lena before work. Then Marco and I had a real fight about money in the car, first one in months, and neither of us apologized. Evening was quiet, did laundry."),
        ("hx_newsfirst", "Got the acceptance email from the Lisbon program! Told Priti at lunch and she screamed. The rest of the day was errands and a long nap."),
        ("hx_griefmid", "Rainy morning, stayed in bed late. Found Nani's old recipe book while cleaning and cried over her handwriting for a while. Ordered pizza and called it a night."),
        ("hx_worrymid", "long day at the clinic then picked up the kids and ben said hes being bullied at school again i dont know what to do then made dinner and bedtime"),
        ("hx_decisionfirst", "I think I'm going to quit the band. It stopped being fun months ago. Practice was at 8, Tom brought snacks, we ran the new song twice."),
        ("hx_fightmid_de", "Vor der Arbeit mit Lena Kaffee getrunken. Dann hatten Marco und ich im Auto einen richtigen Streit ums Geld, der erste seit Monaten, und keiner hat sich entschuldigt. Der Abend war ruhig, Wäsche gewaschen."),
        ("hx_newsfirst_de", "Die Zusage vom Lissabon-Programm ist gekommen! Ich habe es Priti beim Mittagessen erzählt und sie hat geschrien. Der Rest des Tages waren Besorgungen und ein langer Mittagsschlaf."),
        ("hx_fightmid_es", "Tomé un café con Lena antes del trabajo. Luego Marco y yo tuvimos una pelea de verdad por dinero en el coche, la primera en meses, y ninguno se disculpó. La tarde fue tranquila, puse la lavadora."),
        ("hx_newsfirst_es", "¡Me llegó el correo de aceptación del programa de Lisboa! Se lo conté a Priti en la comida y gritó. El resto del día fueron recados y una siesta larga."),
    ]

    /// fr/ru check before shipping prototype (a): the same six drafts de/es were scored on.
    static let followUpFrRuCases: [(label: String, draft: String)] = [
        ("fu_sickday_fr", "J'ai à peine dormi cette nuit, j'avais l'estomac noué jusqu'à presque 4 heures. Je me suis mis en arrêt maladie et j'ai passé la journée sur le canapé. Dev m'a écrit qu'il passerait peut-être plus tard avec de la soupe, mais je ne suis pas sûr d'avoir envie de voir quelqu'un."),
        ("fu_offer_fr", "Le déjeuner avec Priya s'est éternisé. Elle m'a dit que son équipe avait un poste libre et me l'a pratiquement proposé si je le veux. Je n'en ai pas encore parlé à maman ni à Rahul, parce que je n'arrête pas d'hésiter."),
        ("fu_mid_fr", "Dimanche tranquille. J'ai lu un moment sur le balcon. Je repense sans arrêt à la dispute avec Jonas vendredi, je crois que j'ai été injuste avec lui. J'ai fait des pâtes pour le dîner."),
        ("fu_scenefirst_fr", "Le ciel était rose sur la route du retour et la radio passait cette vieille chanson de la fac. J'ai enfin dit à Sam que je ne veux pas renouveler le bail. Il l'a mieux pris que je ne pensais."),
        ("hx_fightmid_fr", "Pris un café avec Lena avant le travail. Ensuite, Marco et moi nous sommes vraiment disputés à propos d'argent dans la voiture, la première fois depuis des mois, et aucun de nous ne s'est excusé. Soirée calme, j'ai fait une lessive."),
        ("hx_newsfirst_fr", "J'ai reçu le mail d'acceptation du programme de Lisbonne ! Je l'ai dit à Priti au déjeuner et elle a crié. Le reste de la journée, c'était des courses et une longue sieste."),
        ("fu_sickday_ru", "Почти не спал этой ночью, живот крутило почти до четырёх. Взял больничный и весь день пролежал на диване. Дев написал, что, может, зайдёт позже с супом, но я не уверен, что хочу кого-то видеть."),
        ("fu_offer_ru", "Обед с Прией затянулся. Она рассказала, что у них в команде есть вакансия, и практически предложила её мне, если я захочу. Я ещё не сказал ни маме, ни Рахулу, потому что всё время сомневаюсь."),
        ("fu_mid_ru", "Спокойное воскресенье. Немного почитал на балконе. Всё время прокручиваю в голове ссору с Йонасом в пятницу, кажется, я был к нему несправедлив. Приготовил пасту на ужин."),
        ("fu_scenefirst_ru", "По дороге домой небо было розовым, и по радио играла та старая песня из универа. Наконец сказал Сэму, что не хочу продлевать аренду. Он воспринял это лучше, чем я ожидал."),
        ("hx_fightmid_ru", "Выпил кофе с Леной перед работой. Потом мы с Марко по-настоящему поругались из-за денег в машине, впервые за несколько месяцев, и никто не извинился. Вечер был тихий, постирал вещи."),
        ("hx_newsfirst_ru", "Пришло письмо о зачислении в лиссабонскую программу! Рассказал Прити за обедом, и она закричала. Остаток дня ушёл на дела и долгий дневной сон."),
    ]

    static let guidedRigCases: [(label: String, turns: [(question: String, answer: String)])] = [
        ("gq_tired", [("How are you feeling today?", "Tired. Work was a lot and I didn't get much done.")]),
        ("gq_sister", [
            ("What's on your mind tonight?", "My sister Maya is moving to Berlin next month."),
            ("How do you feel about her moving?", "Happy for her, but I'll miss our Sunday dinners."),
        ]),
        ("gq_quilt", [("What stood out about your day?", "I finally finished the quilt I started in the spring.")]),
        ("gq_raise", [
            ("What's been on your mind lately?", "Thinking about asking my manager Leo for a raise."),
            ("What makes you want to ask now?", "I've taken on two extra projects since June and nobody seems to have noticed."),
        ]),
        ("gq_sister_de", [
            ("Was beschäftigt dich heute Abend?", "Meine Schwester Maya zieht nächsten Monat nach Berlin."),
            ("Wie fühlst du dich damit?", "Ich freue mich für sie, aber ich werde unsere Sonntagsessen vermissen."),
        ]),
        // Chat-style casual answers: the lowercase run-on shape was the follow-up chip's worst case.
        ("gq_runon", [
            ("How are you feeling today?", "ugh so tired today gym at 7 then back to back meetings till 5 forgot lunch again and still need to sort out the car insurance thing before friday"),
        ]),
        ("gq_plan3", [
            ("What's on your mind tonight?", "thinking about the trip to see grandma in Kochi, we're supposed to go in december"),
            ("What makes that trip feel important right now?", "she's been sick and mom keeps saying we should go sooner"),
            ("How do you feel about going sooner?", "honestly scared of seeing her like that. arjun says he can't get leave till december anyway"),
        ]),
    ]

    /// Writes the exact first-attempt prompt generateFollowUp / generateGuidedQuestion send, as
    /// Gemma would receive it (the Gemma-only system prompt when the plan swaps one in), so the
    /// rig can template it with `rig template`. No model runs. Output dir from HARNESS_DUMP_DIR.
    func test_dumpFollowUpPromptsForRig() async throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump prompts")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { LocalLLMService.generateInterceptForTesting = nil }
        func capture(_ label: String, _ run: () async throws -> Void) async throws {
            var first: (String, String, LocalLLMService.GemmaPlan)?
            LocalLLMService.generateInterceptForTesting = { system, user, _, plan in
                if first == nil { first = (system, user, plan) }
                return ("What do you mean?", .foundationModels)
            }
            try? await run()
            guard let first else { XCTFail("no generation captured for \(label)"); return }
            let gemmaSystem: String
            switch first.2 {
            case .samePrompt: gemmaSystem = first.0
            case .ownSystemPrompt(let own): gemmaSystem = own
            case .grammarConstrained(let message, let grammar):
                // The grounded follow-up chip (2026-09-28): same files as test_dumpNudgePromptsForRig.
                try "<start_of_turn>user\n\(message)<end_of_turn>\n<start_of_turn>model\n"
                    .write(toFile: "\(dir)/\(label)_gemma.prompt", atomically: true, encoding: .utf8)
                try grammar.write(toFile: "\(dir)/\(label)_gemma.gbnf", atomically: true, encoding: .utf8)
                return
            case .unsuitable:
                // Languages outside the grounded 10 get no chip on Gemma.
                try "unsuitable".write(toFile: "\(dir)/\(label)_gemma.none", atomically: true, encoding: .utf8)
                return
            }
            try gemmaSystem.write(toFile: "\(dir)/\(label)_system.txt", atomically: true, encoding: .utf8)
            try first.1.write(toFile: "\(dir)/\(label)_user.txt", atomically: true, encoding: .utf8)
        }
        for c in Self.followUpRigCases + Self.followUpPrototypeExtraCases + Self.followUpHeldOutCases + Self.followUpFrRuCases {
            try await capture(c.label) { _ = try await InsightService.generateFollowUp(currentText: c.draft) }
        }
        for c in Self.guidedRigCases {
            try await capture(c.label) { _ = try await InsightService.generateGuidedQuestion(conversationSoFar: c.turns) }
        }
    }

    /// Prototype (a) for the follow-up chip on Gemma, rig-only: Gemma picks one short phrase of
    /// the draft (literal grammar), the app would compose a fixed question around it. Candidates
    /// are the nudge's own sentences, cut here into clause runs of <= 100 chars so the composed
    /// question stays within validateFollowUp's 160. Instruction variant A mirrors pickNeutral;
    /// B asks for the part most worth writing more about. de/es use the shipped pickNeutral.
    func test_dumpFollowUpPrototypeForRig() throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump prompts")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let maxPhrase = 100
        let conjunctions: Set<String> = ["and", "then", "but", "because", "so", "und", "aber", "weil", "dann", "y", "pero", "porque", "luego"]
        // Cut points are character offsets into the sentence, so every merged run of pieces is a
        // verbatim substring: clause punctuation first, then (only inside a comma-free run that's
        // still too long) before a conjunction, then 12-word windows; adjacent pieces are merged
        // greedily up to maxPhrase so subordinate clauses ("wenn ich will") stay attached.
        func clauses(_ sentence: String) -> [String] {
            let trimSet = CharacterSet(charactersIn: " ,;:—–-.!?…")
            let chars = Array(sentence.trimmingCharacters(in: trimSet))
            guard chars.count > maxPhrase else { return [String(chars)] }
            let wordStarts = (1..<chars.count).filter { chars[$0 - 1] == " " && chars[$0] != " " }
            var cuts = [0] + wordStarts.filter { $0 >= 2 && ",;:—".contains(chars[$0 - 2]) } + [chars.count]
            var refined = [0]
            for (a, b) in zip(cuts, cuts.dropFirst()) {
                if b - a > maxPhrase {
                    let inner = wordStarts.filter { $0 > a && $0 < b }
                    let conj = inner.filter { j in
                        let word = String(chars[j...].prefix { $0 != " " }).lowercased()
                        return conjunctions.contains(word)
                    }
                    var sub = [a] + conj + [b]
                    var windowed = [a]
                    for (x, y) in zip(sub, sub.dropFirst()) {
                        if y - x > maxPhrase {
                            let starts = inner.filter { $0 > x && $0 < y }
                            windowed += stride(from: 11, to: starts.count, by: 12).map { starts[$0] }
                        }
                        windowed.append(y)
                    }
                    sub = windowed
                    refined += sub.dropFirst()
                } else {
                    refined.append(b)
                }
            }
            cuts = refined
            var out: [String] = []
            var start = cuts[0], last = cuts[0]
            for c in cuts.dropFirst() {
                if c - start > maxPhrase && last > start { out.append(String(chars[start..<last])); start = last }
                last = c
            }
            if last > start { out.append(String(chars[start..<last])) }
            return out
                .map { $0.trimmingCharacters(in: trimSet) }
                .filter { $0.split(separator: " ").count >= 3 }
        }
        func literal(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let english: [String: String] = [
            "A": "Copy word for word the part of the journal entry that shows the most important thing of the day. Output only that part.",
            "B": "Copy word for word the part of the journal entry that the writer would most want to say more about: a feeling, a worry, or something that happened to them. Output only that part.",
        ]
        let translatedB: [String: String] = [
            "de": "Kopiere Wort für Wort den Teil des Tagebucheintrags, über den die Person am liebsten mehr schreiben würde: ein Gefühl, eine Sorge oder etwas, das ihr passiert ist. Gib nur diesen Teil aus.",
            "es": "Copia palabra por palabra la parte de la entrada del diario sobre la que la persona querría escribir más: un sentimiento, una preocupación o algo que le pasó. Escribe solo esa parte.",
            "fr": "Recopie mot pour mot la partie de l'entrée du journal sur laquelle la personne aurait le plus envie d'écrire davantage : un sentiment, une inquiétude ou quelque chose qui lui est arrivé. Écris seulement cette partie.",
            "ru": "Перепиши слово в слово ту часть записи в дневнике, о которой человеку больше всего хотелось бы написать подробнее: чувство, тревогу или то, что с ним случилось. Выведи только эту часть.",
        ]
        for c in Self.followUpRigCases + Self.followUpPrototypeExtraCases + Self.followUpHeldOutCases + Self.followUpFrRuCases {
            var seen = Set<String>()
            // No "drop the unfinished last piece" rule: the chip only fires after 6s idle on an
            // unchanged draft, and unpunctuated drafts (checklists, run-ons) put their most
            // salient part last — the rule dropped it in 3 of 11 drafts.
            let options = InsightService.groundedNudgeQuoteCandidates(in: c.draft)
                .flatMap(clauses)
                .filter { seen.insert($0).inserted }
            try options.joined(separator: "\n").write(toFile: "\(dir)/\(c.label)_options.txt", atomically: true, encoding: .utf8)
            let grammar = "root ::= " + options.map(literal).joined(separator: " | ")
            let variants: [(String, String, String)]   // (variant, instruction, entry label)
            if ["_de", "_es", "_fr", "_ru"].contains(where: { c.label.hasSuffix($0) }) {
                let code = String(c.label.suffix(2))
                let loc = try XCTUnwrap(InsightService.groundedLocales[code])
                variants = [("L", loc.pickNeutral, loc.entryLabel), ("LB", try XCTUnwrap(translatedB[code]), loc.entryLabel)]
            } else {
                variants = english.sorted { $0.key < $1.key }.map { ($0.key, $0.value, "Journal entry:") }
            }
            let partsLabel = ["de": "Teile des Eintrags:", "es": "Partes de la entrada:", "fr": "Parties de l'entrée\u{00A0}:", "ru": "Части записи:"][String(c.label.suffix(2))] ?? "Parts of the entry:"
            let numbered = options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            var messages: [(String, String)] = variants.map { ($0.0, "\($0.1)\n\n\($0.2)\n\(c.draft)") }
            // Post-hoc layout variants (RUBRIC.md, round 2), B wording only.
            if let b = variants.first(where: { $0.0 == "B" || $0.0 == "LB" }) {
                messages.append((b.0 + "C", "\(b.2)\n\(c.draft)\n\n\(b.1)"))
                messages.append((b.0 + "D", "\(b.2)\n\(c.draft)\n\n\(partsLabel)\n\(numbered)\n\n\(b.1)"))
            }
            for (variant, message) in messages {
                try "<start_of_turn>user\n\(message)<end_of_turn>\n<start_of_turn>model\n"
                    .write(toFile: "\(dir)/\(c.label)_\(variant).prompt", atomically: true, encoding: .utf8)
                try grammar.write(toFile: "\(dir)/\(c.label)_\(variant).gbnf", atomically: true, encoding: .utf8)
            }
        }
    }


    /// A second synthetic week, unlike the rig cases: new job, rent rise, a grief anniversary.
    static let digestWeekB: [Entry] = {
        let texts: [(String, String, Double)] = [
            ("Landlord emailed that the rent goes up in November. Spent an hour redoing the budget spreadsheet and it still doesn't add up. Couldn't focus on the book after.", "Anxious", 0),
            ("Second day at the new job. The team lead, Farah, walked me through the codebase and it's less scary than I thought. Took the long way home through the market.", "Hopeful", 1),
            ("Grandpa's birthday would have been today. Looked at old photos with Lina over video call and we both cried a bit. Made his dal recipe for dinner.", "Sad", 3),
            ("First day at the new job! Commute was 40 minutes, not bad. Joel from IT set up my laptop. Signed up for the Saturday climbing session with Sam.", "Energized", 4),
            ("Packing up the old desk, found my notes from three years ago. Annoyed that I stayed so long at that place.", "Frustrated", 5),
        ]
        return texts.map { text, mood, daysAgo in
            let e = Entry(text: text, mood: mood)
            e.createdAt = Date().addingTimeInterval(-daysAgo * 3_600)   // hours, so all stay in this week
            return e
        }
    }()

    /// Real generateWeeklyDigest pipeline (validators, cleaners, grounding checks) on Gemma for
    /// both synthetic weeks. Opt-in like the rest of this harness.
    func test_groundedDigest_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 2
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        let weekA: [Entry] = Self.rigCases.map { $0.entries[0] }
        for (label, week) in [("weekA", weekA), ("weekB", Self.digestWeekB)] {
            for i in 1...runs {
                let started = Date()
                do {
                    let (text, engine) = try await InsightService.generateWeeklyDigest(weekEntries: week, allEntries: week)
                    let fallback = InsightService.isUngroundedFallback(text)
                    print("[digest][\(label)][\(i)] engine=\(engine.rawValue) fallback=\(fallback) seconds=\(Int(Date().timeIntervalSince(started)))")
                    print("[digest][\(label)][\(i)] TEXT: \(text.replacingOccurrences(of: "\n", with: " ⏎ "))")
                } catch {
                    print("[digest][\(label)][\(i)] THREW: \(error) seconds=\(Int(Date().timeIntervalSince(started)))")
                }
            }
        }
    }


    /// Real generateMonthlyReport pipeline on Gemma for a synthetic month (both digest weeks).
    func test_groundedMonthly_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 2
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        let month: [Entry] = Self.rigCases.map { $0.entries[0] } + Self.digestWeekB
        for i in 1...runs {
            let started = Date()
            do {
                let (text, engine) = try await InsightService.generateMonthlyReport(monthEntries: month, allEntries: month)
                print("[monthly][\(i)] engine=\(engine.rawValue) fallback=\(InsightService.isUngroundedFallback(text)) seconds=\(Int(Date().timeIntervalSince(started)))")
                print("[monthly][\(i)] TEXT: \(text.replacingOccurrences(of: "\n", with: " ⏎ "))")
            } catch {
                print("[monthly][\(i)] THREW: \(error) seconds=\(Int(Date().timeIntervalSince(started)))")
            }
        }
    }


    /// Real InsightService.ask pipeline on Gemma over the synthetic entries, one answerable question
    /// per kind (sleep, work stress, people, gym) plus one nothing answers (guitar).
    func test_groundedAsk_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 2
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        let entries: [Entry] = Self.rigCases.map { $0.entries[0] } + Self.digestWeekB
        let questions = [
            "How has my sleep been lately?", "What has been stressing me at work?",
            "Who have I spent time with recently?", "Have I been going to the gym?",
            "How is my guitar practice going?",
        ]
        for question in questions {
            for i in 1...runs {
                let started = Date()
                do {
                    let (text, engine) = try await InsightService.ask(question: question, entries: entries)
                    print("[ask][\(question)][\(i)] engine=\(engine.rawValue) seconds=\(Int(Date().timeIntervalSince(started))) TEXT: \(text)")
                } catch {
                    print("[ask][\(question)][\(i)] THREW: \(error)")
                }
            }
        }
    }


    /// Real generateNudge (plan, grammar, validator, fixed tip) on Gemma for the English rig,
    /// edge and reflection-line cases. Opt-in; HARNESS_ENGINE=gemma forces Gemma.
    func test_groundedNudge_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 1
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        for c in Self.rigCases + Self.groundedEdgeCases + Self.reflectionLineCases {
            for i in 1...runs {
                let started = Date()
                do {
                    let (text, engine, degraded) = try await InsightService.generateNudge(entries: c.entries)
                    print("[nudge][\(c.label)][\(i)] engine=\(engine.rawValue) degraded=\(degraded) seconds=\(Int(Date().timeIntervalSince(started))) TEXT: \(text)")
                } catch {
                    print("[nudge][\(c.label)][\(i)] THREW: \(error)")
                }
            }
        }
    }

    /// Real generateFollowUp (plan, grammar, validator, composition) on Gemma for rig drafts in
    /// en/de/es/fr/ru. Opt-in like the rest of this harness; HARNESS_ENGINE=gemma forces Gemma.
    func test_followUp_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RUNS"] ?? "") ?? 1
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        let labels: Set<String> = ["fu_runon", "fu_walk", "hx_biopsyfirst", "hx_worrymid", "fu_sickday_de", "hx_newsfirst_es", "fu_mid_fr", "hx_fightmid_ru"]
        let drafts = (Self.followUpRigCases + Self.followUpHeldOutCases + Self.followUpFrRuCases).filter { labels.contains($0.label) }
        for c in drafts {
            for i in 1...runs {
                let started = Date()
                do {
                    let (text, engine) = try await InsightService.generateFollowUp(currentText: c.draft)
                    print("[followup][\(c.label)][\(i)] engine=\(engine.rawValue) seconds=\(Int(Date().timeIntervalSince(started))) TEXT: \(text)")
                } catch {
                    print("[followup][\(c.label)][\(i)] THREW: \(error)")
                }
            }
        }
    }


    /// Dumps the production-built localized nudge and digest Gemma prompts + grammars for every
    /// supported non-English language (synthetic entries from GroundedLocalizedTests), for the rig.
    func test_dumpLocalizedPromptsForRig() async throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else {
            throw XCTSkip("Set HARNESS_DUMP_DIR to dump prompts")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func write(_ label: String, _ plan: LocalLLMService.GemmaPlan) throws {
            guard case .grammarConstrained(let message, let grammar) = plan else { XCTFail("no grammar plan for \(label)"); return }
            try "<start_of_turn>user\n\(message)<end_of_turn>\n<start_of_turn>model\n".write(toFile: "\(dir)/\(label).prompt", atomically: true, encoding: .utf8)
            try grammar.write(toFile: "\(dir)/\(label).gbnf", atomically: true, encoding: .utf8)
        }
        for (code, text) in SharedLLMState.GroundedLocalizedTests.sickDay {
            let entry = Entry(text: text, mood: "Drained")
            let nudge = try XCTUnwrap(InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: []), code)
            try write("\(code)_nudge", nudge.plan)
            let calm = Entry(text: text, mood: "Peaceful")
            calm.createdAt = entry.createdAt.addingTimeInterval(-3_600)
            let digest = try XCTUnwrap(InsightService.localizedGroundedDigest(weekEntries: [entry, calm], languageSource: [entry]), code)
            try write("\(code)_digest", digest.plan)
            let monthly = try XCTUnwrap(InsightService.localizedGroundedMonthly(monthEntries: [entry, calm]), code)
            try write("\(code)_monthly", monthly.plan)
        }
    }


    /// Real generateNudge / generateWeeklyDigest on Gemma in German, Japanese and Chinese.
    func test_localizedGrounded_fullPipeline() async throws {
        try requireHarnessOptIn()
        guard GemmaModelTestSupport.ensureModelInstalled() else {
            throw XCTSkip("Gemma model not available in this test process — see this file's header comment")
        }
        LocalLLMService.forceGemmaForTesting = ProcessInfo.processInfo.environment["HARNESS_ENGINE"] == "gemma"
        defer { LocalLLMService.forceGemmaForTesting = false }
        let calmDay: [String: String] = [
            "de": "Bin nach der Arbeit mit dem Hund am See spazieren gegangen. Zum ersten Mal diese Woche fühlte ich mich leicht.",
            "ja": "仕事のあと犬と湖のそばを散歩した。今週はじめて気持ちが軽くなった。",
            "zh": "下班后带狗在湖边散步。这周第一次觉得轻松。",
        ]
        for code in ["de", "ja", "zh"] {
            let sick = Entry(text: SharedLLMState.GroundedLocalizedTests.sickDay[code]!, mood: "Drained")
            let calm = Entry(text: calmDay[code]!, mood: "Peaceful")
            calm.createdAt = sick.createdAt.addingTimeInterval(-3_600)
            var started = Date()
            let (nudge, _, degraded) = try await InsightService.generateNudge(entries: [sick])
            print("[loc][\(code)][nudge] seconds=\(Int(Date().timeIntervalSince(started))) degraded=\(degraded) fallback=\(InsightService.isUngroundedFallback(nudge)) TEXT: \(nudge)")
            started = Date()
            let (digest, _) = try await InsightService.generateWeeklyDigest(weekEntries: [sick, calm], allEntries: [sick, calm])
            print("[loc][\(code)][digest] seconds=\(Int(Date().timeIntervalSince(started))) fallback=\(InsightService.isUngroundedFallback(digest)) TEXT: \(digest.replacingOccurrences(of: "\n", with: " ⏎ "))")
            started = Date()
            let (monthly, _) = try await InsightService.generateMonthlyReport(monthEntries: [sick, calm], allEntries: [sick, calm])
            print("[loc][\(code)][monthly] seconds=\(Int(Date().timeIntervalSince(started))) fallback=\(InsightService.isUngroundedFallback(monthly)) TEXT: \(monthly.replacingOccurrences(of: "\n", with: " ⏎ "))")
        }
    }

    // MARK: Round 8 (tools/llmrig/fm/RUBRIC_FM.md): the daily reflection in the other FM languages

    private struct Rig8Case { let lang: String; let label: String; let text: String; let mood: String; let key: String }

    /// Synthetic text only. Per language: a hard day, an ordinary day, one run-on sentence.
    private static let rig8Cases: [Rig8Case] = {
        let rows: [(String, [(String, String, String)])] = [
            ("de", [("hard", "Heute hat mein Chef vor allen anderen meine Arbeit kritisiert. Ich habe den Rest des Tages kaum etwas gesagt. Am Abend bin ich völlig erschöpft nach Hause gekommen.", "mein Chef vor allen anderen meine Arbeit kritisiert"),
                    ("plain", "Zum Frühstück gab es Brot und Kaffee. Danach habe ich zwei Stunden am Projekt gearbeitet und am Abend kurz eingekauft. Ein ganz normaler Tag.", "zwei Stunden am Projekt"),
                    ("runon", "Ich weiß nicht genau warum, aber seit dem Gespräch mit meiner Schwester gestern Abend gehen mir ihre Worte nicht aus dem Kopf und ich habe das Gefühl, dass ich etwas sagen wollte, das ich nicht gesagt habe, und jetzt überlege ich, ob ich sie anrufen soll oder lieber bis zum Wochenende warte.", "Gespräch mit meiner Schwester")]),
            ("es", [("hard", "Hoy mi jefe criticó mi trabajo delante de todo el equipo. Casi no hablé el resto del día. Llegué a casa agotado por la noche.", "criticó mi trabajo"),
                    ("plain", "Desayuné pan con café. Después trabajé dos horas en el proyecto y por la tarde hice la compra. Fue un día normal.", "dos horas en el proyecto"),
                    ("runon", "No sé muy bien por qué, pero desde la conversación con mi hermana anoche no puedo dejar de pensar en sus palabras y siento que quería decirle algo que no dije, y ahora estoy aquí dudando si llamarla o esperar hasta el fin de semana.", "conversación con mi hermana")]),
            ("fr", [("hard", "Aujourd'hui mon chef a critiqué mon travail devant toute l'équipe. Je n'ai presque rien dit le reste de la journée. Je suis rentré à la maison complètement épuisé le soir.", "critiqué mon travail"),
                    ("plain", "J'ai pris du pain et du café au petit-déjeuner. Ensuite j'ai travaillé deux heures sur le projet et fait quelques courses le soir. Une journée tout à fait normale.", "deux heures sur le projet"),
                    ("runon", "Je ne sais pas trop pourquoi, mais depuis la conversation avec ma sœur hier soir, ses mots ne me quittent plus et j'ai l'impression d'avoir voulu dire quelque chose que je n'ai pas dit, et maintenant je me demande si je dois l'appeler ou attendre le week-end.", "conversation avec ma sœur")]),
            ("it", [("hard", "Oggi il mio capo ha criticato il mio lavoro davanti a tutti. Per il resto della giornata ho parlato pochissimo. La sera sono tornato a casa completamente esausto.", "criticato il mio lavoro"),
                    ("plain", "A colazione ho mangiato pane e caffè. Poi ho lavorato due ore al progetto e la sera ho fatto un po' di spesa. Una giornata del tutto normale.", "due ore al progetto"),
                    ("runon", "Non so bene perché, ma da quando ho parlato con mia sorella ieri sera le sue parole non mi escono dalla testa e ho la sensazione di voler dire qualcosa che non ho detto, e adesso mi chiedo se chiamarla o aspettare il fine settimana.", "parlato con mia sorella")]),
            ("pt", [("hard", "Hoje meu chefe criticou meu trabalho na frente de todo mundo. Quase não falei pelo resto do dia. À noite cheguei em casa completamente exausto.", "criticou meu trabalho"),
                    ("plain", "No café da manhã comi pão com café. Depois trabalhei duas horas no projeto e à noite fiz umas compras rápidas. Foi um dia bem normal.", "duas horas no projeto"),
                    ("runon", "Não sei bem por quê, mas desde a conversa com minha irmã ontem à noite as palavras dela não saem da minha cabeça e sinto que queria dizer algo que não disse, e agora estou aqui pensando se ligo para ela ou espero até o fim de semana.", "conversa com minha irmã")]),
            ("ja", [("hard", "今日は上司にみんなの前で仕事を批判された。その後はほとんど何も話せなかった。夜は疲れ果てて家に帰った。", "上司にみんなの前で仕事を批判された"),
                    ("plain", "朝食にパンとコーヒーを食べた。そのあと二時間ほどプロジェクトの作業をして、夜に少しだけ買い物に行った。ごく普通の一日だった。", "二時間ほどプロジェクトの作業"),
                    ("runon", "理由はよく分からないけれど、昨夜妹と話してから彼女の言葉が頭から離れなくて、言いたかったことを言えなかった気がして、今は電話をかけるべきか週末まで待つべきかずっと考えている。", "妹と話してから")]),
            ("ko", [("hard", "오늘 상사가 모두 앞에서 내 일을 비판했다. 그 뒤로는 거의 말을 하지 못했다. 저녁에 완전히 지쳐서 집에 돌아왔다.", "상사가 모두 앞에서 내 일을 비판했다"),
                    ("plain", "아침으로 빵과 커피를 먹었다. 그다음 두 시간 동안 프로젝트 작업을 했고 저녁에 잠깐 장을 봤다. 아주 평범한 하루였다.", "두 시간 동안 프로젝트 작업"),
                    ("runon", "왜 그런지 잘 모르겠지만 어젯밤 동생과 이야기한 뒤로 동생의 말이 머릿속에서 떠나지 않고 하고 싶은 말을 하지 못한 것 같아서 지금은 전화를 할지 주말까지 기다릴지 계속 고민하고 있다.", "동생과 이야기한")]),
            ("zh", [("hard", "今天上司当着所有人的面批评了我的工作。之后一整天我几乎没怎么说话。晚上我筋疲力尽地回到了家。", "上司当着所有人的面批评了我的工作"),
                    ("plain", "早饭吃了面包和咖啡。然后我花了两个小时做项目，晚上去超市买了点东西。就是很普通的一天。", "花了两个小时做项目"),
                    ("runon", "我也说不清为什么，但是自从昨晚和妹妹聊过之后她的话一直在我脑子里转，我觉得有些话想说却没说出口，现在我在犹豫是现在就给她打电话还是等到周末。", "和妹妹聊过之后")]),
        ]
        let moods = ["hard": "Drained", "plain": "Content", "runon": "Anxious"]
        return rows.flatMap { lang, cases in cases.map { Rig8Case(lang: lang, label: "\(lang)_\($0.0)", text: $0.1, mood: moods[$0.0]!, key: $0.2) } }
    }()

    /// Real Foundation Models, the app's own loop (up to 3 attempts, first quote that matches one of the
    /// entry's sentences wins). Needs Apple Intelligence on the host. Output: HARNESS_DUMP_DIR/rig8.tsv.
    func test_rig8_localizedStructuredQuote() async throws {
        guard ProcessInfo.processInfo.environment["HARNESS_RIG8"] != nil else { throw XCTSkip("Set HARNESS_RIG8=1 (real Foundation Models)") }
        guard FoundationModelEngine.isAvailable else { throw XCTSkip("Foundation Models unavailable on this host") }
        let runs = Int(ProcessInfo.processInfo.environment["HARNESS_RIG8_N"] ?? "") ?? 10
        var rows = ["case\trun\tattempt\toutcome\tquote"]
        var perCase: [String: (shown: Int, first: Int, main: Int, attempts: Int, errors: Int)] = [:]
        for c in Self.rig8Cases {
            XCTAssertTrue(FoundationModelEngine.supports(languageCode: c.lang), "\(c.lang) should be supported")
            let entry = Entry(text: c.text, mood: c.mood)
            let grounded = try XCTUnwrap(InsightService.localizedGroundedNudge(recent: [entry], background: [], recentNudges: []), "no grounded plan for \(c.label)")
            let validator = try XCTUnwrap(grounded.validator)
            let system = InsightService.structuredNudgeSystemPrompt(for: [entry])
            let user = InsightService.buildUserMessage(title: "Daily reflection context", recentEntries: [entry], backgroundEntries: [], maxChars: InsightService.dailyNudgePromptBudget, includeRecurringTerms: false)
            var tally = (shown: 0, first: 0, main: 0, attempts: 0, errors: 0)
            for run in 1...runs {
                var shownText: String?
                for attempt in 1...InsightService.structuredNudgeAttempts {
                    tally.attempts += 1
                    do {
                        let draft = try await FoundationModelEngine.generateDailyReflection(systemPrompt: system, userMessage: user)
                        if let option = FMDailyGuard.matchOption(quote: draft.quote, in: grounded.quoteOptions), let text = try? validator(option) {
                            if attempt == 1 { tally.first += 1 }
                            if option.contains(c.key) { tally.main += 1 }
                            shownText = text
                            rows.append("\(c.label)\t\(run)\t\(attempt)\tMATCH\t\(option)")
                            break
                        }
                        rows.append("\(c.label)\t\(run)\t\(attempt)\tNOMATCH\t\(draft.quote.replacingOccurrences(of: "\n", with: " "))")
                    } catch {
                        tally.errors += 1
                        rows.append("\(c.label)\t\(run)\t\(attempt)\tERROR\t\(type(of: error))")
                    }
                }
                if shownText != nil { tally.shown += 1 }
            }
            perCase[c.label] = tally
            print("[rig8] \(c.label) shown=\(tally.shown)/\(runs) first=\(tally.first) main=\(tally.main) errors=\(tally.errors)/\(tally.attempts)")
        }
        let total = perCase.values.reduce((0, 0, 0, 0, 0)) { ($0.0 + $1.shown, $0.1 + $1.first, $0.2 + $1.main, $0.3 + $1.attempts, $0.4 + $1.errors) }
        print("[rig8] TOTAL shown=\(total.0)/\(perCase.count * runs) first=\(total.1) main=\(total.2) errors=\(total.4)/\(total.3)")
        for lang in Set(Self.rig8Cases.map(\.lang)).sorted() {
            let mine = Self.rig8Cases.filter { $0.lang == lang }.compactMap { perCase[$0.label]?.shown }.reduce(0, +)
            print("[rig8] LANG \(lang) shown=\(mine)/\(3 * runs)")
        }
        if let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try rows.joined(separator: "\n").write(toFile: "\(dir)/rig8.tsv", atomically: true, encoding: .utf8)
        }
    }
}
