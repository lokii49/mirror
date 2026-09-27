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
