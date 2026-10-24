# Gemma Ask: which sentences get picked (written 2026-10-23, before any run)

Owner report (2026-10-23, iPhone 13, Gemma, Smart Search installed): Ask's quotes are often off-topic. In every
answer of one screenshot the second quote had nothing to do with the question, and a one-word "Health?" got a
family line. Gemma Ask answers only with the person's dated sentences (2026-09-27: free prose swapped who did
what); that stays. This round measures only **which sentences are shown**. No prose answer, no "you haven't written
about this" verdict (both measured wrong before, README "Ask you haven't written about this").

## What the shipped path does (`InsightService.ask` → `groundedAskPlan`)

1. Retrieval: EmbeddingGemma top 10 (Smart Search installed and index coverage ≥ 0.95), else keyword search, which
   returns the 10 newest entries when no keyword matches. Plus the 8 newest entries not retrieved. 18 entries.
2. Entries mentioning the question's stems (+ English word-embedding neighbours) go first, the rest after.
   Hard/good-lean questions ("stressed", "happy") take only hard/good-mood entries.
3. The prompt shows those entries through `formatEntries(maxChars: 3_800)`: entries past the budget are cut.
4. Options: sentence 1 of every entry, then sentence 2 of every entry, …, capped at 40. The grammar lets Gemma
   pick one option and optionally a second.

Suspected defects: (a) options from entries the prompt cut, so Gemma picks sentences it never read; (b) the
first-sentence-first order plus the 40 cap drops mid-entry sentences; (c) the optional second quote is filled
almost always, like the old tip slot; (d) the pool has no relevance floor, so the model chooses among mostly
unrelated sentences.

## Data (all synthetic; no real journal text)

`build_pool.py` → `out/pool.jsonl`. The 69 English targets of `../retrieval/cases/targets.tsv` (same gold labels as
the retrieval round), each wrapped in 0–2 neutral filler sentences before and 1–3 after (seeded), so the sentence
that answers is not always first; plus 220 filler entries of 4–7 neutral sentences from `build_corpus.FILLER_EN`.
Entries spread over 180 days. 289 entries, mean 243 chars, so 18 entries overflow the 3,800-char prompt as long
real entries do.

Queries (`cases/queries.tsv`): the 38 English retrieval questions with their gold, plus 8 short ones in the shape of
the report, gold copied from the matching paraphrase question: "Health?", "Work", "Sleep?", "Money", "My dog",
"Exercise", "Getting fit", "Family".

**Gold is sentence-level**: a shown quote is RELEVANT when it is a substring of a gold target's *original* text
(the wrap sentences never are). Exception, `cases/gold_sentences.tsv`: ex6 is a long day where only the bike-ride
sentence is exercise, so only that sentence is gold for it. A blind spot-check of non-gold quotes (below) catches label gaps.

**Moods**: the pool has none, so lean routing never fires. Lean questions (any word in `askHardLeanWords` /
`askGoodLeanWords`: p6, p9, a1, a2, a3, a5, a6; p9 "enjoyed" was missed in the first draft and added
before any score was read) are reported separately and **excluded from the decision set**.

## Inputs, dumped from the app (never hand-built)

`GroundingSampleHarness.test_dumpGemmaAskPicksForRig` (sim, `forceGemmaForTesting`): EmbeddingGemma installed from
`mirror/LocalModels`, index refreshed over the whole pool, and the dump **asserts semantic retrieval ran** for every
question (search returned ids). Per question it writes the Gemma plan's own user message and grammar (the grammar
path sends no system prompt), the retrieved order, and every quotable sentence of the 18 entries with: its option
string as the app formats it, whether it is in S0's 40 options, whether it appears verbatim in the prompt, a lexical
score (distinct `askTerms(for:)` stems it contains) and a semantic score (EmbeddingGemma dot product, query prefix
vs document prefix, as Smart Search scores entries). It also records whether `NLEmbedding.wordEmbedding(for:
.english)` exists in the sim (if not, the lexical score is stems only and that is noted).

A second dump with Smart Search off (keyword retrieval) checks the fallback path.

## Variants

The prompt is S0's in every model variant; only the set of options in the grammar changes.

- **S0**: shipped grammar as dumped.
- **V1 seen**: every pool sentence that appears verbatim in the prompt (no 40 cap), shipped order.
- **V2 lex8**: V1 ranked by lexical score (ties: V1 order), top 8.
- **V3 sem8**: V1 ranked by semantic score, top 8.
- **B1 / B2 (no model)**: the top 1 / top 2 sentences of all pool sentences by semantic score, shown directly.
  **B1L**: top 1 by lexical score.
- **Gate (offline, no new runs)**: applied to S0, V1, V2, V3 outputs: keep a second quote only if it is in the top 3 of
  that variant's options by semantic score (lexical for V2).

Model runs: `rig gengrammar` on the templated user-only prompt, temperature 0.45 and max 1000 chars (`.ask`), N = 5
per question (seeds 1001–1005). Each output goes through the same check as `validateGroundedAsk` (prefix, 1–2
options, a repeated quote dropped).

## Metrics (per variant; decision set = 39 non-lean questions)

- **PREC**: relevant shown quotes / shown quotes. (The owner's complaint.)
- **HIT**: answers with at least one relevant quote / answers.
- **FIRST**: answers whose first quote is relevant.
- **TWO**: answers with two quotes.
- **UNSEEN**: shown quotes not in the prompt / shown quotes.
- **CEIL**: questions whose option set contains any gold sentence.

## Ship bar (semantic retrieval, decision set)

A variant ships only if PREC ≥ S0's + 15 points, HIT ≥ S0's − 3 points, and UNSEEN = 0. Among those, the highest
PREC wins. A no-model baseline wins only if it is ≥ the best model variant on both PREC and HIT (then Gemma adds
nothing). The gate is adopted on the winner if it adds ≥ 5 points PREC and costs ≤ 1 point HIT.

Keyword fallback (Smart Search off, decision set): the winner's non-semantic form (V2 for V3, the lexical gate for
the semantic one) must not be below S0 by more than 3 points on PREC or HIT.

