# Ask retrieval: keyword vs Apple embeddings vs EmbeddingGemma

Off-device measurement of which entries reach the Ask prompt. Method, metrics and decision bar are in
`RUBRIC.md`, written before any run. All entries and questions are synthetic.

```sh
python3 build_corpus.py 2          # out/cap2/: English + a few other-language entries, 88 targets + 0/150/400 filler
python3 build_corpus.py            # out/: same with uncapped keyword traps (stress test)
python3 build_corpus.py --lang de  # out/de/: monolingual, 31 targets + 0/150/300 filler (also es, fr, ja)
python3 build_corpus.py --lang de impersonal   # out/de-impersonal/: same, first round's impersonal filler

D=out/cap2; C=$D/corpus_400.jsonl; Q=cases/queries.tsv   # monolingual: C=out/de/corpus_300.jsonl Q=out/de/queries.tsv
swift nl_embed.swift $C $Q $D/nl_vectors.json            # Apple NLEmbedding + NLContextualEmbedding
python3 -I eg_embed.py $C $Q $D/eg_vectors.json          # EmbeddingGemma-2 fp32 (venv outside the repo: torch,
                                                         #   sentence-transformers>=6.1, transformers>=5, pillow, torchvision)
python3 gguf_embed.py <llama-server> eg1-Q8_0.gguf $C $Q $D/gguf_eg1q8.json   # any GGUF via llama.cpp; picked up
                                                                              #   by score.py as system "eg1q8"
python3 score.py $D                                      # tables + $D/detail_<n>.tsv
```

GGUFs used: `ggml-org/embeddinggemma-2-GGUF` (Q8_0, 310MB), `ggml-org/embeddinggemma-300M-GGUF` (v1, Q8_0,
334MB) and `unsloth/embeddinggemma-300m-GGUF` (v1, Q4_0, 278MB). All three repos are ungated. llama.cpp was the b11496
macOS arm64 release, running `llama-server --embedding`.

## Headline (2026-10-08)

R@10 is the share of gold entries in the top 10 that Ask retrieves. Each cell is lexical / paraphrase / abstract.
The largest corpus is used for each set: 488 entries for `cap2`, 331 for each monolingual set. The de/es/fr columns use
first-person filler; impersonal filler shifts single cells (see the last section), but not the orderings.

