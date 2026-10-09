#!/usr/bin/env python3
"""Embeds the corpus and queries with an EmbeddingGemma GGUF through llama.cpp's llama-server, the
runtime the app would ship (quantized, Metal). Same retrieval prompts as eg_embed.py, added here by
hand because llama.cpp doesn't apply sentence-transformers prompts. Pure stdlib.
Usage: python3 gguf_embed.py <llama-server> <model.gguf> corpus.jsonl queries.tsv out.json"""
import csv, json, os, subprocess, sys, time, urllib.request

server, model, corpus, queries, out = sys.argv[1:6]
PORT = 8091
QUERY, DOC = "task: search result | query: ", "title: none | text: "

docs = [json.loads(l) for l in open(corpus, encoding="utf-8")]
with open(queries, encoding="utf-8") as f:
    qs = list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))

proc = subprocess.Popen([server, "-m", model, "--embedding", "--port", str(PORT), "-c", "2048", "-ub", "2048",
                         "--log-disable"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    for _ in range(60):
        if proc.poll() is not None:
            sys.exit(f"llama-server exited ({proc.returncode}); run it by hand to see why (e.g. an older build can't load this GGUF)")
        try:
            if b"ok" in urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=1).read():
                break
        except OSError:
            time.sleep(1)
    else:
        sys.exit("llama-server didn't become healthy in 60s")

    def embed(texts):
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/embeddings", data=json.dumps({"input": texts}).encode(),
                                     headers={"Content-Type": "application/json"})
        data = json.load(urllib.request.urlopen(req, timeout=300))["data"]
        return [d["embedding"] for d in sorted(data, key=lambda d: d["index"])]

    started = time.time()
    vecs = {}
    for i in range(0, len(docs), 32):
        batch = docs[i:i + 32]
        vecs.update({e["id"]: v for e, v in zip(batch, embed([DOC + e["text"] for e in batch]))})
    vecs.update({"q:" + r["qid"]: v for r, v in zip(qs, embed([QUERY + r["query"] for r in qs]))})
    secs = time.time() - started
finally:
    proc.terminate(); proc.wait()

json.dump({"model": os.path.basename(model), "eg": vecs}, open(out, "w"))
print(f"{os.path.basename(model)}: {len(docs)} docs + {len(qs)} queries in {secs:.1f}s, dim {len(next(iter(vecs.values())))}")
