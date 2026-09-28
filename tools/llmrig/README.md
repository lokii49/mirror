# llmrig — off-device Gemma test rig

Runs the app's exact Gemma 3 1B path on a Mac, at Metal speed: same GGUF, and it builds against the
app's own vendored `Packages/SwiftLlama` (patched swift-llama-cpp + llama.cpp b6102), with a
generation loop that mirrors the patched `Llama.processPrompt`. Built 2026-09-26 to find the root
cause of fabricated daily reflections. The simulator path works too, but at ~25s per generation it
can't run the N≥10-per-variant comparisons prompt work needs.

```sh
swift build -c release
export MODEL=../../mirror/LocalModels/gemma-3-1b-it-Q4_K_M.gguf

# Token-level sanity check of the chat template (BOS once, <start_of_turn>=105 / <end_of_turn>=106
# as single special tokens, system merged into the user turn, ends with "<start_of_turn>model\n").
.build/release/rig integrity system.txt user.txt

.build/release/rig template system.txt user.txt > p.prompt   # app-identical templated prompt
.build/release/rig gen p.prompt 0.45 10                       # N raw generations
.build/release/rig gengrammar p.prompt g.gbnf 0.45 10         # same, GBNF-constrained
```

Get prompts byte-identical to the app's with `GroundingSampleHarness.test_dumpNudgePromptsForRig`
(`TEST_RUNNER_HARNESS_DUMP_DIR=<dir>`), which captures the final system/user strings — attempt 1
and both retry attempts — through `LocalLLMService.generateInterceptForTesting` without running a
model. Never paste real journal text into rig inputs; the harness cases are synthetic.

## Findings (2026-09-26) — scored with RUBRIC.md, written before any run

4 synthetic cases (sick day, lunch/job offer, work stress, lake walk), N=10 each, temp 0.45.

| Variant | Pass | What failed |
|---|---|---|
| Token/template integrity | clean | — (not the cause) |
| Production `DAILY_NUDGE_SYSTEM`, 3 recent entries | ~0/40 | Invented sensory opener nearly every time: "The rain outside…" (sick day 20/20), "The scent of sandalwood…", "The chipped ceramic mug…", "Bruno's laughter" (Bruno is a dog) |
| Same, contradictory English language line removed | ~0/40 | Same |
| Faithful rules after entries, 3 entries | poor | Blends yesterday's entries into today ("curled up with Dev… working from home") |
| Faithful rules, today's entry only | ~55–65% | People swapped (Karan/Dev), offer→"accepted", nervous→"excitedly", "despite the overcast sky" |
| Same at temp 0.2 | worse | Locks into one error (Karan swap 6/10) |
| "Quote them word for word" by instruction only | fails | Model puts invented text inside the quotes, or copies the whole entry |
| **GBNF: quote ∈ entry's own sentences, then `That sounds`/`You seem` + optional `Maybe`/`Try`, no capitals (no names) after the quote** | **~39/40** | One soft misattribution of excitement |

Root cause: the creative "warm, open with a concrete image" prompt puts a 1B model in
creative-writing mode, where it invents a scene. Word-overlap guards reject most of these, which is
why Gemma users mostly saw "Couldn't confirm"; the partly-invented ones that slipped through were the
visible fabrications. Paraphrase with a 1B model always drifts on facts, so the fix is to not let it
paraphrase facts: the fact is a verbatim quote enforced by grammar, the model only writes the
feeling/suggestion line.

Foundation Models on the same sick-day case with the production prompt: 12/12 correct. The production
prompt is kept for that engine.

## Shipped version, verified (2026-09-26)