Spot-check: 40 random non-gold shown quotes from the winner and 40 from S0, shuffled together with only the
question and the quote shown, labelled "answers the question / doesn't". Reported as the label-gap rate.

No bar met → owner, with the numbers.

Not measured here, before shipping a semantic variant: its latency and memory on an iPhone 13 (EmbeddingGemma loads
per question before Gemma).

## Result, Smart Search on (2026-10-23, 46 questions x 5 runs x 4 model variants; PAUSED before the keyword check)

Decision set (39 non-lean questions), semantic retrieval asserted for every question, English word embedding present:

| variant | PREC | HIT | FIRST | TWO | UNSEEN | CEIL |
|---|---|---|---|---|---|---|
| S0 shipped | 21% | 40% | 38% | 94% | 0% | 100% |
| S0 + gate | 36% | 38% | 38% | 8% | 0% | 100% |
| V1 seen | 22% | 39% | 36% | 96% | 0% | 100% |
| V2 lex8 | 37% | 54% | 46% | 82% | 0% | 87% |
| V3 sem8 | 37% | 62% | 51% | 83% | 0% | 100% |
| V3 + gate | 51% | 55% | 51% | 22% | 0% | 100% |
| **B1 no model, top sentence by EmbeddingGemma** | **95%** | **95%** | 95% | 0% | 0% | 100% |
| B2 no model, top 2 | 77% | 97% | 95% | 100% | 0% | 100% |
| B1L no model, top by lexical score | 51% | 51% | 51% | 0% | 0% | 100% |

Short questions (8): S0 31% / 62%, V3 41% / 75%, B1 88% / 88%. Lean questions (7, report only): S0 24% / 34%, B1 57% / 57%.

- By the bar: V2, V3, B1, B2 meet it; the best model variant is V3 (gate costs 7 points HIT > 1, not adopted); B1 is
  ≥ V3 on both PREC and HIT, so **B1 wins: Gemma's pick adds nothing over the ranker.**
- Defect (a) is real in code (S0 offers ~4 of 40 options from text the prompt cut) but Gemma never picked one (UNSEEN 0%).
  The cause is the pick itself: a gold sentence was always among S0's options (CEIL 100%), Gemma chose it 21% of the time.
- Spot-check (42 non-gold quotes, 40 S0 + 2 B1, shuffled, question + quote only): 0 answer the question (3 borderline:
  "Getting fit" → salt, "rested" → woke at 4:40 twice). S0's misses include keyword traps ("job interview" → "radio
  interview about old bridges", "sleeping" → "the cat next door was sleeping"). B1's two misses: "Family" → "Proud dog
  parent moment.", creative hobbies → flat-pack coffee table.
- The pool is easier than a real journal (filler avoids every topic by construction): expect B1 below 95% on device.

**Keyword check (Smart Search off, 2026-10-24, decision set): passes.** Retrieval is the ceiling here: a gold sentence
reaches the 18-entry pool for only 38% of questions (CEIL), 25-38% on short ones.

| variant | PREC | HIT | CEIL |
|---|---|---|---|
| S0 shipped | 8% | 13% | 38% |
| V2 lex8 | 13% | 18% | 33% |
| V3 sem8 (needs the model; reference only) | 14% | 15% | 33% |
| **B1L no model, top lexical sentence** | **23%** | **23%** | 38% |

B1's non-semantic form (B1L) is above S0 on both (bar: not more than 3 points below), and also ≥ V2 on both, so Gemma's
pick adds nothing on this path either. Short questions: S0 0% / 0%, B1L 12% / 12%: without Smart Search a one-word
question mostly can't be answered, whoever picks. The lever there is getting Smart Search installed, not the picker.

**Still open before anything ships:**
(1) done (above). (2) ~~B1 latency~~ measured 2026-10-24 on the iPhone 14 Pro (A16; the iPhone 13's A15 will be somewhat slower, not measured): query + 43–54 sentence embeddings = 0.75–1.0 s per question (10 synthetic questions, 2 rounds); EmbeddingGemma load 6.3 s cold (fresh install), 0.2 s warm; peak footprint +105 MB. Shipped Smart Search already loads the embedder for every question, so B1 adds the sentence pass and removes the Gemma run. Throwaway probe in a `prepare_search_device.py` copy, deleted after; numbers in the outputs folder. (3) A second quote for B1 needs
its own round (B2 always-two drops PREC to 77%). **Post-hoc sweep (2026-10-24, no model runs, same 39 questions, so tuned
on the data it is scored on, not a ship result):** second sentence only when it is within δ of the top score: δ 0.01
90% / 95% / 8% (PREC / HIT / TWO), 0.02 87 / 97 / 18, 0.03 84 / 97 / 44, 0.05 84 / 97 / 62. Only when its own score is
≥ floor: 0.40 89 / 95 / 41, **0.45 96 / 95 / 21**, 0.50 95 / 95 / 10. Gaps overlap (second gold: 0–0.095; not gold:
0.009–0.238), so a gap rule can't separate them; an absolute floor near 0.45 is the candidate for a held-out round. Outputs: `~/mirror-rig-outputs/ask-picks-2026-10-23/` (synthetic only).
Goes to the owner.
