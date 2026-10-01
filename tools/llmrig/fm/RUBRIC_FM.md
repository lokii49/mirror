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