Production-built prompts + grammars (dumped by `test_dumpNudgePromptsForRig`, not hand-built) for
the 4 cases above plus 4 messy ones (unpunctuated run-on, checklist, quotes/backslash/emoji, two
entries same day): **80/80 pass `validateGroundedNudge`**, every quote verbatim and on-topic.
Strict rubric ~76/80 — misses are all in the feeling line: a to-do list read as done ("after
tackling these tasks"), one misattributed "relieved about this exciting opportunity", and one
"stubborn mood that's making you want to just disappear" (1/80).

Real app pipeline in the simulator with `HARNESS_ENGINE=gemma`, all 8 cases x 2: **16/16 real
reflections on attempt 1, 0 fallbacks**, 18–49s each on the simulator's single-thread CPU path
(the old path took ~27s per attempt x 3 and still fell back).

## Weekly digest (2026-09-27)

Baseline, `WEEKLY_DIGEST_SYSTEM` on Gemma, synthetic week: invents details in most sections ("a system
for organizing your photography workflow", "a dull ache in your shoulders", "a steaming mug of
chamomile tea"). Prototypes (DIGEST_RUBRIC fixed before running):

| Variant | Result |
|---|---|
| Quote-anchored energy/building/watch, free lowercase theme | nothing invented; same quote often reused for building + watch |
| Theme built only from the week's keywords | unusable ("A week of around, around and around") |
| + building from good-mood entries, watch from hard-mood entries | week B: "most **drained** when you wrote '<hopeful sentence>'" 10/10 |
| **+ energy adjective bound to the quote's mood bucket (shipped)** | **20/20 nothing invented** (two different synthetic weeks) |

Production-built grammar (dumped via `test_dumpOtherInsightPromptsForRig`): 20/20 pass
`validateGroundedDigest`. Real pipeline, `HARNESS_ENGINE=gemma`, both weeks x 2: 4/4 real digests,
0 fallbacks, 39–82s on the simulator CPU path. Known quality limits (not fabrication): the same hard
quote often fills both YOUR ENERGY and WATCH OUT FOR; a salient entry can be skipped (week B's grief
entry never surfaced); MOOD BOOST/NEXT WEEK are generic ("short walk in nature").

## Monthly report (2026-09-27)

Baseline on Gemma: opens "Okay, here's a deep monthly reflection…" and invents specifics ("During a
conversation with Bruno, I realized…"). Prototypes on a 10-entry synthetic month, N=10:

| Variant | Result |
|---|---|
| Quoted moment/becoming/release + char-level free text | nothing invented, but free text garbles ("stability and adventure uring the unknown", "A swirling nebula  nebula.") and "How can **i**…" in 4/10 questions |
| Word-level free text, "you"-led question openers | garble persisted in the forced "X and Y" tension |
| **"You seem pulled between <phrase>" tension (shipped)** | **10/10 well-formed, nothing invented, moment dates match their quotes** |

Production-built grammar: 10/10 on the rig; real pipeline with Gemma forced 2/2, 54–67s. One real-run
output quoted a grief entry under "Maybe it's time to let go of…" — Sad/Numb entries are now excluded
from that section (still quotable as a moment). Images/tensions are generic ("A solitary lighthouse
against a stormy sea", "pulled between responsibility and freedom") — metaphors, not claims.

## Other languages (2026-09-27)

Baseline: the shared prompts on Gemma invent scenes in every language tried, same as English
("Der Duft von frisch gemähtem Gras…", "El sol se filtraba a través de las persianas…",
"夕焼けが空を染めて…"). The English grammar (free lowercase line after the quote) doesn't carry
over: German capitalises nouns ("unruhigenabend"), and a Japanese grammar with a negated character
class was silently dropped by the sampler.

Shipped: outside English, Gemma only picks sentence(s) from a grammar of literal sentences; the app
composes fixed, translated text around them by mood (`groundedLocales`). Prompt layout matters —
instruction first, then the entry, with the mood named in the instruction: Spanish went from quoting
the last sentence 6/6 to the main event 6/6. Production-built prompts, 5 runs each: 7/9 languages
quote the main event 5/5; ja/zh quote "woke at 10, much later than usual" (true, relevant).
Digest picks valid in all 9. Real pipeline (de/ja/zh nudge + digest, Gemma forced): 6/6 real
outputs, 4–15s on the simulator. The word-overlap guards are skipped for grammar-verified output —
they rejected a verified Japanese nudge 3/3 (no spaces to split words on).

## Ask "you haven't written about this" (2026-09-27) — removed on Gemma

The deterministic no-answer shortcut (question words + stems + word-embedding neighbours, none found
in the entries) was measured on paraphrased, answerable questions and said "not written about" when
the answer was there: English 3/10 ("Do I exercise?" over a gym entry, "How are my finances?" over a
rent/budget entry, "What was my mood like?"), Italian 2/11 ("Faccio sport?" over a *palestra* entry,
"Com'era il mio umore?"). Most languages have no word embedding on device at all (the simulator had
none; the Mac only Italian). Gemma itself took a grammar-offered no-answer 24/24 even for answerable
questions. So Gemma's Ask always answers with the closest sentences under "The closest things you've
written:" (and localized equivalents); the no-answer phrase is used only when nothing is quotable.
Mood routing (worry questions → hard-mood entries, happy → good-mood) stays in every language.

## Follow-up chip + Talk It Out (2026-09-27) — baseline, not yet changed

Both still run the shared free-prose prompt on Gemma (`FOLLOW_UP_SYSTEM` / `GUIDED_ENTRY_SYSTEM`,
`GemmaPlan.samePrompt`). Prompts dumped from the app with
`GroundingSampleHarness.test_dumpFollowUpPromptsForRig`, templated with `rig template`, run with
`rig gen <prompt> 0.5 10 140` (the app's `.followUp` temperature and 140-char cap). Scored with the
follow-up section of RUBRIC.md, written before the first run in the same session (not committed
first). All 160 outputs pass the validator's shape rules (checked with an approximation of
`validateFollowUp`), so every one would be shown.

| Case | Pass | Failures |
|---|---|---|
| fu_sickday | 8/10 | quotes "comfort", which the draft never says (2) |
| fu_offer | 9/10 | asks what *Priya* is excited about; 9/10 assume "excites you" though the writer is undecided |
| fu_work | 10/10 | — |
| fu_walk | 9/10 | "Bruno's posture shifted" |
| **fu_runon** (lowercase, no punctuation) | **3/10** | **"the rain" 5/10**, quotes 'lost', "solitude" |
| **fu_sickday_de** | **5/10** | **Dev "describes a feeling", Dev "meant 'rumort'" (the writer's stomach), Dev "said something about the room" (2)**, quotes 'Rumble' |
| fu_offer_de | 10/10 | grammar slips only |
| fu_sickday_es | 10/10 | one generic "what music do you like" |
| fu_offer_es | 9/10 | addresses the writer as "Priya" |
| **Follow-up total** | **73/90 (81%)** | below the 95% bar; ~86% even dropping every invented-quote and borderline call |
| gq_tired / gq_quilt / gq_raise / gq_sister_de | 40/40 | often ignore the answer ("one small thing that brought joy" after "tired") |
| gq_sister | 9/10 | "remember about Berlin" (the sister is moving, not the writer) |
| gq_runon | 10/10 | all generic "one small joy today" after "ugh so tired" |
| gq_plan3 | 8/10 | "remember from that trip" (planned for December) (2) |
| **Talk It Out total** | **67/70 (96%) strict** | passes narrowly; every miss is the same "remember from a move/trip that hasn't happened" shape |

The follow-up chip fails where the old nudge failed: unpunctuated text (the rain again) and other
people being given the writer's words or actions (German). Talk It Out's generated questions
mostly don't reference the conversation at all, which is why they rarely invent — a quality
problem, not a fabrication one. No ja/zh follow-up case: `strippedWordCount` splits on whitespace,
so CJK drafts never reach the chip's 20-word gate.

## Follow-up prototype (a): Gemma picks a phrase, the app composes the question (2026-09-27)

Rig-only, no app change. `test_dumpFollowUpPrototypeForRig` builds candidates from the nudge's own
`groundedNudgeQuoteCandidates`, merged or cut into verbatim clause runs of <= 100 chars (so e.g.
`What's underneath "<phrase>"?` stays under validateFollowUp's 160). The prompt goes in as a
user-only message with a literal grammar of those phrases, at temp 0.5, N=10. Scored with the
prototype section of RUBRIC.md: did it pick the writer's feeling, worry, decision or a key event,
not scenery or logistics.

The grammar held for every one of the 380+ picks: always an exact phrase from the draft, so
**nothing can be invented.** The problem is *which* phrase. Picks are near-deterministic (usually
10/10 the same), so each case is about one real sample: 11 English drafts, 4 German, 4 Spanish.
None of these was validated on held-out cases.

| Instruction / layout | English (11) | German (4) | Spanish (4) |
|---|---|---|---|
| A: "the most important thing of the day" (= shipped `pickNeutral` for de/es) | 80/110 (73%): walk, scene-first, mid 0/10 | 30/40 | 10/40 |
| **B: "the part they'd most want to say more about: a feeling, a worry, or something that happened to them"** | **100/110 (91%)**: mid 0/10 ("Made pasta for dinner" over the Jonas argument) | 30/40 | 28/40 |
| BC: B with the instruction after the entry | 80/110 | 29/40 | 26/40 |
| BD: B + the parts as a numbered list | 100/110 (91%): walk 0/10 (the gold light) | 20/40 | 12/40 |

**What fails:**
- **Scenery at the start.** The scene-first draft picks "the sky was pink…" in German and Spanish under every variant.
- **Position over meaning.** The model follows where a phrase sits more than what it says, e.g. the last sentence, "Made pasta for dinner".
- **Too few candidates.** When a draft yields only one or two, the pick is forced.

Against the bar fixed before the run (>= 85% and no case below 7/10), **no variant qualifies**.

A wrong pick here is a dull question, e.g. `What's underneath "Made pasta for dinner"?`, not an
invented one. By comparison, the shipped free-prose chip scored 73/90: 17 of 90 questions
invented or misattributed something.

Two design choices were settled here: no "drop the unfinished last piece" rule (it dropped the
most salient part in 3 of 11 unpunctuated drafts), and clause runs are merged, not split at every
comma (German subordinate clauses became fragments like "wenn ich will").

### Held-out round and baselines (2026-09-28)

Rounds 1-3 drafts mostly ended on the feeling, and on them "always take the last candidate" scored
as well as Gemma. So 10 fresh drafts (6 en, 2 de, 2 es) put the salient part first or mid-draft;
SALIENT lists were added to RUBRIC.md before running. The shipped free-prose chip was also run on
all 20 drafts added since the baseline, so the two designs are compared on the same inputs.

| Picker | Held-out en (6) | Held-out de+es (4) | All en (17) | All de (6) / es (6) |
|---|---|---|---|---|
| **Gemma, BD wording + numbered parts** | **50/60** (newsfirst 0/10: "errands and a long nap") | de 10/20, es 18/20 | **150/170 (88%)**; walk and newsfirst 0/10 | 30/60, 30/60 |
| Gemma, B wording | 33/60 (biopsy draft → "Made pasta…") | de 10/20, es 10/20 | 133/170 (78%) | LB 40/60, 38/60 |
| Rule: always first candidate | 3/6 | 2/4 | 10/17 drafts | — |
| Rule: always last candidate | 1/6 | 0/4 | 11/17 drafts | — |

On held-out drafts the model beats both rules in English, so the pick carries real signal. No
variant meets the adopt bar in any language. German and Spanish pick scenery or logistics
("coffee with Lena", "the sky was pink") on roughly a third to a half of drafts.

The shipped free-prose chip on those 20 drafts: English 108/120, de/es 59/80. Examples:
- "your son" and "a shade of blue" on the biopsy draft;
- "the rain" on the fight draft;
- a quoted "sunshine" in Nani's recipe;
- the writer's disillusionment blamed on "Tom's snacks" (5/10);
- Sam reacting to the song (de, 7/10);
- Priti "angry", "worried", "horror in her eyes" (de).

**Invented or misattributed across all 29 drafts:** 50/290 (17%).
- English: 23/170 (14%).
- German and Spanish: 27/120 (22%).

**What the composed question looks like** (`What's underneath "…"?`, Gemma BD pick):
- `What's underneath "Dad's biopsy results come back Friday and I can't stop thinking about it"?`
- `What's underneath "I feel so behind, and I snapped at Omar in standup for no reason"?`
- `What's underneath "The rest of the day was errands and a long nap"?` (a dull pick)
- `What's underneath "He took it better than I expected"?` ("He" has nothing to refer to)
- `What's underneath "and ben said hes being bullied at school again i dont know what to do then made dinner and bedtime"?`
  Starts with a conjunction, which can be stripped and still leave a verbatim substring. Too long for a chip.

Spanish candidates keep an opening "¡" or "¿" without the closing mark; strip them when composing.

### Same metric for both designs (2026-09-28)

The shipped chip was first scored only for invention and the prototype only for salience. To
compare like with like, the prototype's SALIENT lists (fixed before any run) were applied
afterwards to the shipped chip's 290 outputs: **salient AND nothing invented**.

| Design | English | German + Spanish |
|---|---|---|
| Shipped free-prose chip | 107/170 (63%) | 56/120 (47%) |
| (a) Gemma picks, app composes (best variant per language) | 150/170 (88%) | 78/120 (65%) |

The shipped chip is often dull as well as sometimes wrong. The biopsy drafts get questions about
river and pasta colours (1/20 mention the biopsy). The scene-first drafts get questions about the
song. The walk draft gets questions about the gold light. Spanish drafts get questions about
coffee types and errands. So (a) beats it on both counts; it is not a trade of dull for safe.

It also prints a literal slash in 18/290 outputs ("felt most hurtful to you/your?", "your/your",
"tu/tu", "deinem/deinem"), echoing `FOLLOW_UP_SYSTEM`'s `Address them as "you/your"`.
`validateFollowUp` doesn't catch it.

**Limits:**
- Salience calls ("vague" vs specific) are one scorer's judgement.
- The best de/es wording differs between rounds on only 6 drafts per language, so that choice is noise.
- Only de and es were measured of the 9 non-English languages. fr/it/pt/ru/ko are extrapolation; ja/zh never trigger the chip (word count).
- All of this is the Gemma path; the Foundation Models chip is unmeasured.

### French and Russian check (2026-09-28): (a) ships there too

The same six drafts de/es were scored on, translated. The rubric and decision rule were added to
RUBRIC.md before running.

| | French | Russian |
|---|---|---|
| (a) numbered parts (LBD) | **58/60** | **49/60** (news draft → "errands and a long nap" 0/10) |
| (a) no list (LB) | 22/60 | 39/60 |
| Shipped chip, salient AND nothing invented | 28/60 | 30/60 |

- **Layout.** The numbered-parts layout is better across all four non-English languages: 167/240 vs 139/240 without the list. It is also English's best (BD), so **(a) uses one layout everywhere**: entry, numbered parts, then the instruction.
- **Shipped chip in French and Russian.** It invents feelings and scenes ("sentiment de vide", "le soleil sur le balcon", "Марко отвернулся") and asks about Lena instead of the fight. It says vous/вы in most outputs, and uses a feminine "говорила" for a writer who wrote in the masculine.
- **Register.** (a)'s question is fixed text, so it says tu/ты by construction.

### Shipped (2026-09-28)

`InsightService.groundedFollowUpPlan` uses the numbered-parts layout in every grounded language.
- **Candidates:** production `followUpPhraseCandidates` (the harness logic, plus CJK clause cuts), last 12 parts.
- **Composed question:** one of two fixed templates per language, with a leading conjunction or ¡/¿ stripped.
- **Other languages:** outside the 10 grounded languages, the chip doesn't appear on Gemma.

Real pipeline in the simulator (`test_followUp_fullPipeline`, `HARNESS_ENGINE=gemma`, 8 drafts in en/de/es/fr/ru, x2): **16/16 composed questions**, 4-7s each. Picks matched the rig, including the known dull one (fu_walk → the gold light).
