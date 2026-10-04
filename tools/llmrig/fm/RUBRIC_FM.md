# Foundation Models daily reflection: rubric and plan (fixed BEFORE any run, 2026-10-02)

Question: can the FM daily reflection say more, and say it with evidence, without inventing?
Engine: Apple Foundation Models, run on a Mac with `fm/fmrig.swift` (this folder). Inputs are the
byte-identical (system, user) prompts dumped by `GroundingSampleHarness.test_dumpNudgePromptsForRig`
(synthetic cases only: never real journal text).

## Variants
- **V0 baseline**: production `DAILY_NUDGE_SYSTEM`, free prose, as shipped.
- **V1 structured**: `@Generable` with a verbatim `quote` field first, then `insight`, then an
  optional `suggestion`. The app would assemble `You wrote, "<quote>" <insight> <suggestion>`.
- **V2 structured + connection**: V1 plus an optional `connection` that links today to an earlier
  entry with a second verbatim quote.

N = 10 per variant per case, temperature 0.45 (the app's). Cases: the rig's sickday, lunch, work,
walk, plus the messy ones (run-on, checklist, quotes/emoji, two entries same day) and the good-mood
and neutral cases. Scoring is blind: outputs are shuffled and variant labels removed before scoring.

## Per output, scored 0/1 (PASS needs 1-5 all true)
1. **MAIN**: names the entry's main event or feeling (per-case list in the rig README / rubric).
2. **INVENT**: no event, object, place, person, sensation or scenery that is not in the entries.
   Scenery counts: "watch the light change", "the sky", "steam from a mug" are INVENT failures.
   Figurative wording is fine if it is not stated as fact.
3. **SWAP**: no person given another person's action; a dog is not a person.
4. **TENSE**: plans and offers are not stated as done.
5. **FORMAT**: no preamble or meta text, 2-4 sentences, "you" register, no first person.

Also recorded, not part of PASS:
6. **EVIDENCE** (V1/V2): every `quote` / `connection` quote is found verbatim in the entries
   (whitespace and curly quotes normalised). Checked by script.
7. **INSIGHT**: says something beyond restating the quote (a feeling, need, tension or link) that the
   entries support. This is the "richer" measure.
8. **SUGGESTION**: on hard-mood cases, names something from the entry; generic self-care (breathing,
   walk, tea, sky) scores 0.
9. Latency, guardrail refusals, other errors.

## Ship rule
Ship a structured variant only if, over all cases: PASS rate >= baseline and >= 95% on cases 1-5,
no case below 8/10 PASS, EVIDENCE 100%, INSIGHT clearly higher than baseline, and guardrail
refusals/errors <= 5%. Otherwise keep the baseline. A variant that fails only on INSIGHT is a
quality gain we do not ship.

---
## Round 1 result (2026-10-02, N=10 x 13 cases x 3 variants, blind-scored)

| Variant | PASS 1-5 | INVENT ok | quote verbatim | errors | median s |
|---|---|---|---|---|---|
| V0 baseline (shipped) | 6/130 (5%) | 11/130 | n/a | 0 | 2.1 |
| V1 structured | 83/130 (64%) | 96/130 | 120/120 | 10 (all `rl_missing`) | 1.8 |
| V2 + earlier link | 58/130 (45%) | 77/130 | 116/120 (+1 bad earlier quote) | 10 (all `rl_missing`) | 2.3 |

Neither candidate meets the ship rule. Findings:
- **The shipped FM prompt invents** in most outputs, mostly scenery or sensation in the suggestion
  ("feel the air change", "watch the light", "the air touch your skin") and details in the opener
  ("Priya's voice cracked", "the air crisp and full of quiet hope"). The earlier "12/12 faithful"
  was one case under a looser rubric.
- **V1 guardrail**: `rl_missing` (a flatmate moved away, "missing him a lot tonight") was refused
  10/10 with "May contain sensitive content", in V1 and V2 only. Diagnosis (4 runs each, not scored):
  the cause is the system prompt listing hard moods ("anxious, overwhelmed ... sad or numb"), not the
  schema or the entry; with that sentence removed the same entry went through 8/8.
- **V1 failures by case**: lunch 0/10 (invents "relief"), rl_missing 0/10 (errors), rl_neutral 2/10
  (invents "something feels off"), runon 3/10 (output lowercase and unpunctuated after a long quote),
  rl_lowwork 6/10 (invented furniture: table, wall).
- **V2 is worse**: it forces links to earlier entries that do not connect ("the group chat noise
  mirrors feeling light"). One good link in 130 (a mother's "don't worry about it" and "I still feel
  bad"). Dropped.
- Formatting slips (lowercase, no end punctuation) are fixed by the app when it assembles the text.

## Round 2: V1b (changes fixed BEFORE running)
1. The app, not the prompt, decides whether a suggestion is wanted from the entry's mood: hard moods
   use `system_v1b_hard.txt` (with a suggestion field); other moods use `system_v1b_easy.txt` and a
   schema with no suggestion field. No list of moods appears in either prompt.
2. Feelings: name only feelings the person wrote or that their words plainly show; do not add
   emotions (relief, excitement, joy, unease). An ordinary day is described as ordinary.
3. No invented objects, furniture, places or sensations; no claims that exaggerate what they wrote.
4. The quote is the single most important sentence, at most 25 words.
5. The app capitalises the insight and adds end punctuation when assembling.
Same cases, N, temperature and blind scoring. V0 results from round 1 are the baseline. Same ship rule.

## Round 2 result (V1b, N=10 x 13 cases, blind-scored 2026-10-02)
PASS 109/130 (84%), INSIGHT 18/130 (14%), errors 0 (the guardrail refusals are gone), quotes verbatim 129/130,
19 quotes over 200 characters (run-on and multi-sentence entries), median 1.5 s. By case: rl_lowwork 0/10,
sameday 6/10, rl_sickfriend 6/10, sickday 8/10, lunch 9/10, all others 10/10.
Failures: (a) the model-written suggestion invented a person ("Talk to the person at your desk about lunch",
10/10 on rl_lowwork) and is formulaic ("Talk to X about Y") everywhere; (b) second sentences starting in
lowercase (sameday, rl_sickfriend), fixable by the app; (c) one "relief" and one "anticipation" not in the
entries. Insight became terse.

## Round 3: V1c (changes fixed BEFORE running)
1. No model-written suggestion at all. On hard moods the app appends its existing fixed tip (the
   `groundedNudgeTips` the Gemma path already uses), so the rig scores quote + insight only.
2. The app capitalises every sentence and ends with punctuation.
3. Insight is exactly two sentences: what it seems to mean, then the need, tension or hope their words show.
   No advice, no questions.
Same cases, N, temperature, blind scoring and ship rule. INSIGHT must beat V1b's 14%.

## Round 3 result (V1c, stopped early)
Blind-scored the first 45 of 130: 25 contained an invention (invented wants and worries: "You worry about
what Dev will do", "You want to finish the run", "quiet weariness" on an ordinary day; "relief"; a swap: Mom's
tiredness from the wedding prep given to Priya). Pass ~44%. Rest not scored. Forcing a second "need or
tension" sentence makes the model pad with invention. 1 guardrail refusal in 130. Rejected.

## Round 4: V1d (fixed BEFORE running)
`system_v1b_easy.txt` (the short prompt, no mood list, no suggestion) for EVERY mood, schema
quote + insight only, `tidyAll` applied by the app. On hard moods the app appends its existing approved fixed
tip, which this rig does not score. Same cases, N, temperature, blind scoring, ship rule
(PASS >= 95%, no case < 8/10, quotes 100% verbatim, errors <= 5%, INSIGHT above baseline).
Expected from the V1b data (not a measurement): about 96%.

## Round 4 result (V1d, N=10 x 13 cases, scored 2026-10-02)
Scoring note: outputs were near-identical within a case, so the scorer read the unique texts per case with
counts (not the shuffled blind sheet). Single scorer. Treat the numbers as +-3 outputs.

Errors 0/130. Quotes verbatim 130/130. Median ~1.4 s.
PASS about 122/130 (94%). Failures: sickday 1 ("uneasy"), lunch 2 ("relief", "calm" not in entry),
walk 3 ("a lightness you haven't felt before" overclaims "first time this week"), sameday 1 ("tired" from
heavy legs), neutral 1 ("everything felt quiet"). Per case: walk 7/10, lunch 8/10, sickday 9/10, sameday 9/10,
neutral 9/10, all other cases 10/10.
Not in PASS but a quality defect: `rl_missing` 8/10 are ungrammatical ("You feel sad and missing him",
"You feel missing him a lot"), and the insight restates the quote's feeling in nearly every output.
INSIGHT (says something beyond the quote): under 10%, lower than V1b's 14%.

Verdict against the pre-registered rule: NOT shipped as is. PASS 94% (< 95%), walk is below 8/10, INSIGHT
is not above baseline-style richness. The rule is missed narrowly on PASS and clearly on INSIGHT.
What the data does show: structured output with app-verified quotes removes the baseline's invention
(5% -> 94% PASS) and the guardrail refusals; the richer-content goal is not met by any variant. Asking the
model for more (V1c) makes it invent.

## Round 5: V1e = V1d + app-side guards (fixed BEFORE running, 2026-10-02)
Decision recorded: on 2026-10-02 the owner chose to ship V1d with app-side guards ("go with option 1"). That
knowingly drops the "INSIGHT clearly above baseline" criterion; the richer-content goal is NOT met and is not
claimed. What ships, if it passes, is the same short reflection with the invention removed.

Guards: `mirror/Core/Services/FMDailyGuard.swift`, compiled into the rig and into the app (same file, no copy).
Per insight sentence, a sentence that fails is dropped and the rest kept; the attempt is rejected when no
sentence survives. Checks: no quote marks; no first person; feeling words must come from the entry, a
today-entry mood label or its small synonym list; "before/ever/never/always/anymore/again/finally/first time..."
only when the entry has them; no scenery words or names the entry lacks; no "feel + -ing" ("feel missing him").
Quote: must be found in TODAY's entries (case-insensitive, whitespace and curly quotes normalised), shown with
the entry's own casing, cut to 25 words / 200 characters, at least 4 words.
The rig runs the app's loop: up to 3 attempts, the first that survives is what would be shown; when all 3
are rejected the run is a FALLBACK (the app then uses Gemma's grammar path if present, else the existing
honest card; not scored here).

Cases: the 13 original + 6 held-out synthetic cases written after the guards (hold_*), N = 10 each.
The guards were built from round 4's failures, so the held-out cases are the generalisation test.
Scoring: shuffled blind sheet (`score_tools.py sheet`), rubric above, plus FORMAT now also fails
ungrammatical feeling phrases ("You feel missing him").

Ship rule (all must hold): shown-output PASS >= 95% overall and >= 95% on the held-out cases alone; no case with
more than 2 shown failures out of 10; FALLBACK rate <= 10% overall and <= 30% in any case; shown quotes 100%
verbatim; errors/guardrail refusals <= 5%. INSIGHT is reported, not gated.

### Round 5 result (V1e, 19 cases x 10, blind sheet of the 185 shown outputs, scored 2026-10-02)
Shown 185/190, FALLBACK 4/190 (2.1%: lunch, runon, checklist, rl_lowwork 1 each), 1 error (FM guardrail
"May contain sensitive content" on sickday; the app treats it as a failed attempt), shown quotes 185/185 verbatim.
Shown PASS 180/185 (97.3%): original 13 cases 124/125 (99%), the 6 held-out cases 56/60 (93.3%).
Failures: hold_argue "to feel active" (invented motive) and "did something to feel like you had to do
something" (nonsense); hold_plain "quiet moments", "You are quiet and focused" (states the entry lacks);
rl_sickfriend a lowercase name ("maya"). No case has more than 2 shown failures.
Verdict: all gates hold EXCEPT the held-out PASS (93.3% < 95%, one output short; two of the four are
borderline wording). Not shipping on this alone. Generalisable fix: "quiet / focused / productive / active /
busy / relaxed / wired / alert / steady / determined" now count as feeling words that need support in the
entry or mood. The lowercase-name case is left unfixed (1/185, cosmetic).

## Round 6 (fixed BEFORE running)
Same guard plus the state words above. 6 FRESH held-out synthetic cases written before the run
(hold2_*: deadline, bday, lonely, gym, cough, cooking) + the 19 earlier cases re-run, N = 10 each.
Same blind scoring and ship rule; the held-out gate is evaluated on the 6 fresh cases alone (>= 57/60), the
overall gate on all 25 cases. One round only: if it misses, the structured path does not ship.

### Round 6 result (V1e with state words, 25 cases x 10, blind sheet of the 241 shown outputs, scored 2026-10-02)
Shown 241/250, FALLBACK 9/250 (3.6%; worst case hold_plain 3/10 = 30%, rl_neutral 2, rl_missing 2, rl_lowwork 1,
hold2_cooking 1), errors 0, shown quotes 241/241 verbatim.
Shown PASS 237/241 (98.3%). The 6 FRESH held-out cases: 58/59 (98.3%, gate >= 95%). No case has more than 1
shown failure. Failures: hold_argue "You feel quiet after the conversation with Vikram" (Vikram's quiet given to
the writer: a SWAP the word check cannot see), rl_sickfriend lowercase name ("maya", 2nd time in two rounds),
lunch one insight sentence repeated twice, hold2_cooking "a sense of care for what you made" (inferred motive).
INSIGHT (beyond restating the quote): still under 10%; not gated, not improved. Single scorer, case labels visible.
Verdict: ship rule met (shown PASS 98.3%, fresh held-out 98.3%, fallback 3.6% / worst case 30%, errors 0, quotes
100% verbatim). Ship as the English FM daily reflection. Known limits, not fixed: swapped attributions
inside the word list (quiet/wired/tired said of someone else), lowercase names, repeated sentences.
Cheap follow-ups worth doing in the app: drop a repeated sentence; capitalise a name the entry capitalises.

### Shipped (2026-10-02)
App: `FMDailyGuard` (shared with the rig), `FoundationModelEngine.generateDailyReflection`, `InsightService.structuredFMNudge`
(3 attempts) wired into `generateNudge` for English on FM; on failure Gemma's grammar path if a model exists, else the honest
card. Two cosmetic guard fixes landed after round 6 and were not re-measured: a repeated sentence is dropped, and a name
the entry writes capitalised is restored ("maya" -> "Maya"); each only removes a defect seen in rounds 5-6.
End to end on the simulator's real Foundation Models: 5/5 grounded, assembled, tip appended on Drained
(`RealFMNudgeTests`, set TEST_RUNNER_HARNESS_REAL_FM=1). Unit suite 501/501.

### Round 7: two input shapes round 6 lacked (N=10, indicative, not gated; scored 2026-10-02, 70 shown outputs)
Entries with NO mood (sickday, lunch, neutral, work, good): shown 40/50, FALLBACK 6, errors 4 (all nomood_sickday: the FM
guardrail "May contain sensitive content" fired 4/10 once the mood label was gone). Worst: nomood_work 4/10 fell back.
Newest entry dated YESTERDAY (sickday, work, good): shown 30/30, no fallback or error; quotes came from the right day.
Replaying round 6's raw drafts with the mood removed: 47/250 first drafts would be rejected and retried, because the guard
leans on the mood label for feeling words. Moods are set on practically every entry (detected at save), so this is the rare path.
Scoring: 3 of 70 shown lines gave one person's feeling to another ("a mix of tiredness and concern" for the writer, where
"tired" is Mom's), the swap the word check cannot see; 0 invented events. "steady" was taken out of the guard's feeling
list after this replay (it is the prompt's own sanctioned wording for an ordinary day, and without a mood it made every
neutral day fall back).

### Round 8: the daily reflection in the other FM languages (plan fixed BEFORE running, 2026-10-02)
Question: can one prompt, `DAILY_REFLECTION_FM_SYSTEM` unchanged plus the app's existing "respond in <language>" line, make
Foundation Models pick the quote for de, es, fr, it, pt, ja, ko and zh, so Gemma is not needed on a device that has FM?
Russian is not on Apple's language list (`supportsLocale` false on the dev Mac), so it stays on Gemma.
What the app shows outside English: the model's quote only if it matches one of the entry's own quotable sentences
(`FMDailyGuard.matchOption`, characters not words, so ja/zh work), then the app's fixed translated line for the entry's
mood (`groundedLocales`). The model-written insight is NOT shown (FMDailyGuard is English-only), so it is not scored.
Cases: 3 synthetic entries per language (a hard day with mood Drained, an ordinary day with mood Content, a single
run-on sentence with mood Anxious), 24 cases, N = 10 each, temperature 0.45. Synthetic text only. Run:
`GroundingSampleHarness.test_rig8_localizedStructuredQuote` (HARNESS_RIG8=1, FM on the simulator).
Per run it does what the app does: up to 3 attempts, first one that matches an option wins.
- SHOWN: a run ends with a matched option. Gate: >= 95% over all runs and >= 90% in every language.
- ATTEMPT1: the first attempt already matches (not gated).
- ERRORS: attempts that throw (guardrail, unsupported language, other). Gate: <= 5% of attempts.
- MAIN: the shown option contains the case's main-event sentence (not gated; says whether FM picks a good quote).
A language under the gate is taken off the FM list (`supports` false) so it stays on Gemma, as before this change.
AMENDED 2026-10-02 (after the round 8 run, before round 9; the gate itself is unchanged): the owner's rule is no Gemma on a device that has
Foundation Models, so a language under the gate stays on FM and its fallback-card rate is reported instead.
Everything shown is the person's own sentence plus fixed text, so there is nothing to score for invention.

### Round 8 result (2026-10-02, N=10 x 24 cases, mechanical, `rig8.tsv`): FAILED the gate
SHOWN 171/240 (71.2%, gate >= 95%). By language: es 100%, ja 100%, pt 97%, de 67%, it 67%, zh 67%, fr 40%, ko 33% (gate >= 90%).
Errors 0/389 attempts. Failures were systematic, not random: 9 cases were 0/10 and 2 more near zero. Every rejected attempt
returned the WHOLE ENTRY as its "quote" (3 sentences, the short entries of this rig); no sentence is 60% of it, so
`matchOption` rejected it. The same copy-the-whole-entry draft is what the English guard's `cut` already turns into the
entry's own start. Not a prompt or language problem; ja/es/pt passed because those entries ended up matching a sentence.

### Round 9: matcher v2 (plan fixed BEFORE running, 2026-10-02)
Change, one thing only: `FMDailyGuard.matchOption`, after the existing rules fail, takes the option that appears EARLIEST inside
the model's quote (so a quote that is the whole entry becomes its first sentence, like the English cut). Prompt, cases, N,
temperature, attempts and gates are exactly round 8's (SHOWN >= 95% overall and >= 90% per language, errors <= 5%).
MAIN stays informational; expect it to drop for entries whose main event is not the first sentence, which is the cost of this rule.

### Round 9 result (2026-10-02, N=10 x 24 cases, mechanical, matcher v2): PASSED the gate
SHOWN 240/240 (100%, gate >= 95%); every language 30/30 (gate >= 90%); errors 0/241 attempts (gate <= 5%); first attempt
already matched 239/240. Verdict: ship. In de, es, fr, it, pt, ja, ko and zh the daily reflection on Foundation Models is the
person's own sentence plus the app's fixed translated mood line (`groundedLocales`); the model-written insight is not shown.
MAIN (informational): 160/240. Hard-mood and run-on cases 80/80 and 80/80; the ordinary-day case 0/80, because those entries
open with a breakfast sentence and the main sentence is the second one, and the shown quote is the first sentence the model's
quote holds. Grounded and harmless, but not the most telling sentence on ordinary days; not gated, not fixed.
Known limits: synthetic entries, one scorer-free mechanical metric; Russian is not on Apple's list and stays on Gemma;
other Apple-supported languages (nl, sv, da, tr, vi, nb) have no translated line, so they get the honest card.

### Shipped with round 9 (2026-10-02)
`DAILY_REFLECTION_FM_SYSTEM` is the one Foundation Models daily-reflection prompt for every language it supports (English adds
the model's checked insight; the others the quote + fixed line). On a device that has Foundation Models, Gemma does not
answer: `LocalLLMService.generate` rethrows a Foundation Models failure except `unsupportedLanguageOrLocale` (Russian today).
A language outside English and the nine gets the honest card. `DAILY_NUDGE_SYSTEM` is retired as a prompt and kept only as
`DAILY_NUDGE_LEGACY_SYSTEM` for the "How this was generated" sheet on older rows.

---
## Round 10: V1f, a longer English reflection (plan fixed BEFORE running, 2026-10-04)

Question (owner, 2026-10-04): can the English FM daily reflection be longer than one or two sentences without
inventing? Owner chose to try it alongside app-built lines (3.0.9 roadmap, Track 2).

**Variant V1f** = shipped V1e with three changes, nothing else:
- `DAILY_REFLECTION_FM_SYSTEM`, insight line: "two or three sentences" instead of "one or two", plus
  "Each sentence adds something new: do not repeat the quote or say the same thing twice." (file `system_v1f.txt`)
- `@Guide` on `insight`: "Two or three sentences ... Each sentence says something new. ..." (`DailyV1f` in fmrig.swift;
  the app's `DailyReflectionDraft` gets the identical text only if this round passes)
- `FMDailyGuard.verify(maxSentences: 3)` instead of 2. Every sentence is still checked; failing ones are dropped.

**Baseline** `prod` = the shipped prompt, guide and guard (V1e), run on the same cases for the mechanical length and
fallback comparison only (not blind-scored).

**Inputs**: byte-identical to the app: `InsightService.structuredNudgeSystemPrompt` + `buildUserMessage(title: "Daily
reflection context", ...)` from `dailyNudgeContext`, dumped by `GroundingSampleHarness.test_dumpStructuredNudgePromptsForRig`.
The prompt files dumped for V1f differ from `prod` only in the insight line of the system prompt.

**Cases**: the 13 committed cases (rigCases, groundedEdgeCases, reflectionLineCases) + 10 FRESH held-out synthetic
cases written before this run and committed in the harness (`heldOutRound10`, labels `hold3_*`): good news with a
worry, a sick pet, an exam with an offer not yet taken up, a birthday where another person is in pain, a plain day,
an unsent email, a numb day, a running milestone, two moods the same day, a hospital day.
(Rounds 5-6's `hold_*` / `hold2_*` inputs were never committed and cannot be re-run.) N = 10 each, temperature 0.45.

**Per shown output, 0/1, PASS needs 1-5:**
1. MAIN, 2. INVENT, 3. SWAP, 4. TENSE as in round 5, applied to EVERY insight sentence. SWAP is checked sentence by
   sentence for who felt or did what (round 7: the word guard cannot see one person's feeling given to another).
5. FORMAT (redefined for this round): `You wrote, "<quote>"` + 1-3 insight sentences; "you" register; no first person,
   no meta text; grammatical; **no padding**: a sentence that only restates the quote or another sentence in other
   words fails FORMAT.

**Recorded by script**: shown insight sentence count, dropped sentences, attempts, fallback, quote verbatim, errors.

**Ship rule (all must hold)**:
- shown PASS >= 95% over all 23 cases AND >= 95% on the 10 hold3 cases alone; no case with more than 2 shown failures;
- FALLBACK <= 10% overall and <= 30% in any case; shown quotes 100% verbatim; errors / guardrail refusals <= 5%;
- **LENGTH**: >= 60% of V1f's shown outputs have at least 2 insight sentences after the guard, and that share is at least
  20 points above `prod`'s. (A variant that passes every check but still shows one sentence most days does not fix
  what was asked, so it does not ship.)
One round only. If it misses, the shipped V1e stays.
Scoring: shuffled blind sheet of V1f's shown outputs (`score_tools.py sheet`), single scorer.

### Round 10 result (2026-10-04, 23 cases x 2 variants x 10, mechanical): FAILED the gate; V1e stays
| | runs | shown | fallback | errors | quotes verbatim | shown with >= 2 insight sentences |
|---|---|---|---|---|---|---|
| prod (V1e) | 230 | 220 | 0 | 10 | 220/220 | 109/220 (49.5%) |
| V1f | 230 | 214 | 6 (2.6%) | 10 | 214/214 | 210/214 (98.1%) |

- **Fails the per-case fallback gate**: hold3_vet fell back 6/10 (60% > 30%). Under the longer guide the model rewrote
  the quote ("He slept on my feet" became "Biscuit slept on my feet"), so no attempt had a verbatim quote. prod quoted
  that case correctly 10/10. Per the plan (one round only), V1f does not ship and was not blind-scored.
- LENGTH gate would have passed (98.1% vs 49.5%).
- Indicative only (single scorer, case labels visible, 30 random shown V1f outputs, not the blind protocol): about 9/30
  would fail: nonsense ("You feel no steady feeling"), ungrammatical ("You feel the flat feels too quiet"), invented
  meaning ("which shows you are moving forward slowly"). Most of the rest lengthened the reflection by listing entry
  facts ("You worked from home. You made soup for lunch."). More sentences from this model mostly add recitation.
- **Production finding (not caused by V1f)**: hold3_hospital (a day at the hospital with Grandma) was refused by the
  FM guardrail 10/10 in BOTH variants ("May contain sensitive/unsafe content"), so on FM devices such a day gets the
  fixed-line fallback or the honest card. Follow-up for the 3.0.9 roadmap.
- Decision: lengthen the English reflection with the app-picked second quote instead (`secondGroundedQuote`), which
  adds the person's own words and no model text.

## Round 11: why a hospital day gets no reflection (diagnostic, 2026-10-04) + app-side fallback
Probe (`hold3_hospital` prompt, shipped V1e guide, N = 4-6 per variant, macOS CLI and the iOS app path on the simulator):
- Swapping only the place word: "hospital", "clinic", "doctor's office", "ICU", "cancer ward", "funeral home",
  "therapist's office", "police station", "court", "rehab center" were declined 4/4 each; "office", "ER", "vet",
  "dentist" went through 4/4. Removing "Grandma" or "couldn't eat" changed nothing. The setting, not the person, triggers it.
- `SystemLanguageModel(guardrails: .permissiveContentTransformations)` did not help with guided generation (6/6 declined).
- In the app the decline arrives as `LanguageModelError.refusal` ("May contain sensitive content", code 3 on iOS 27), not
  `.guardrailViolation`; both now count (`FoundationModelEngine.isSafetyRefusal`).
No prompt can fix a decline on the input itself, so the fix is app-side and model-free (no ship gate applies to the
model): when all 3 structured attempts are declined, `InsightService.refusedDayNudge` shows the day's first quotable
sentence and the fixed mood line, with no tip (a breathing/walk tip next to an ICU or funeral entry reads as tone-deaf);
no mood line for the mood -> the honest card as before. Real FM end to end: `RealFMNudgeTests.realFoundationModelsRefusedHospitalDayGetsTheFixedLine`.
Digest, monthly report and Ask on FM still end at their honest cards when declined: not addressed here.