| system | English `cap2` (13/16/9 q) | de (4/7/4) | es | fr | ja |
|---|---|---|---|---|---|
| `kw` (today's `SearchService.search`) | .62 / .07 / .03 | .17 / 0 / 0 | .33 / 0 / 0 | .67 / 0 / 0 | 0 / 0 / 0 |
| `kw-stemidf` (new `SearchService.search`, 2026-10-08) | .72 / .15 / .14 | .83 / .12 / .08 | .83 / 0 / .08 | .92 / .10 / 0 | 0 / 0 / 0 |
| `nlc` Apple `NLContextualEmbedding` | .32 / .31 / .23 | .58 / .46 / 0 | .58 / .27 / 0 | .33 / .29 / .13 | .75 / .24 / .30 |
| `eg2q8` EmbeddingGemma-2, llama.cpp Q8_0 | .90 / .65 / .42 | .83 / .54 / 0 | .92 / .69 / .38 | .83 / .74 / .31 | .92 / .77 / .17 |
| **`eg1q8` EmbeddingGemma v1 300M, Q8_0** | **.92 / .76 / .68** | **1.0 / .69 / .42** | .83 / .83 / .78 | .83 / .93 / .82 | 1.0 / .80 / .61 |
| `eg1q4` v1, Q4_0 | .90 / .76 / .66 | 1.0 / .69 / .63 | .83 / .95 / .83 | .83 / .81 / .74 | 1.0 / .85 / .87 |
| `hybidf-eg768` (EG-2 + `kw-stemidf` boost) | .77 / .58 / .42 | .92 / .39 / .08 | .83 / .69 / .46 | .92 / .43 / .08 | .92 / .77 / .17 |

1. **EmbeddingGemma v1 is the better model for this job.** Single cells are noisy (Q4 vs Q8 of the same model
   differs by up to ±0.2), so the comparison is paired per question, pooled over all five sets:

   | v1 Q8_0 vs v2 Q8_0, R@10 per question | v1 better | v2 better | tie | mean v1 / v2 |
   |---|---|---|---|---|
   | abstract (25 q), first-person filler | 19 | 1 | 5 | .67 / .29 |
   | abstract, impersonal filler | 16 | 1 | 8 | .78 / .44 |
   | paraphrase (44 q), first-person filler | 19 | 4 | 21 | .79 / .67 |
   | paraphrase, impersonal filler | 18 | 4 | 22 | .85 / .74 |
   | lexical (29 q), first-person filler | 3 | 1 | 25 | .92 / .89 |

   The biggest gap is on mood questions ("When was I happiest?", "Am I burning out?"). Against Apple `nlc`, v1 wins
   38–0 on paraphrase and 23–0 on abstract questions.
2. **Quantization costs nothing measurable, but truncation does for v1.**
   - EG-2 Q8_0 on llama.cpp matches the PyTorch fp32 vectors at mean cosine 0.9999 (min 0.9998), with identical R@10.
   - v1 Q4_0 matches v1 Q8_0 per question: paraphrase 6 better / 5 worse, abstract 7 / 2. It is only 17% smaller (278 vs 334MB),
     because the 262k-token embedding table dominates the size. The Q4_0 build tested is unsloth's (a third party), so a shipped
     model should be quantized from Google's weights.
   - **v1 truncated to 256 dims loses a lot**: paraphrase 16 better / 3 worse at 768, abstract 12 / 2, means .79 → .66 and
     .67 → .44. Keep 768 for v1 (3KB per entry in fp32, 1.5KB in fp16). EG-2's 256 truncation held up, but v1's doesn't.
3. **Apple's embeddings don't clear the bar.** `nlc` gains on paraphrase and loses on lexical in English. Outside English
   it is better than keyword search but far below either EmbeddingGemma. `NLEmbedding.sentenceEmbedding` exists
   only for English on macOS 27 and is worse than keyword search there (lexical .06).
4. **Don't mix embeddings with keywords.** Every hybrid tried scores below the same embedding alone on paraphrase and abstract
   questions. That includes the original rule (+0.15 when SearchService's rule matches) and an IDF-weighted, stemmed,
   generic-words-dropped version. Pure embeddings already score .83–1.0 on lexical questions.
5. **Keyword search alone can be improved in German and Spanish without any model.** `kw-stemidf` matches whole words via the
   app's `askStem`, weights keywords by IDF over the user's own entries, and drops keywords found in more than 25% of entries.
   Nothing in it is tuned on these questions. Lexical R@10 with each filler style (first-person / impersonal):

   | | de | es | fr | en `cap2` |
   |---|---|---|---|---|
   | `kw` | .17 / .17 | .33 / .58 | .67 / .92 | .62 |
   | `kw-stemidf` | .83 / .92 | .83 / .83 | .92 / .92 | .72 |

   - **German and Spanish:** robust to filler style. Today's search fails there because its stopword list is English, so "ich", "wie",
     "que" and "mi" match many entries and the newest ones win.
   - **French:** the gain depends on how often the journal uses "je"/"me"/"ma". Today's search already scores .92 with impersonal filler.
   - **English:** .62 → .72. Most of the gain is plurals: `searchStem` drops a trailing "e" after `askStem`, so "migraines"
     meets "migraine". Without that rule it was .64.
   - **Japanese:** both score 0, because questions have no spaces and the whole question becomes one keyword. `NLTokenizer` word
     segmentation might fix that; it wasn't tested.
   - **Implemented** as `SearchService.search` on branch 3.1.0 (uncommitted as of 2026-10-08), tested in
     `mirrorTests/SearchServiceTests.swift`.
     - It has one guard the rig never exercised: below 20 entries the 25% cutoff is off, because 2 gym entries out of 5 is 40%.
     - Questions and entries share one word split: any non-letter, non-digit separates words, both apostrophes included,
       so "Mom's", "Mom’s" and "l'entretien" match "mom" and "entretien".
     - `score.py`'s `kw-stemidf` is kept identical to the app code.

## Against the decision bar (RUBRIC.md)

- **Embeddings worth adopting at all:** only EmbeddingGemma is. Apple `nlc` regresses on English lexical (.32 vs .62).
- **EmbeddingGemma worth its size:** yes, for both versions. Compared with the best Apple system, v1 adds +.45 on English paraphrase+abstract (.73 vs .28)
  and stays at or above `kw` on lexical in every set.
- **Which one:** v1 is better on quality. On license and support:
  - v2 is Apache 2.0.
  - v1 is under the Gemma Terms of Use, the same terms as the Gemma 3 1B the app already ships.
  - v1's Google repo is gated. The ggml-org GGUF is not.

## Shipping cost

- **Runtime.** The app's vendored llama.cpp is b6102, which has no gemma-embedding architecture. Bisected with the macOS release binaries:
  - b6390 is the first release whose framework contains the architecture. b6380 doesn't.
  - b6390, b6500 and b6700 still refuse ggml-org's v1 GGUF: "wrong number of tensors; expected 316, got 314". The GGUF carries the
    dense projection layers, and those builds don't know them.
  - **b6750 is the first tested release that loads it** (b6725 and b6775 have no macOS asset). b6800 gives the same vectors as b11496
    (mean cosine 1.00000).

  So the smallest upgrade is b6102 → about b6750, not to today's release. Any upgrade still changes Gemma 3 1B generation, so every Gemma
  rig round (nudge, digest, monthly, follow-up, mood) would have to be re-run. The alternative is a separate embedding runtime
  (Core ML/ONNX conversion) next to the existing llama.cpp.
- **Size.** About 280–335MB on top of the Gemma GGUF.
- **Storage.** 768 floats per entry for v1, because 256 loses quality (see 2). Keep vectors on-device only, never in CloudKit.
- **Not measured on iPhone.** On the Mac (Metal), embedding took 1–3s for 331–488 entries including startup.

## Earlier detail (English `cap2`, first round)

| system | lexical | paraphrase | abstract |
|---|---|---|---|
| `nls` `NLEmbedding.sentenceEmbedding` | .06 | .05 | .01 |
| `nlc_sent` (max over sentences) | .33 | .23 | .19 |
| `eg768` EG-2 PyTorch fp32 | .90 | .65 | .42 |
| `eg256` EG-2, Matryoshka 256 | .90 | .68 | .39 |
| `kw-rank` (rank by keywords matched) | .64 | .07 | .03 |
| `kw-idf` (substring + IDF, generic dropped) | .68 | .07 | .03 |
| `hyb-eg768` (+0.15 if SearchService rule matches) | .83 | .58 | .42 |

How R@10 changes as the journal grows (88 → 238 → 488 entries):

| system | lexical | para+abstract |
|---|---|---|
| `kw` | .71 → .64 → .62 | .08 → .06 → .06 |
| `nlc` | .35 → .32 → .32 | .30 → .28 → .28 |
| `eg768` | .92 → .92 → .90 | .76 → .63 → .57 |

The **uncapped stress test** (`out/`) uses each keyword trap line ("carpet" ⊃ pet, "current" ⊃ rent) about 20 times. Under it,
`kw` lexical falls to .32 and the embedding-only numbers barely move.

The mixed-language questions in `cases/queries.tsv` (`nonen`) don't discriminate between systems. Each language has only 8–13 entries
there, so any language-aware model finds the gold entry (`nlc` scores 1.00). The monolingual sets replace them.
Gold is same-language only. That penalizes EmbeddingGemma's cross-lingual hits, such as German, Japanese and Spanish sleep entries
for "How have I been sleeping?".

## What it does not show

- **One author, binary gold, small per-language sets** (15 questions each). Abstract questions are subjective.
- **The label check** (`score.py`, kw / signal columns). It shows that paraphrase and abstract questions share no topic word with their gold entries.
  The few "signal" hits left in de/es/fr come from function words ("mit", "con", "por") that SearchService's English stopword list keeps.
- **Filler style moves absolute numbers.** In the first monolingual run, "ich" appeared in 10% of the filler vs 39% of the targets. That
  gives keyword search a free pronoun signal. The filler was rewritten in first person (`filler.txt`), and the first version is kept as
  `filler_impersonal.txt`. Between the two, per-language cells move by up to .4 (EG-2 German abstract .30 → 0). The orderings
  (v1 > v2 > `nlc`, with `kw-stemidf` ≥ `kw`) hold under both.
- **Not tested:** Japanese keyword search with `NLTokenizer`, it/pt/ru/ko/zh, voice-note transcripts, and real entry lengths
  (most entries here are 1–3 sentences).
