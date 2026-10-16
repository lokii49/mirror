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
Follow-up probe (real FM, a four-entry hospital week, 3 runs each): weekly digest 3/3, monthly report 3/3 and Ask 3/3
answered, none declined. The decline is specific to the structured (`@Generable`) daily reflection, so the other three
need no fallback. A declined Ask saves nothing, so it never counts against Core's 15 questions a month.

---
## Round 12: reflection styles Tier 2, model-written Plain and Question (plan fixed BEFORE running, 2026-10-09)

Question (owner, 2026-10-09, roadmap §2): can Foundation Models write a reflection in a different style without
inventing, as reliably as today's? The owner picked two styles to measure:
- **Plain (S1)**: one short sentence that names what happened or how they felt, with no reading of what it means.
- **Question (S2)**: one open question about something they wrote, in their own words. Tier 1's app-built Curious
  falls back to Gentle when the entry has nothing else to ask about; this would always have a question.

**Scope and constraints (decided before the run):**
- **FM English only.** FM's own words are not shown outside English (`FMDailyGuard` is English word lists), and
  Gemma's other languages are fixed text. Gemma English is a grammar-forced feeling sentence, so a Gemma style would
  need its own grammar and its own rig round. Not in this round: on Gemma devices and in other languages, a
  model-written style falls back to Gentle, and the Tier 1 styles still apply.
- **Stored shape unchanged.** A model-written style is an input to the *next* generation, not a display-time change:
  Security Rule 4 (no regeneration within 24h) means switching style never rewrites today's reflection. The output is
  stored as `You wrote, "<quote>" <insight>`, the shape 3.0.9 / Mac 1.0.2, the widget and the lock screen parse. No
  new field, so no CloudKit schema change.
- **One variable per variant.** Only the `insight` line of the system prompt (`system_s1_plain.txt`,
  `system_s2_question.txt`) and the `insight` `@Guide` (`DailyS1Plain`, `DailyS2Question` in fmrig.swift) differ
  from what ships. The quote guide, `FMDailyGuard` (unchanged, cap 2 sentences) and the 3-attempt loop are
  byte-identical. Round 10 changed only the insight guide and the model still rewrote quotes, so the per-case
  fallback gate matters most.

**Baseline** `prod` = the shipped V1e on the same cases, for the mechanical comparison (fallback, refusals, length).

**Inputs**: dumped fresh by `GroundingSampleHarness.test_dumpStructuredNudgePromptsForRig` (byte-identical to the
app). The S1/S2 system prompts are the dumped prod prompt with only the insight line replaced.

**Cases**: the 23 committed cases (rigCases, groundedEdgeCases, reflectionLineCases, heldOutRound10) plus 10 NEW
held-out synthetic cases written before this run and committed in the harness (`heldOutRound12`, labels `hold4_*`):
a move with old photos, gardening with an aching back, an interview tomorrow (a plan), an apology that came out flat,
a niece born with a visit planned, a plain errands day, a third working weekend, a colleague back after his dad's
funeral (another person's grief), a bug fixed with relief, two moods the same day. hold3 has been read, so hold4
is the held-out set. N = 10 per case per variant, temperature 0.45. 33 cases x 3 variants x 10 = 990 runs.

**Per shown output, 0/1, PASS needs 1-5 (as round 10, applied to every shown insight sentence):**
1. MAIN: about the entry's main event or feeling.
2. INVENT: no event, object, place, person, sensation, scenery or feeling the entries lack. For S2, a question
   that names a feeling or reason the entry lacks ("Are you worried about…?" when no worry is written) fails INVENT.
3. SWAP: no person given another person's action or feeling (hold4_colleague: the grief is Kai's).
4. TENSE: plans and offers are not stated or asked about as done ("How did the interview go?" fails).
5. FORMAT: `You wrote, "<quote>"` + the insight; "you" register; no first person, no meta text; grammatical.
   S1: one plain sentence; a reading of what it means ("which shows you…") fails. S2: exactly one question,
   open (what/how/why, or a yes/no question that proposes no answer); advice dressed as a question
   ("Could you call Lena?") fails.

**Recorded by script**: shown insight word count and sentence count, ends with "?", dropped sentences, attempts,
fallback, quote verbatim, errors and safety refusals.

**Ship rule (all must hold, per style; each style is judged on its own):**
- shown PASS >= 95% over all 33 cases AND >= 95% on the 10 hold4 cases alone; no case with more than 2 shown failures;
- FALLBACK <= 10% overall and <= 30% in any case; shown quotes 100% verbatim;
- errors / safety refusals no more than prod's on the same cases + 5 points (prod already declines hold3_hospital);
- **STYLE (mechanical, so a style that reads like Gentle does not ship):**
  - S1: >= 90% of shown insights are one sentence, AND the median shown insight word count is at most 60% of prod's.
  - S2: >= 90% of shown insights are exactly one sentence ending in "?".
One round only. A style that misses stays unbuilt and Tier 1 stays as it is. Scoring: shuffled blind sheet of each
style's shown outputs (`score_tools.py sheet`), single scorer; prod's shown outputs are not blind-scored (its PASS
rate is known from rounds 5-10).

