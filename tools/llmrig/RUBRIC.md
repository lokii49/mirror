Rubric (fixed BEFORE any rig run, 2026-09-26). Per output, PASS only if all hold:
1 MAIN   — names the entry's main event: sickday=bad night/stomach/sleep; lunch=Priya lunch or job offer; work=presentation/dashboard bug/behind; walk=lake walk/Bruno/ducks/light.
2 INVENT — no event/object/dialogue absent from entries (rain, laughter, blanket-as-literal, "afternoon with X" not written...). Figurative wording ok if not claimed as fact.
3 SWAP   — no person given another person's action (Dev/Karan, Priya/Mom/Rahul, Omar/Nisha, Bruno/Anu).
4 TENSE  — plans not stated as happened (Dev coming over, Rahul hike Sunday, Nisha review Monday, calling Anu tomorrow).
5 FORMAT — no preamble/meta ("Here's a reflection", "Okay,"), not a question-only filler.

---
Follow-up chip + Talk It Out guided question rubric (fixed BEFORE any rig run, 2026-09-27).
Cases: fu_* = mid-draft text passed to generateFollowUp; gq_* = Q/A transcript passed to
generateGuidedQuestion. Scored only on outputs the app would show, i.e. that pass the
validateFollowUp shape check (ends "?", 8-160 chars, exactly one "?", no writer first person);
shape failures are counted separately (the app retries once on those).
Per shown output, PASS only if all hold:
1 INVENT — no person, place, object, event or detail absent from the source text (draft, or all
           answers + questions so far). Generic words (day, today, feeling, work, this) are fine;
           figurative wording is fine if not claimed as fact.
2 SWAP   — no person given another person's action or role (Dev, Priya/Mom/Rahul, Nisha/Omar,
           Bruno/Anu, Maya, Leo); Bruno (a dog) not treated as a person.
3 TENSE  — undecided/planned things not treated as done: Dev *might* come over, the offer is not
           accepted, the presentation (Thursday) and review (Monday) haven't happened, Anu not yet
           called, insurance not yet sorted, Maya hasn't moved yet, the raise not yet asked for.
Informational, not a failure: SPECIFIC (refers to something actually in the text) and
REGISTER (du/tú/you — the question addresses the writer, not a third party).
Threshold: ship as-is only if >= 95% of shown outputs PASS across all cases; otherwise ground it.

