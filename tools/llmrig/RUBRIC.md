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