### Round 12 result (2026-10-09, 33 cases x 3 variants x 10 = 990 runs, mechanical): BOTH styles FAILED; Tier 1 stays
| | runs | shown | fallback | errors | quotes verbatim | style gate |
|---|---|---|---|---|---|---|
| prod (V1e) | 330 | 301 | 19 (5.8%) | 10 (hold3_hospital refusals) | 301/301 | n/a (one sentence 50%, median 10 words) |
| S1 Plain | 330 | 296 | 34 (10.3%) | 0 | 296/296 | one sentence 99%, median 5 words = 0.50 x prod (pass) |
| S2 Question | 330 | 308 | 22 (6.7%) | 0 | 308/308 | one question 94% (pass) |

- **S1 Plain fails**: fallback 10.3% > 10%, and three cases fell back 10/10 (> 30%): hold3_exam, hold3_run,
  hold4_weekends. On hold3_exam/run the model wrote "You feel anxious." or a lowercase sentence with a reason the
  guard drops. What it did show is mostly the mood label restated: "You felt drained." / "You felt sad." /
  "You felt joyful." are the most common outputs (54 distinct insights in 296 shown). That is not a style worth a
  setting; Quiet (quote only) already covers "less".
- **S2 Question fails**: hold4_move 10/10 and hold3_twomoods 7/10 fallback (> 30%). Of 308 shown, 162 open with
  the same template, "What does it mean…". Grounded, but it is the app-built Curious question (`followUpQuestion`)
  written by a model, with fallbacks added.
- Per the plan (one round only), neither style was blind-scored and neither is built.
- **Production findings (prod, not caused by the styles)**, follow-ups for the roadmap:
  - hold4_weekends fell back 10/10: the model copied the prompt's mood line, "Drained. Source: written entry.", as
    the quote. The guard rejects it as designed, so the day gets the fixed mood line instead of a reflection. Likely
    cause (untested): the user message layout puts `Mood: X. Source: written entry.` directly above the text, and
    this entry opens with a short sentence. All 33 cases share that layout and only this one copied it, so this
    needs its own rig round before any change.
  - hold4_garden fell back 5/10: "you feel a sense of relief" ("relief" is not in the entry; the guard is right).
  - hold3_hospital: prod refused 10/10 ("May contain sensitive content") as in round 11, but S1 and S2 were
    refused 0/10 each and showed a reflection all 10 times. The variants differ from prod only in the insight
    line and `@Guide`, so that wording affects the refusal, and round 11's "no prompt can fix a decline on the input
    itself" does not hold for these variants. One case, one round, with variants that failed elsewhere: this is a
    lead for its own round, not evidence that a guide change fixes the refusal.

## Round 13: FMDailyGuard name casing (plan fixed BEFORE running, 2026-10-15)

**Change under test** (`39fcab8`, unpushed): `FMDailyGuard.personNames` now counts a tagged name only where it is
capitalized mid-sentence. Reason: on iOS 27 the NLTagger labels a sentence-initial noun as a name ("Exam is on
Friday" tags Exam as a PlaceName on an iPhone 14 Pro), so `restoreNames` turned the insight's "the exam" into
"the Exam" (SecondQuoteTests failed on 3.1.3). The guard's accept/reject decisions are not meant to change; only
the casing step. The trade-off: a name the person writes only at a sentence start, if the model writes it in
lowercase, stays lowercase.

**Method.** One model, one prompt: prod (the shipped V1e, `DAILY_REFLECTION_FM_SYSTEM` dumped by
`test_dumpStructuredNudgePromptsForRig`, `@Guide` and 3-attempt loop unchanged). fmrig built with the NEW
`FMDailyGuard.swift` records every attempt's raw quote and insight (`raws`). The OLD guard (`FMDailyGuard.swift` at
`39fcab8^`) is then replayed over the same raws offline (`replay13.swift`), so both guards judge identical model
outputs and only the guard differs. Note: the dev Mac's tagger, not an iPhone's, decides names here (macOS 27.0.1).

**Cases**: the 33 cases of round 12 plus 10 NEW held-out synthetic cases written before this run
(`heldOutRound13`, labels `hold5_*`): everyday words opening a sentence (Work, Gym, Dinner, Interview, Grief, Rent)
and names or places only at a sentence start (Priya, Tomás, Lena, Lisbon), plus a name mid-sentence (Arjun).
N = 10 per case, temperature 0.45: 43 x 10 = 430 runs.

**Gates (mechanical, all must hold):**
- G1 no regression: for every run, old and new guards show the same attempt or both fall back, with the same
  number of dropped sentences; shown texts differ only in letter case.
