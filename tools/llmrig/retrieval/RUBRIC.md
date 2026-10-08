# Ask retrieval rubric (written 2026-10-08, before any run)

Question: would an embedding model find better entries for Ask than `SearchService.search`, and is
EmbeddingGemma-2 worth ~200MB more than Apple's built-in embeddings?

Only retrieval is measured here: which entries reach the Ask prompt. No model writes anything.

## What Ask sees

`InsightService.ask` sorts readable entries newest first. Then `SearchService.search(limit: 10)`
returns the first 10 entries, newest first, whose `insightContext` or tags contain any query
keyword as a substring. If none match, it returns the 10 newest. The 8 newest entries that weren't
retrieved are added as background. The model sees those **18 entries**.

## Data

All synthetic. No real journal text (see the memory rule). Same files for every system.

- `cases/targets.tsv`: hand-written entries that answer at least one question. There are also
  some non-English entries, and some that are distractors only.
- `build_corpus.py`: adds deterministic filler entries from neutral, everyday sentence pools.
  Some filler contains trap words that match the keyword search on a substring but are irrelevant:
  "home**work**", "**ran** errands", "the cat **sleep**s", "**book**ed a haircut", "the bus didn't **move**".
  Dates are seeded over 180 days. There are three corpus sizes: targets only, +150 filler and +400 filler.
  Each smaller corpus is a subset of the larger one.
- `cases/queries.tsv`: each question with its class, its language and its gold entry ids. Gold means
  every target entry a person would want shown for that question, **in the question's language only**.
  Filler is never gold, and that is checked by construction (the filler pools avoid every question topic).

Question classes:
- `lexical`: the question shares a content word with its gold entries. Keyword search should do well here.
- `paraphrase`: the same topic in different words ("Have I been working out?" over gym, 5k and yoga entries).
- `abstract`: a mood or theme question ("When was I happiest?").
- `nonen`: non-English (de, es, fr, ja, pt). Both lexical and paraphrase questions appear. Japanese has no spaces, so
  the keyword search treats the whole question as one keyword.

`score.py` prints the content-word overlap between each question and its gold entries, using
SearchService's own keyword extraction. A paraphrase question with high overlap is a labeling error.
Fix the label, not the result.

## Systems

| id | what |
|---|---|
| `kw` | Exact port of `SearchService.search`: same stopwords, splitting, `count > 2`, substring match on context and tags, newest first, newest-10 fallback |
| `nls` | `NLEmbedding.sentenceEmbedding(for:)` in the entry's language when one exists. Entries in other languages get no score and rank last |
| `nlc` | `NLContextualEmbedding` per script, mean-pooled token vectors. Two variants: whole entry, and max over sentences (for long entries) |
| `eg768` | EmbeddingGemma-2, fp32 on CPU, query prompt `task: search result \| query: `, document prompt `title: none \| text: ` |
| `eg256` | The same vectors truncated to 256 dimensions and re-normalized (Matryoshka) |
| `hyb-*` | Embedding cosine + 0.15 if `kw`'s keyword rule matches the entry. This tests whether embeddings rescue the keyword misses without losing its hits |

All embedding systems rank by cosine similarity and take the top 10. The 8 background entries are
then added the way the app adds them.

## Metrics (per question, then averaged)

- **R@10**: the share of gold entries in the top 10. This is the primary metric.
- **R@pool**: the share of gold entries anywhere in the 18 entries Ask sees.
- **MRR**: reported for interest only. `kw` orders by date, not relevance, so MRR isn't a fair basis for comparing it.

Results are reported by class and language at each corpus size. The headline is the 400-filler corpus.

## Decision bar (fixed before running)

- **Embeddings are worth adopting at all** if the best on-device-free system (`nls`, `nlc` or a hybrid of
  them) raises R@10 on paraphrase + abstract by **≥ 0.15** over `kw` at 400 filler, and loses **≤ 0.05** on lexical.
- **EmbeddingGemma-2 is worth its size** only if `eg*` or its hybrid beats the best Apple system by
  **≥ 0.10 R@10** on paraphrase + abstract + nonen at 400 filler, with no lexical loss beyond 0.05.
  If it doesn't, Apple's embeddings win because they cost nothing in app size.
- Shipping either one is a separate decision. The vendored llama.cpp b6102 has no `gemma-embedding`
  architecture (checked in the framework's strings: gemma3 and gemma3n only), so EmbeddingGemma-2 on
  device needs a llama.cpp upgrade or a Core ML conversion. Its numbers have to be re-checked on that
  runtime, not taken from PyTorch.

## Known limits

- One author wrote both the questions and the entries. The overlap check above is the guard
  against making questions easy.
- Gold is binary. Abstract questions are subjective. Their gold lists only entries that state the
  feeling plainly.
- Tags are used only by `kw`, as in the app. The embedding systems see the entry text.

## Amendment after the first run (same day)

The first run's filler used each trap line about 20 times in 400 entries, so keyword collisions were
planted, not realistic. `build_corpus.py 2` caps each trap line at 2 uses. The capped corpus is now the headline,
and the uncapped one is reported as a stress test. The questions, gold, systems, metrics and bar are unchanged.

## Second round (same day): systems added, bar unchanged

These were added after the first results:
- EmbeddingGemma v1 and v2 as GGUFs through llama.cpp b11496 (`gguf_embed.py`)
- keyword-only fixes (`kw-rank`, `kw-idf`, `kw-stemidf`) and an IDF hybrid (`hybidf-*`)
- monolingual de/es/fr/ja sets (`cases/<lang>/`, 15 questions each, same classes and gold rule)

The keyword fixes use the app's own `askStem` and a fixed 25% document-frequency cutoff, chosen before
scoring and not tuned afterwards. The de/es/fr filler was rewritten in first person after the first
monolingual run showed pronoun rates far below the targets' (a free signal for keyword search).
