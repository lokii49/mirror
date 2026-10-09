#!/usr/bin/env python3
"""Embeds the corpus and queries with EmbeddingGemma-2 (text only), fp32 on CPU, using the model
card's retrieval prompts: query "task: search result | query: ", document "title: none | text: ".
Usage: python3 -I eg_embed.py out/corpus_400.jsonl cases/queries.tsv out/eg_vectors.json [model]"""
import csv, json, sys

import torch
from sentence_transformers import SentenceTransformer

corpus, queries, out = sys.argv[1:4]
name = sys.argv[4] if len(sys.argv) > 4 else "google/embeddinggemma-2"
docs = [json.loads(l) for l in open(corpus, encoding="utf-8")]
with open(queries, encoding="utf-8") as f:
    qs = list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))

model = SentenceTransformer(name, device="cpu", model_kwargs={"torch_dtype": torch.float32})
d = model.encode([e["text"] for e in docs], prompt_name="Document", normalize_embeddings=True, batch_size=16)
q = model.encode([r["query"] for r in qs], prompt_name="SearchQuery", normalize_embeddings=True, batch_size=16)
vecs = {e["id"]: v.tolist() for e, v in zip(docs, d)}
vecs.update({"q:" + r["qid"]: v.tolist() for r, v in zip(qs, q)})
json.dump({"model": name, "dim": int(d.shape[1]), "eg": vecs}, open(out, "w"))
print(f"{name}: {len(docs)} docs, {len(qs)} queries, dim {d.shape[1]}")