- G2 the fix: under the new guard, 0 shown insights capitalize mid-sentence a word that the entries capitalize
  only at sentence starts (old guard's count reported beside it).
- G3 the trade-off: under the new guard, at most 5% of shown outputs on hold5_priya, hold5_tomas, hold5_grief and
  hold5_lisbon contain Priya / Tomás / Lena / Lisbon in lowercase.
- G4 sanity (model drift since round 12): prod fallback <= 10% overall; errors only on hold3_hospital.

**Decision rule**: all pass -> 39fcab8 stays and 3.1.3 is pushed. G1 or G2 fails -> 39fcab8 is reverted before the
push and the SecondQuoteTests failure goes back to the owner. Only G3 or G4 fails -> report to the owner before
pushing. One round only.

### Round 13 result (2026-10-15, 43 cases x 10 = 430 runs, prod, mechanical): G1, G2, G3 pass; G4 fails (not the guard); owner decides
Tools: `fmrig.swift` (new guard) + `replay13.swift` built with each guard + `gates13.py`. The new replay reproduces
fmrig's shown outputs exactly (0 mismatches).
- **G1 pass**: 0 runs where old and new differ beyond letter case (same attempt, quote, fallback, dropped count). 14
  runs differ in casing only.
- **G2 pass**: sentence-start words capitalized mid-sentence: old 14, new 0. All 10 hold3_exam runs read "the Exam"
  under the old guard ("You feel anxious about the Exam."), as on the iPhone.
- **G3 pass as defined**: 0/30 lowercase names on the hold5 name cases, but only because the model never named
  Priya, Tomás, Lena or Lisbon there. **The trade-off did show elsewhere**: hold4_colleague ("Kai came back to the
  office today…", Kai only at a sentence start) shows "kai" in lowercase in 4/10 runs under the new guard (old: 2/10;
  the model writes "kai" and the old guard fixed two of them).
- **G4 fails (model, not guard)**: fallback 28/430 = 6.5% (round 12: 5.8%; hold4_weekends 10/10 and hold4_garden
  8/10 as before). Errors: hold5_grief refused 10/10 "May contain sensitive content" (a grief entry mentioning a
  dad); hold3_hospital was not refused this time (0/10). Production finding: grief days can get no reflection;
  `refusedDayNudge` covers it in the app.
- Tagger on the dev Mac: Kai and Priya are PersonalName, Exam and Lisbon PlaceName. A sharper rule (at a sentence
  start trust only PersonalName) would keep Kai and drop Exam; it is not this round's change.
Per the decision rule (G4 failed) this goes to the owner before the push.

## Round 14: sentence-start names, PersonalName only (plan fixed BEFORE running, 2026-10-15)
Owner, after round 13: sharpen the rule. **Change**: at a sentence start, a tagged word counts as a name only when the
tagger calls it PersonalName (mid-sentence, any name tag counts, as before 39fcab8). Round 13 showed Kai/Priya tagged
PersonalName and Exam/Lisbon PlaceName on the dev Mac; on the iPhone 14 Pro, Exam was PlaceName.
**Method**: no new model runs. The same 430 raw outputs of round 13 replayed with the round-14 guard
(`replay13.swift` built against it) beside the old guard (`39fcab8^`).
**Gates**: G1 as round 13 (old vs round-14: differences in letter case only). G2: no mid-sentence capital on a word
the entries capitalize only at sentence starts, except words the dev Mac's tagger calls PersonalName there (listed);
hold3_exam shows "exam" 10/10. G3: hold4_colleague shows "kai" in lowercase in no more runs than the old guard (2/10).
Pass -> commit the guard change and push 3.1.3. Fail -> back to the owner.

### Round 14 result (2026-10-15, round 13's 430 raw outputs replayed): PASSED; the PersonalName rule ships
- G1 pass: 0 runs differ from the old guard beyond letter case (10 differ in case: all hold3_exam).
- G2 pass: hold3_exam shows "the exam" 10/10 (old guard: "the Exam" 10/10). The only other mid-sentence capitals
  on sentence-start words are "Kai" (hold4_colleague, 4 runs), which the tagger calls a PersonalName: the exception.
- G3 pass: hold4_colleague shows "kai" in lowercase in 0/10 runs (old guard 2/10, round 13's rule 4/10).
- Model numbers are round 13's (same outputs): fallback 6.5%, hold5_grief refused 10/10.

## Round 15: the weekly digest on Foundation Models, in the Gemma digest's shape (plan fixed BEFORE running, 2026-10-15)
Owner, 2026-10-15: FM insights paraphrase the context instead of using the person's words, and the Gemma weekly
digest (quotes + a line after each) reads better. FM weekly/monthly/Ask have never had a rig round: they are free
prose with only the word-overlap backstop. Weekly first; monthly and Ask get their own rounds after.

**Variants** (same dumped user message, `test_dumpDigestPromptsForRig`, byte-identical to the app):
- **W0 baseline**: shipped `WEEKLY_DIGEST_SYSTEM`, free prose (`fmrig free`).
- **W1**: `system_digest_d1.txt` + `@Generable WeeklyDigestD1` (theme, then quote + one line for energy / building /
  watch, then boost and next week). The app composes the Gemma digest's text (same six labels, `You seemed most
  <entry's mood> when you wrote, "<quote>" …`, `You wrote, "<quote>" …`), and `FMDigestGuard` (compiled into the rig)
  must accept it: each quote found in this week's entries, the three quotes different, building not from a hard-mood
  entry when the week has another, every model line passing `FMDailyGuard.cleanSentences` against the week. Up to 3
  attempts; none accepted -> fallback (the app's honest card).

**Cases**: 10 synthetic weeks, no real journal text: `wk_rigA` (the 13 daily rig cases as one week), `wk_rigB`
(digestWeekB) and 8 new weeks written for this round (`digestRigWeeks`: caregiver, good, hard, neutral, sparse,
runon, breakup, exam). N = 10 per case per variant, temperature 0.45 (`dailyNudge`'s, as the daily rounds).

**Scored per shown digest**, blind (variant labels removed, shuffled), one section at a time, 0/1:
1. **INVENT**: no event, object, place, person, sensation or scenery the entries don't contain; no feeling the
   entries don't state or plainly show.
2. **SWAP**: no person given another's action; plans not stated as done.
3. **VALUE**: the section says something a reader would not get from the quote or entry alone (a meaning, a link
   between two days, a concrete next step tied to their words). A restatement of the quote, or generic advice
   ("take some time for yourself") scores 0.
A digest PASSES when all six sections pass 1 and 2.

**Gates for W1 to ship (all must hold)**:
- G1 fallback <= 10% of runs, and no case above 30%.
- G2 shown PASS >= 95% of shown digests, and W1's invented-section rate below W0's.
- G3 VALUE: W1's mean VALUE per section >= W0's.
- G4 quotes: 100% of shown quotes verbatim (by construction; checked by script).
Pass -> `WEEKLY_DIGEST_FM_SYSTEM` + `WeeklyDigestDraft` ship for English FM digests; other languages keep the
shipped path this round. Fail -> report to the owner with the numbers; no prompt change ships. One round, plus at
most one revision (W2) if only G1 fails, fixed in writing before it runs.

### Round 15, W2 (fixed BEFORE running, 2026-10-15; owner said go after W1's partial numbers)
W1 partial (7 of 10 weeks): fallback ~70% (wk_hard and wk_neutral 10/10); W0 shown 10/10. Most rejected lines
contained "quiet"/"quietly", which `FMDailyGuard` counts as an added state word; the W1 prompt itself said "quietly
costing them". The rest were real catches ("before the grant review", "find a quiet space").
**W2 changes, nothing else:**
1. Prompt (`system_digest_d2.txt`) and the watch `@Guide` say "may be costing them or wearing on them", never
   "quietly"; one added rule: do not call anything quiet unless they did.
2. `FMDigestGuard.merge`: each section is taken from the first attempt in which it passes (same checks as W1), quotes
   still distinct across the chosen sections. Attempts stop as soon as all six sections are filled; at most 3.
   The guard itself (`FMDailyGuard.cleanSentences`) is unchanged.
Same cases, N, temperature, scoring and gates G1-G4 as W1. W2 is the last revision this round.

### Round 15 result (2026-10-16): W1 and W2 FAILED; nothing ships. The shipped FM digest (W0) invents in half its sections
Runs: W0 100/100 shown; W1 25/100 shown (75% fallback); W2 47/100 shown (53% fallback; wk_exam 10/10, wk_neutral 9/10).
W2's unfilled sections at fallback: energy 26, boost 15, nextWeek 10, watch 7, building 6.
Blind scoring (3 scorers, 97 digests shuffled, labels removed: all 47 shown W2 + 5 W0 per week; the two shapes
are recognisable, so blind only in labels):

| | digests PASS | sections invented | swap | VALUE / section |
|---|---|---|---|---|
| W0 shipped free prose | **0/50** | **146/300 (48.7%)** | 9 | 0.51 |
| W2 structured + guard | 30/47 (64%) | 20/282 (7.1%) | 1 | 0.19 |

- G1 fail (53%), G2 fail (64% < 95%, though invented rate is far below W0's), G3 fail (0.19 < 0.51), G4 pass.
- W0 inventions are scenery and events ("the dent in the wall", "the notebook from the corner", "your breath steady
  as the pavement warmed") in every section, worst in YOUR ENERGY (44/50) and MOOD BOOST (34/50). This is what
  English FM users get today.
- W2's inventions are mostly in YOUR ENERGY (12/20) and come from the "connect it to another day" instruction:
  false links ("especially after skipping dinner", "after the quiet time with Chris"). W2's low VALUE: theme reads
  as a list of nouns (0/47), and most reads restate the quote; MOOD BOOST is its best section (25/47).

## Round 16: W3, the weekly digest with fixed app lines where the model fails (plan fixed BEFORE running, 2026-10-16)
Owner, after round 15: go ahead with W3. **Changes from W2, nothing else:**
1. Prompt `system_digest_d3.txt` + `WeeklyDigestD3` guides: no "connect it to another day" (round 15: most of W2's
   inventions were false links between days). Theme is one short phrase about what the week was about, not a list of
   names. Each read says what the moment seems to show they need, hope for or worry about, and must not retell it.
2. `FMDigestGuard.assemble`: same per-section checks and merge across up to 3 attempts as W2. A section still empty
   after 3 attempts is filled by the app, never by the model:
   - quote section whose quote passed but whose line didn't: the quote + a fixed line (`fixedReads`);
   - quote section with no passing quote: the app picks a sentence of 4+ words from an entry of the right kind
     (energy: any; building: not a hard mood when the week has another; watch: a hard mood when it has one), not
     overlapping the other quotes, + the fixed line;
   - theme / boost / next week: a fixed line.
   Nothing to quote at all (no sentence of 4+ words) -> fallback.
Same 10 weeks, N = 10, temperature 0.45.
**Gates** (G1-G4 as round 15, plus G5):
- G1 fallback <= 10%. G2 shown PASS >= 95% and invented-section rate below W2's 7.1%.
- G3 VALUE per section >= W0's on clean sections only (round 15: W0 0.39 useful-and-clean per section; W0 0.51 raw
  is inflated by invented sections scoring VALUE).
- G4 quotes verbatim 100%. G5 fixed (app-written) sections <= 25% of all sections.
Pass -> wire into the app for English FM digests (other languages unchanged), with tests. Fail -> owner.
Scoring: blind, 3 scorers, W3 shown digests only (W0's round-15 scores are reused as the baseline).

### Round 16 result (2026-10-16, W3, 10 weeks x 10, blind-scored by 3 scorers): FAILED G2 and G3; nothing ships
| | shown | digests PASS | sections invented | swap | useful-and-clean / section | app-fixed sections |
|---|---|---|---|---|---|---|
| W0 shipped (round 15) | 100% | 0/50 | 48.7% | 9 | 0.39 | - |
| W2 (round 15) | 47% | 30/47 | 7.1% | 1 | 0.18 | - |
| **W3** | **100%** | **46/100** | **9.5%** | 7 | **0.25** | 49/600 (8%) |

- G1 pass (0% fallback), G4 pass, G5 pass (8%). G2 fail (46% < 95%; 9.5% is not below W2's 7.1%). G3 fail (0.25 < 0.39).
- The scorer prompt this round also counted unstated cause-and-effect between days as invented; round 15's did not.
  So W2 vs W3 is not exactly like for like.
- NEXT WEEK is the worst section (18 invented): the field asks for something upcoming, so the model makes one up
  ("Next week, the talk about the senior role": the entry says next month; "the final exam review will begin").
  MOOD BOOST swaps people ("Talk to Tara about working from Mom's place": the request was to Deepa, 4 runs).
  Reads add feelings the week-wide guard allows because another entry used the word ("heavy", "strain").
- The 49 app-fixed sections scored VALUE 0/49, as expected.

## Round 17: W4 = W3 aimed at round 16's three causes (plan fixed BEFORE running, 2026-10-16)
Owner chose another round. **Changes from W3, nothing else:**
1. NEXT WEEK: prompt/guide ask for one kind, practical sentence about something they wrote is still unfinished or
   undecided, without saying when anything will happen. Guard: a model line with a timing phrase the entries don't
   contain ("next week", "next month", "tomorrow", "coming up", "soon", "will begin", "as it nears") is dropped
   (`FMDigestGuard.timingPhrases`).
2. Names stay with their entry: for every name in a model line, at least 60% of the line's other content words
   (4+ letters, not stop words) must appear in one entry that contains that name. Checked on every model line.
3. A read under a quote is checked against the quoted entry only (feeling words, names), not the whole week.
4. (Added before running.) MOOD BOOST prompt/guide: "using a person and a task from the same entry, or a task or
   thing they named" instead of "in the next few days, using a person, task or thing they named this week".
Names are found with `FMDailyGuard.personNames` (tagger, PersonalName only at a sentence start), now internal.
Same weeks, N, temperature, fixed lines and gates G1-G5 as round 16. Scored blind by 3 scorers with round 16's
scorer prompt. Last weekly round: pass -> wire into the app for English FM digests; fail -> owner picks W3 interim or
leaving W0.
**Held-out (added 2026-10-16 while W4 ran, before any W4 result was seen):** W4's rules were shaped by the 10 weeks
above, so 5 new synthetic weeks (`digestHeldOutWeeks`: ho_move, ho_newparent, ho_volunteer, ho_flu, ho_short; new
names incl. one only at sentence starts, a pet, future plans, two similar friends) run W4 and W0 at N = 10. Gates
G1-G5 must also hold on the held-out weeks alone (W0's held-out VALUE is the G3 bar there). A pass on the old weeks
only is not a pass.

### Round 17 result (2026-10-16, W4, 10 original weeks x 10, blind-scored by 3 scorers, round 16's prompt): FAILED
| | shown | digests PASS | sections invented | swap | useful-and-clean / section | app-fixed |
|---|---|---|---|---|---|---|
| W3 (round 16) | 100% | 46/100 | 9.5% | 7 | 0.25 | 8% |
| **W4** | **100%** | **48/100** | **12.2%** | **2** | **0.17** | **21.5%** |

- G1 pass, G4 pass, G5 pass (21.5%, MOOD BOOST app-fixed in 52/100). G2 fail, G3 fail (0.17 < 0.39).
- Swaps fell (7 -> 2): the names rule works. The timing rule ended invented dates. But NEXT WEEK now invents
  indecision instead (35 invented: "you haven't decided what to do with them", "the chat with Grandpa is still
  waiting to unfold"): asked for something unfinished, the model makes something unfinished up.
- Pattern across W1-W4: each field that asks for a kind of content (an upcoming event, something undecided,
  something costing them on a peaceful week) gets that content invented when the week has none.
- Held-out weeks: stopped after ho_move (W4 already failed on the original weeks); not scored.
Per the plan, the owner picks: W3 as an interim, or keep W0.

## Round 18: W3 as an interim, held-out check (plan fixed BEFORE running, 2026-10-16)
Owner, after round 17: ship W3 as an interim for English FM digests (it failed G2/G3 in round 16 but invents in
~1 section in 10 against W0's ~1 in 2). W3 was only measured on the weeks that shaped it, so before it ships:
W3 (round 16's exact prompt, guides and guard; the `fmrig3` binary) and W0 on the 5 held-out weeks, N = 10, blind
scored together with round 16's scorer prompt (labels removed, shuffled).
**Interim bar** (not round 15's gates; the owner accepted W3 below them): on the held-out weeks, W3 fallback <= 10%,
W3's invented-section rate at most half of W0's on the same weeks, app-fixed sections <= 25%. Miss -> back to the
owner before anything ships. The app ships round 16's FMDigestGuard (no round-17 rules).

### Round 18 result (2026-10-16, 5 held-out weeks x 10, blind-scored by 3 scorers): two of three bars met; one missed by a refusal
| held-out weeks | shown | digests PASS | sections invented | swap | useful-and-clean / section |
|---|---|---|---|---|---|
| W0 shipped | 50/50 | 0/50 | 205/300 (68.3%) | 25 | 0.18 |
| W3 | 40/50 | 20/40 | 19/240 (7.9%) | 10 | 0.20 |

- Invented at most half of W0's: met (7.9% vs 68.3%). On these weeks W3 is also as useful as W0 on clean sections.
- **ho_move: FM refused W3 10/10 ("May contain sensitive content"); W0's free prose was not refused.** In the app every
  attempt refused means `FMDigestGuard.assemble([])`: a digest of the week's own sentences and fixed lines only.
- App-fixed sections: 39/240 (16%) on the four answered weeks; counting ho_move as 60 fixed, 99/300 (33%) > 25%: missed.
Per the plan this goes back to the owner before anything ships.

### Shipped (2026-10-16, owner decision after round 18): W3 as an interim, English and the other FM languages
- English FM digests: `WEEKLY_DIGEST_FM_SYSTEM` (= `system_digest_d3.txt`) + `WeeklyDigestDraft` (= WeeklyDigestD3's
  guides) + round 16's `FMDigestGuard`, 3 attempts, app-filled sections (`InsightService.structuredFMDigest`).
  Owner accepted the ho_move refusal case (an all-app digest of the week's sentences) over W0's 68% invented.
- One app-side change after the rounds: on a week whose only good day went to YOUR ENERGY, an app-picked hard
  sentence under WHAT'S BUILDING gets "That stood out this week." instead of "worth holding on to" (seen end to
  end on the Mac's FM: "Woke up with a fever and chills." That sounds like something worth holding on to.).
- de/es/fr/it/pt/ja/ko/zh on FM (owner: "fix this for all languages"): the same draft, but only its three quotes
  are used, each matched with `FMDailyGuard.matchOption` to the Gemma localized digest's options; all other text is
  `groundedLocales`' fixed translated lines, as on Gemma (`structuredFMLocalizedDigest`). No model-written text is
  shown, so nothing can be invented; NOT rig-measured for how often the model's picks match (app picks fill gaps).
- Still open: languages outside the 10 keep the free-prose digest on FM; reads can say "they" instead of "you".

## Round 19: the monthly report on Foundation Models, in the Gemma report's shape (plan fixed BEFORE running, 2026-10-16)
Owner: go ahead with the next items (monthly, then Ask, then the daily two quotes). FM monthly is free prose on
`MONTHLY_REPORT_SYSTEM` with only the word-overlap backstop, never measured.
**Variants** (same dumped user message, `test_dumpMonthlyPromptsForRig`, byte-identical to the app):
- **M0**: shipped `MONTHLY_REPORT_SYSTEM`, free prose.
- **M1**: `system_monthly_m1.txt` + `@Generable MonthlyM1`, built on round 15-17's lessons from the start: no field
  asks for something the month may not have (no "upcoming", no "undecided", no link between days); every line
  hangs off a quote or a fixed opener. Composed in the Gemma report's text: `A <image>.` / `You seem pulled between
  <a> and <b>.` / `On <date>, you wrote, "<quote>" <line>` / `You wrote, "<good-day quote>" You seem to be becoming
  someone who <...>.` / `You wrote, "<hard-day quote, not Sad/Numb>" Maybe it's time to let go of <...>.` /
  `<question>?`. `FMMonthlyGuard` (compiled into the rig): quotes found in the month, distinct, mood rules as Gemma's;
  every model line through `FMDailyGuard.cleanSentences`; each section from the first of up to 3 attempts where it
  passes; still-empty sections filled by the app (its own quote + a fixed line, or a fixed line).
**Cases**: 6 synthetic months of 10-14 entries spread over the month (`digestRigMonths`), built from the round-15/17
weeks: 4 from the original weeks, 2 (`mo_ho_*`) from the held-out weeks. N = 10, temperature 0.45.
**Scoring**: blind, 3 scorers, round 16's scorer prompt with the monthly section names; M0 and M1 mixed.
**Ship bar** (the interim bar the owner accepted for the weekly digest): M1 fallback <= 10%, invented-section rate
at most half of M0's, app-fixed sections <= 25% (refused months reported apart); usefulness reported, not gated.
Also on the 2 held-out months alone. Miss -> owner.

### Round 19 result (2026-10-16, 6 months x 10 x 2 variants, blind-scored by 4 scorers): ship bar met; usefulness very low
| | shown | reports PASS | sections invented | swap | useful-and-clean / section |
|---|---|---|---|---|---|
| M0 shipped, all months | 60/60 | 2/60 | 175/360 (48.6%) | 14 | 0.19 |
| **M1, all months** | **60/60** | 17/60 | **43/360 (11.9%)** | 16 | **0.03** |
| M0, held-out months | 20/20 | 1/20 | 46.7% | 10 | 0.16 |
| M1, held-out months | 20/20 | 1/20 | 17.5% | 11 | 0.06 |

- Bar: fallback 0% (no refusals), invented at most half of M0's (11.9% vs 48.6%; held-out 17.5% vs 46.7%), app-fixed
  58/360 = 16% (release 21, image 15, tension 13). Met.
- Usefulness (reported, not gated) is far below M0's: the model's lines mostly restate the quote.
- M1's invented sections: A MOMENT THAT SHIFTED SOMETHING (25: its line restates another day's entry), TENSION (10:
  "Omar didn't call" from "omar called, yusuf didnt"). Swaps are about the same as M0's.

### Shipped (2026-10-16, owner decision after round 19): monthly report = the person's sentences + app lines, every FM language
M1's own lines were honest but clumsy ("someone who baking bread", "let go of everything feels heavy and slow") and
scored 0.03 useful. Owner chose: on FM the model only picks the moment / becoming / release sentences (matched with
`FMDailyGuard.matchOption` to the Gemma report's options); image, tension, the line after each quote and the question
are fixed text by the month's dominant mood: `englishMonthlyText` in English, `groundedLocales` elsewhere
(`groundedMonthlyParts` is the one composer for both). Nothing model-written is shown, so nothing can be invented.

## Round 20: Ask on Foundation Models (plan fixed BEFORE running, 2026-10-16)
FM Ask is free prose on `ASK_SYSTEM`, never measured; Gemma Ask answers only with the person's dated sentences.
**Variants** (dumped user message, `test_dumpAskPromptsForRig`; entries found by the app's own retrieval):
- **A0**: shipped `ASK_SYSTEM`, free prose (plus the no-answer line the app appends).
- **A1**: `system_ask_a1.txt` + `@Generable AskA1`: `answer` (one or two sentences to "you"), `quote1`, `quote2` (may be
  empty). Shown: `<answer> The closest things you've written: On <date>, you wrote, "<quote>" …`. Each quote must be
  found in the retrieved entries; `answer` goes through `FMDailyGuard.cleanSentences` against them. Up to 3 attempts;
  if no answer passes, the quotes alone (Gemma's shape); no quote found -> the app's first retrieved sentence.
**Cases**: 4 synthetic month pools x 5 questions (20), each pool with one question the entries can't answer.
N = 5, temperature 0.45 (`ask`'s).
**Scoring** (blind, A0/A1 mixed): per answer, INVENT (no fact, person, event or feeling the entries lack; for an
unanswerable question, any claimed answer = invented), SWAP, ANSWERS (the text actually answers the question from the
entries, or honestly says it isn't there), VALUE.
**Ship bar**: A1 invented-answer rate at most half of A0's, 0 invented answers on unanswerable questions beyond
A0's count, fallback (no text) 0%. ANSWERS and VALUE reported. Miss -> owner.
**A1 revised before the round (2 probes on mo_caregiver_hard, 2026-10-16):** the first A1 copied "me" from the
entry, appended the no-answer phrase to real answers and rewrote quotes. Now `found` comes first and A1 never says
"you haven't written about this" (Gemma's measured lesson: model no-answer judgements were often wrong); when nothing
is found or the answer fails, the closest sentences are shown under "The closest things you've written:".

### Round 20 result (2026-10-16, 20 questions x 5 x 2 variants, blind-scored by 4 scorers): bar met by a hair; A1 far less useful
| | shown | answers invented | swap | answers the question | useful |
|---|---|---|---|---|---|
| A0 shipped | 96/100 (4 errors) | 21/96 (22%) | 3 | 95% | 59% |
| A1 | 100/100 | 10/100 (10%) | 6 | 74% | 14% |

- Unanswerable questions: 0/20 invented for both.
- A1: 73 answers + quotes, 27 quotes only; 24 runs needed an app-picked quote (the model's wasn't verbatim).
- A1's errors are mostly swaps and false negatives: "You did not see anyone this month" (Leo visited), "You helped with
  the night feeds" (Sam did), "raj said it WAS the cache" (the writer did).
- Unlike the digest (49-68% invented) and the monthly report (49%), free-prose Ask invents in 22% and is the most
  useful text FM writes in this app. Goes to the owner.

## Round 21: Ask = today's answer + the person's own sentences under it (plan fixed BEFORE running, 2026-10-16)
Owner, after round 20: keep the free-prose answer (useful 59%) and show 1-2 of the person's dated sentences under it
as evidence. **A2**: unchanged `ASK_SYSTEM` answer, then one structured call (`system_ask_quotes.txt` + `@Generable
AskQuotes`: quote1, quote2) given the question, the retrieved entries and that answer, asked for the sentences that
back the answer. Each quote must be found in the retrieved entries (`FMDailyGuard.locate`) and is shown as `On <date>,
you wrote, "<quote>"` under "The closest things you've written:". None found -> the answer alone (today's behaviour).
No quotes after the no-answer phrase.
**Inputs**: round 20's 96 A0 answers (same prompts), so only the quote step is new. N = 1 per answer.
**Scoring** (blind, 3 scorers): per shown quote, SUPPORTS (it backs what the answer says, or is the entry the answer
is about) and DATE (the date is that entry's).
**Ship bar**: >= 80% of answered (non-no-answer) responses get at least one verified quote; >= 90% of shown quotes
SUPPORT; 100% DATE. Miss -> owner.
**Round 21 first count (before scoring): coverage 52/82 = 63%, under the bar.** 10 were refusals ("May contain
sensitive content"); most of the other 20 were verbatim quotes from the prompt's *older excerpts*, which the rig's
matcher did not search. Fix decided before re-counting: quotes are matched against every entry the model was shown
(retrieved + older excerpts, with their dates). Replayed offline over the same 96 outputs; no new model runs.

### Round 21 result (2026-10-16): shipped by the owner with coverage under the bar
- Shown quotes: 86/90 (96%) back the answer they sit under; dates 90/90 right. Both bars met.
- Coverage: 61/82 answered responses get a quote (74%; 61/72 = 85% without the 10 refusals of the quote call), under
  the 80% bar. Without a quote the answer shows alone, as before; the owner shipped it on that basis.
- In the app (`InsightService.askEvidenceQuotes`): quotes matched against every entry the Ask prompt shows; English
  with `FMDailyGuard.locate` (as measured), the other grounded languages with `matchOption` and their `askPrefix`
  lines (not rig-measured); other languages and the no-answer phrase get no quotes. End to end on the Mac's FM
  (simulator): the mom question got two dated sentences, the sleep question none, the trips question the no-answer.

## Round 22: the daily reflection's second quote, picked by the model (plan fixed BEFORE running, 2026-10-16)
Owner: tie two of the person's own sentences together. Today the second quote ("You also wrote, …", display only,
never stored) is the day's longest other sentence (`secondGroundedQuote`), not a related one. Lesson from rounds
15-17: a model-written link between two sentences is where FM invents, so the model only *picks* the related
sentence; the app writes the joining words. Not stored in `Insight.content` (old versions would leak it): kept per
device as a reference (entry id + sentence index), never as text.
**Variants** (same dumped prompts as rounds 12-14, `test_dumpStructuredNudgePromptsForRig`, + 6 new held-out days):
- **P**: shipped V1e (`DailyV1bEasy`, `FMDailyGuard`, 3 attempts), plus the app's `secondGroundedQuote` pick.
- **R**: the same struct with one more field after `insight`: `relatedQuote` ("a different sentence from today's
  entries that connects to the quote, copied word for word, or empty"); everything else unchanged.
**Mechanical gates (R vs P, same cases):** G1 fallback (no reflection) at most P's + 2 points; G2 the shown quote and
insight pass the same guard, so the reflection itself must not change: shown-insight PASS on a blind sample of 60
R vs 60 P not lower by more than 5 points; G3 `relatedQuote` found in today's entries, distinct from the main quote,
in >= 80% of runs where today has another quotable sentence.
**Blind (pairs):** for each run with both picks, the scorer sees today's entries, the main quote, and two candidate
second quotes (R's pick, the app's pick) in random order and says which one connects better to the main quote, or
neither. Ship if R's pick wins more often than the app's and G1-G3 hold. N = 5 per case.

### Round 22 result (2026-10-16, 49 cases x 5 x 2 variants): FAILED; the daily reflection stays as it is
- G1 pass: fallback/error 30/245 (R) vs 29/245 (P); adding the field does not hurt the reflection.
- G3 fail: R's related sentence was a real, different sentence of today in 98/143 runs (69% < 80%); misses: the main
  quote repeated (32), empty (7), not verbatim (6). In 52 of the 98 it was the sentence the app already picks.
- Blind pairs, 46 runs where the picks differ (2 scorers): the app's longest-sentence pick connected better 26, R's
  15, neither 5; on the 6 new held-out days the app won 10-0. The model's pick is not better than the app's, so no
  related-quote field ships; `secondGroundedQuote` stays.

## Round 23: two guard fixes, replayed (plan fixed BEFORE running, 2026-10-16)
Owner: fix the "they" lines and the prefix matching. **Changes:**
1. `FMDailyGuard.matches` (shared by the daily reflection and every FM digest/report line): a word shorter than five
   letters matches only itself or itself plus a plain ending (s, es, ed, er, est, ness, ing, ful, ly, y). Today it
   compares the first 3-4 letters, so "over" counts as "overwhelmed" and "numbers" as "numb" (the line is dropped
   unless the entries carry that feeling).
2. `FMDigestGuard` lines only: a line that speaks about "they / them / their" and never to "you / your" is dropped
   ("That moment seems to show they need space"). The daily guard is not changed by this.
**Method**: no new model runs. Old and new guards judge the same saved outputs: round 22's 490 daily runs (every
attempt), round 16's 100 W3 digests and round 18's 40 held-out W3 digests. Every line whose verdict flips is listed.
**Gates**: G1 daily: every newly accepted insight sentence is read by hand and contains no feeling the entries
don't carry (0 allowed); fallback not higher than before. G2 weekly: every newly accepted line read by hand, 0
invented feelings; no shown line speaks of "they" without "you"; app-fixed sections not higher than before.
Pass -> ship both. Fail -> owner.

### Round 23 result (2026-10-16, replay): G1 passes; G2 misses on app-fixed sections only
- Daily (587 attempts of round 22): 1 verdict changes (sickday: "You feel drained and uncomfortable, with many ups and
  downs." now kept; "ups" no longer counts as "upset"); no invented feeling. Fallback unchanged.
- Weekly: lines that speak of "they" without "you": 61 -> 0 (round 16's 100 digests), 18 -> 0 (round 18's 40). App-fixed
  sections 49 -> 88 of 600 (8% -> 15%) and 39 -> 43 of 240 (16% -> 18%): under the interim's 25%, but higher, so G2
  as written misses. Cause found: W3's own guide says "what that moment seems to show they need", and the model
  copies "they"; a "you" wording needs a model round. To the owner.