---
Follow-up prototype (a) rubric — Gemma picks one phrase, the app composes a fixed question
(fixed BEFORE any prototype run, 2026-09-27). Nothing can be invented by construction (literal
grammar of the draft's own clauses), so this scores the pick. Per output, PASS only if:
1 VALID   — exactly one of the offered phrases (the grammar should guarantee it; count anyway).
2 SALIENT — the phrase carries the writer's feeling, worry, decision or a key event:
            sickday: barely slept / stomach in knots / called in sick / not sure I want company /
                     Dev might come over;
            offer:   team has an opening / offered it to me / haven't told Mom or Rahul /
                     going back and forth;
            work:    presentation moved up / dashboard bug not fixed / Nisha review / feel so
                     behind / snapped at Omar;
            walk:    long walk with Bruno around the lake / should call Anu / weeks since we talked;
            runon:   so tired / back to back meetings / forgot lunch again / car insurance.
            de/es: the same things in translation.
            FAIL: scenery/timing/logistics only (the gold light, the ducks, "until almost 4am",
            "with the heating on", "gym at 7"), or a fragment that means nothing on its own.
Adopt (a) if the total is >= 85% and no case is below 7/10. Choose the instruction variant with
the higher total.
Added after the first prototype run (picks were near-deterministic: ~1 real sample per case, so
more cases were needed). Written BEFORE the second run; same PASS rule, SALIENT lists:
            biopsy:    Dad called / biopsy results Friday / trying not to think about it
                       (FAIL: the run, the legs, the emails);
            scenefirst:told Sam I don't want to renew the lease / took it better than expected
                       (FAIL: pink sky, the radio song);
            checklist: fraud charge being reversed / haven't replied to Meera, feel guilty
                       (FAIL: groceries done);
            good:      presented the redesign, people clapped / Kavya's praise / still buzzing;
            mid:       argument with Jonas / I was unfair to him (FAIL: slow Sunday, balcony, pasta);
            night:     can't sleep, 2am / brain going over the interview / gap year question.
            de/es mid + scenefirst: same as English.
Variant LB = variant B translated for de/es (Claude translation, not native-reviewed), added after
the first run showed the shipped pickNeutral ("most important thing of the day") picking
logistics on fu_offer_es, the same failure as English variant A on fu_walk.
Round 2 result: no variant met the bar (English B 100/110 but fu_mid 0/10; de 30/40; es LB 28/40);
picks track first/last position more than meaning. Two layout variants added AFTER seeing that
(post-hoc, same PASS rule; a winner still needs held-out cases): C = entry first, instruction
after (the English nudge's layout); D = entry, then the candidate parts as a numbered list, then
the instruction. Both use the B wording (LB translation for de/es).

---
Held-out round (fixed BEFORE running, 2026-09-28). After round 3, an advisor review pointed out
that Gemma's B pick equalled "always take the last candidate" on the round-1-3 drafts, most of
which end on the feeling. Fresh drafts put the salient part FIRST or in the MIDDLE. Scored for:
Gemma pick (B, BD; LB for de/es), always-first rule, always-last rule, and the shipped free-prose
chip (follow-up rubric above, INVENT/SWAP/TENSE).
SALIENT (prototype rule) / TENSE traps (free-prose rubric):
  hx_biopsyfirst: biopsy results Friday / can't stop thinking (FAIL: the run, pasta, baking show)
                  TENSE: results not back yet.
  hx_fightmid:    fight with Marco about money / neither apologized (FAIL: coffee with Lena,
                  quiet evening, laundry). SWAP: Lena wasn't in the fight.
  hx_newsfirst:   acceptance email from the Lisbon program / told Priti, she screamed (FAIL:
                  errands, nap). TENSE: accepted, not yet gone to Lisbon.
  hx_griefmid:    Nani's recipe book / cried over her handwriting (FAIL: rainy morning in bed,
                  pizza). Rain IS in this draft, so mentioning it is not an INVENT.
  hx_worrymid:    Ben being bullied at school / don't know what to do (FAIL: clinic, picking up the
                  kids, dinner, bedtime). SWAP: Ben is the one bullied, not the writer.
  hx_decisionfirst: going to quit the band / stopped being fun (FAIL: practice at 8, Tom's snacks,
                  the new song). TENSE: hasn't quit yet.
  hx_fightmid_de/_es, hx_newsfirst_de/_es: same as English.

---
fr/ru check before shipping (a) (fixed BEFORE running, 2026-09-28). The user chose (a). Same 6
drafts as de/es, translated: sickday, offer, mid, scenefirst (rounds 1-3), fightmid, newsfirst
(held-out). SALIENT lists are the English ones. Variants: LB (B wording, translated) and LBD
(LB + numbered parts). Also scored: the shipped free-prose chip on the same drafts, "salient AND
nothing invented" (same rules as its earlier scoring). Register (vous/вы) is noted, not scored.
Decision rule per language: ship (a) there if its best variant scores >= the shipped chip AND
>= 50%; otherwise turn the chip off on Gemma for that language.

---
Daily reflection: the line after the quote (fixed BEFORE any run, 2026-09-30). The quote is
grammar-verbatim and out of scope; this scores what Gemma writes after it (feeling line + optional
tip). Cases: rig + edge cases above, plus rl_sickfriend (Sad), rl_missing (Sad), rl_lowwork
(Drained), rl_good (Joyful), rl_neutral (Content): synthetic, shaped like a real report, no real text.
Per output:
FACT failures (any = fail): INVENT (a detail, event or assumption not in the entry), SWAP (a
  feeling or action given to the wrong person, e.g. the writer is the one who is sick), TENSE (a
  plan or wish treated as done).
GENERIC_TIP: the tip is generic self-care: breathing, mindful/mindfulness, meditation, self-care,
  "acknowledge (your|those) feelings", "small (achievable) steps", "be gentle/kind with yourself",
  "take a moment for yourself", "feel more grounded". Rest/sleep after a drained or sick day is
  not generic. Contacting someone the entry is about ("send her a message") is not generic.
CLINICAL: significant, grappling, well-being, navigating, processing, emotional toll/weight/state,
  "it's understandable", "valid".
RESTATE: the feeling line only rewords the quote, adding no angle (informational).
TIP_ON_GOOD: any tip on a good or neutral mood case (walk, lunch, checklist, punctuation, rl_good,
  rl_neutral) (informational).
