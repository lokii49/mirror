# Ask retrieval with EmbeddingGemma v1: plan (2026-10-08)

Decided with the owner (2026-10-08):
1. Ship the no-model keyword fix first.
2. Upgrade the vendored llama.cpp so one runtime runs Gemma 3 1B and the embedder.
3. Download the embedding model on demand, not bundled.

Evidence: `tools/llmrig/retrieval/README.md`.

## Step 1: keyword fix (done on 3.1.0, uncommitted as of writing)

`SearchService.search` now:
- matches whole words by `searchStem` (`askStem` plus a trailing "e" dropped),
- splits questions and entries the same way (both apostrophe styles separate words),
- ranks by summed IDF, so results come back by relevance, not newest first,
- drops keywords found in more than 25% of entries, from 20 entries up.

No caller assumes newest first: the Ask prompt labels the block "Most relevant entries" and dates each entry, and the
"How this was generated" reading list shows the top 3.
- Rig lexical R@10: de .17→.83, es .33→.83, en .62→.72. Japanese is unchanged at 0 (no spaces).
- Tests: `mirrorTests/SearchServiceTests.swift` (14, incl. apostrophes/elision and 2,000 entries under 1s).
- Full mirrorTests: first run 711 passed / 0 failed / 27 skipped. A later run had 4 failures, all in `BrainViewTests` (NLTagger
  noun tagging), which don't touch search, and they pass on re-run.

## Step 2 spike results (llama.cpp b6102 → b6750, Mac, scratchpad copy, repo untouched)

- **Builds as-is.** SwiftLlama with all 6 mirror patches and tools/llmrig compile against b6750 with no source change.
  The only diff is in `Package.swift`: `llamaVersion = "b6750"`,
  `llamaChecksum = "769478a7997c5bc67f5f10c4593e35b6278e4b6b70279f11ddf4f40d6e85a94f"`.
  b6750 is the first tested release that loads ggml-org's v1 GGUF. b6700 and earlier fail with "expected 316 tensors, got 314" (the dense layers).
- **Gemma 3 1B gives identical short unconstrained outputs.** `rig integrity` is clean. On the mood prompt, 40 cases × 3 seeds gave 120/120
  byte-identical one-word labels (60-character cap). Longer free prose wasn't compared.
- **Gemma 3 1B drifts under grammar.** Production prompts and grammars (`GroundingSampleHarness.test_dumpNudgePromptsForRig` + `test_dumpOtherInsightPromptsForRig`),
  5 seeds each: 19/85 identical, 66 different. The verbatim quote is always identical, because the grammar forces it. What differs is the
  model-written feeling or theme words, e.g. "You seem incredibly happy and relaxed." vs "You seem incredibly excited and happy…".
  **So every Gemma rig round must be re-run before shipping:** daily nudge en + 9 langs, digest, monthly, follow-up chip, mood, Ask.
- **The embedder works from Swift.** v1 Q8_0 through the raw C API, 538 texts in 3.6s on the Mac, matches `llama-server`
  at mean cosine 1.00000 (min 1.00000). The code that did it:
  ```swift
  var cp = llama_context_default_params()
  cp.n_ctx = 2048; cp.n_batch = 2048; cp.n_ubatch = 2048   // non-causal: whole text in one ubatch
  cp.embeddings = true
  let ctx = llama_init_from_model(model, cp)!
  // per text: tokenize with add_special = true; batch with pos 0..<n, seq_id 0, logits 1 for all
  llama_memory_clear(llama_get_memory(ctx), true)
  llama_decode(ctx, batch)                                  // gemma-embedding has no encoder
  let p = llama_get_embeddings_seq(ctx, 0)!                 // mean-pooled + dense, llama_model_n_embd = 768
  // L2-normalize. Prompts: "task: search result | query: " / "title: none | text: "
  ```

## Step 2 gate: Gemma rig rounds on b6750 (2026-10-08, partial)

Same GGUF, prompts and seeds on b6102 vs b6750 (spike copy of SwiftLlama + rig):
- **Mood detection (`mood/run.py`, cases + cases_hard, 3 seeds): byte-identical on both builds.**
  en 72% exact / 100% bucket, de 67%, es 83%, hard set 58% / 100% bucket, 0 missed hard.
