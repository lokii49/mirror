# llmrig — off-device Gemma test rig

Runs the app's exact Gemma 3 1B path (same GGUF, same llama.cpp b6102 build, same SwiftLlama
wrapper sources, same sampler chain and generation loop as `Llama.swift`) on a Mac, at Metal speed.
Built 2026-09-26 to find the root cause of fabricated daily reflections. The simulator path works
too, but at ~25s per generation it can't run the N≥10-per-variant comparisons prompt work needs.

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

Same-style prompts NOT yet fixed on Gemma (baseline, synthetic week): weekly digest and monthly
report invent details ("organizing your photography workflow", "during a conversation with Bruno,
I realized", "steaming mug of chamomile tea") and the monthly report opens with a preamble; Ask
stays on the entries but swaps some attributions. Non-English daily nudges still use the old prompt.
