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