- **Grammar paths, English** (production prompts from `test_dumpNudgePromptsForRig` + `test_dumpOtherInsightPromptsForRig`:
  12 nudge cases, digest ×2, monthly, Ask; `gengrammar` temp 0.45, N=10 per build, 340 outputs):
  - Quotes are verbatim on every output of both builds. The Ask output is identical on both.
  - The feeling and theme lines resample within the same phrase families. Example: work, "exhausted and (a little) frustrated with the
    constant rescheduling / current workload" on both.
  - **No new failure mode on b6750** under the RUBRIC.md nudge rules. Every apparent invention checked against the entries was grounded:
    - rl_good "new opportunity": the entry is an offer letter.
    - sameday "after the argument": a same-day entry has one.
    - digestB "new role": the entry is a new job.
  - The known soft misattribution (lunch: the writer "happy with the prospect of a change" about Priya's offer) is equally frequent
    on both builds.
  - One scorer, not blind to build.
- **Follow-up chip** (`test_dumpFollowUpPromptsForRig`, fixed to dump the grammar plan): 50 cases (en, de, es, fr, ru; fu_* + hx_*), N=10.
  **Byte-identical on both builds, 500/500.**
- **Localized nudge / digest / monthly** (`test_dumpLocalizedPromptsForRig`, 9 languages × 3), N=10. Nudges are identical in all 9 languages.
  Digests and monthlies are identical in de, ja, pt, ru, zh. es/fr/it/ko differ only in which of the same 2–3 entry sentences
  is picked, and in what order:
  - fr_monthly repeated-sentence picks: 2 on b6102, 3 on b6750.
  - fr_digest: b6102 has 1 output with a repeated sentence, b6750 none.
- **Talk It Out** (free prose, `gq_*`, temp 0.5, N=10 × 7 cases), strict RUBRIC follow-up rules: **b6102 65/70, b6750 64/70**.
  The shipped measurement was 67/70. Every failure on both builds is the known shape: a trip or move that hasn't happened yet is treated as done.
  - plan3: "remember from that trip", "about Kochi".
  - sister: "remember about Berlin / her move".
  - b6750 also has sister_de "deine neue Umgebung" ×2 (the move attributed to the writer) and "grandma's absence" ×1.
  - b6102 also has sister "her new life" and "her move".
  - One scorer, not blind to build.
- **Verdict: b6750 passes the rig gate.** Mood and follow-up are identical. The grammar paths resample the same distributions.
  Talk It Out stays at the same failure rate and type.

## Step 2 build order (branch off 3.1.0 once step 1 is committed)

1. **SwiftLlama → b6750.** Add an embedding API (`LlamaEmbedder`, the code above) as mirror patch 7 in `PATCHES.md`.
   Never log the text or tokens. Grammars and entries are journal text, as with patch 1.
2. **Re-run the Gemma rig rounds** on b6750 with the existing RUBRICs. Ship only if each is at least as good as on b6102.
3. **Model delivery.** Download on demand from a pinned URL with a SHA-256 check. The file is v1 Q8_0, 334MB.
   Open decisions:
   - Host: the ggml-org HF file directly, or our own static host. A direct HF fetch shows the user's IP to HF but sends no journal data.
   - Gate: download for everyone, or only when Ask is used.
   - License: Gemma Terms notice in the app, same as for Gemma 3 1B.
   - Quantization: quantize from Google's own weights if not using the ggml-org file. The Q4_0 tested was unsloth's.
4. **Vector index.** On device only: no CloudKit, and no new SwiftData model synced to CloudKit (memory: no schema changes unless asked).
   - Store a file in Application Support with complete file protection. Vectors leak content, so treat them like entry text.
   - Key each vector by entry id + text hash. Re-embed on edit, and backfill in a BGProcessingTask.
   - 768 fp32 (3KB) or fp16 per entry. v1 truncated to 256 loses quality.
5. **Ask.** When the model and index are ready, `SearchService.search` → embedding top 10. Otherwise use the keyword path from step 1.
   No hybrid: every mix measured worse. `InsightSignalSource` (.askResponse) has to call the same function, so
   "How this was generated" stays truthful.
6. **Memory.** Never hold Gemma and the embedder at once. Embed at entry save or in a background pass, and load Gemma only to write.
7. **Measure on iPhone** before release: embedding speed per entry, peak memory, backfill time for 1,000 entries.

## Device results, iPhone 14 Pro (2026-10-08, branch `ask-embeddings`, devtest bundle id)

- **LlamaEmbedder, v1 Q8_0 on b6750.** Load 0.5s. 24ms per ~60-word entry. A 5,400-char entry takes 0.4s. Footprint 57 → 165MB after load
  (170MB peak). 1,000 entries ≈ 24s.
- **SemanticSearchService end to end.** Install, then backfill of 301 entries in 5.8s, then search (load + query + rank) in 0.28s.
  The right entry ranks first. Footprint 135MB.
- **Gemma 3 1B on b6750, real generation on the device GPU** (`LlamaBatchBoundaryTests`): passes.
- **Bug found and fixed on the device.** `refresh()` re-checked a finished backfill task before it was cleared and recursed without end.
  iOS killed the app with SIGKILL and no crash report. Now the task clears `backfillTask` itself, and callers wait in a loop.
  A probe on a Swift concurrency thread vs an 8MB-stack thread showed both are fine, so the stack wasn't the cause.
- **Simulator full suite on the branch:** 708 passed, 4 failed. The failures are the known NLTagger flakes in BrainViewTests.

## Hosting (owner, 2026-10-08)

The owner will host the model at `https://models.mirrornotes.org/embeddinggemma/embeddinggemma-300M-Q8_0.gguf`.
It must be byte-identical to ggml-org's file: 333,590,944 bytes,
SHA-256 `b5ce9d77a3fc4b3b39ccb5643c36777911cc4eb46a66962eadfa3f5f60490d63`. Until then, every download fails its check and Ask
stays on keyword search.
