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