Adopt a variant only if: FACT failures <= baseline's count, GENERIC_TIP <= half of baseline's,
CLINICAL <= baseline's. Among those, prefer the fewest GENERIC_TIP + CLINICAL + RESTATE.
Variants: base (current DAILY_NUDGE_GEMMA_INSTRUCTIONS); a (plain feeling words, no repeating the
quote, tip only if it follows from the entry, banned self-care and stiff words); b (a, but no tip
unless something written points to a next step); c (model writes only the feeling line; grammar
without the tip; any tip would be fixed text per mood, like the other 9 languages).
N=10 per case per variant, temp 0.45 (the app's), production-built prompts and grammars.

---
Mood detection (`EMOTION_DETECT_SYSTEM`) on Gemma (fixed BEFORE any run, 2026-09-30). Never measured
before; the Laya/Jev eval measured other models. Mood now picks the fixed tips, the other-language
reflection lines, the digest/monthly options and Mood Alerts, so a wrong mood produces confidently
wrong text. Cases: `mood/cases.tsv`, synthetic, hand-labelled by construction (one clear primary
emotion each): 36 English (3 per label), 12 German, 12 Spanish. No real journal text.
Run: the app's exact prompt (EMOTION_DETECT_SYSTEM + entry as the user turn, templated with
`rig template`), temp 0.1, max 30 chars, 3 seeds per entry, scored per output with the app's
`recognizedEmotion` rule (first alphanumeric token, case-insensitive, must be one of the 12; else
the app defaults to "Content").
HARD = Anxious, Overwhelmed, Frustrated, Drained, Sad, Numb (the set Mood Alerts and the fixed tips
treat as difficult). Everything else is NOT_HARD.
Per output:
EXACT: predicted label == gold label.
BUCKET: predicted HARD/NOT_HARD == gold HARD/NOT_HARD. This is what tips, alerts and bucket
  wording depend on, so it is the headline number.
FALSE_HARD: gold NOT_HARD, predicted HARD (a good day gets a tip / counts toward an alert).
MISSED_HARD: gold HARD, predicted NOT_HARD (a hard day is treated as fine).
UNRECOGNIZED: no valid label parsed (the app silently records "Content").
Bar for "fine, don't touch it", per language: BUCKET >= 90%, MISSED_HARD <= 15%, FALSE_HARD <= 10%,
UNRECOGNIZED <= 3%. EXACT is informational (neighbours like Sad/Drained are close); report the
confusion pairs. If the bar fails, fix candidates (prompt wording, examples per label, a grammar
over the 12 labels) are measured on the same set before anything ships.
Mood detection, hard set (added 2026-09-30 after the clear-case run scored BUCKET 100%, so that run
is an upper bound; this file and its gold labels were fixed BEFORE the hard-set run):
`mood/cases_hard.tsv`, 24 synthetic English entries that a keyword reader gets wrong: negation
("not sad"), a bad word inside a good day, a good word inside a bad day, understated hard days, mixed
days with one dominant feeling, very short entries, a long entry whose feeling comes last. Same
scoring and bar as above; report it separately (n is small, so read counts, not percentages).

---
Reflection opener rotation (fixed BEFORE any run, 2026-10-01). Only the fixed opener before the quote
changes (`You wrote, "` / `In your words, "` / `Something you wrote: "`); the quote and the grammar
after it don't. Question: does the opener change what Gemma writes after the quote? Cases: the
production-built rig + edge + reflection-line cases (`test_dumpNudgePromptsForRig`), grammar and
prompt with the opener substituted the way `groundedNudgeGrammar/Instructions(opener:)` do. N=10 per
case per opener, temp 0.45, production grammar.
Per output:
SHAPE: passes `validateGroundedNudge` (quote is an option, "That sounds"/"You seem", complete
  sentence, no first person). Bar: 100% for every opener.
FACT (any = fail, same definition as "Daily reflection: the line after the quote"): INVENT, SWAP, TENSE.
CLINICAL: significant, grappling, well-being, navigating, processing, emotional toll/weight/state,
  "it's understandable", "valid".
Adopt an alternate opener only if, versus `You wrote, "` on the same cases: SHAPE = 100%,
FACT failures <= baseline + 1, CLINICAL <= baseline + 1. Otherwise that opener stays out.
Read the unique feeling lines per case and opener (they repeat heavily at this temperature); count
each unique line once per output that produced it.
