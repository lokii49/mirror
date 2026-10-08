#!/usr/bin/env python3
"""Scores Ask retrieval per RUBRIC.md: keyword search (exact port of SearchService.search) against
Apple NL embeddings and EmbeddingGemma-2, at each corpus size. Pure stdlib.
Usage: python3 score.py [dir]   (dir defaults to out/; reads corpus_*.jsonl, nl_vectors.json,
eg_vectors.json there and writes detail_400.tsv there)"""
import csv, json, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, "out")
HYBRID_BOOST = 0.15

# --- SearchService.search, ported line for line -------------------------------------------------
STOP = set("""a an the and or but in on at to for of with by from is was are were be been have has had do
does did will would could should may might can i me my we our you your he she it they them their this
that these those what when where how why who about just so up out if its also then than not no very
really feel felt feeling think thought""".split())
SEPARATORS = set(" .,!?;:\"'()[]{}")


def keywords(query):
    parts, cur = [], ""
    for ch in query.lower():
        if ch in SEPARATORS:
            parts.append(cur); cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [p.strip() for p in parts if len(p.strip()) > 2 and p.strip() not in STOP]


def kw_match(entry, kws):
    lower = entry["text"].lower()
    tags = [t.lower() for t in entry["tags"]]
    return any(k in lower or any(k in t for t in tags) for k in kws)


def kw_search(query, newest_first, limit=10):
    kws = keywords(query)
    if not kws:
        return newest_first[:limit]
    matched = [e for e in newest_first if kw_match(e, kws)]
    return (matched or newest_first)[:limit]


# --- keyword-search fixes (no model; nothing here is tuned on cases/queries.tsv) ----------------
# InsightService.askStem, ported: irregular table, then one of ing/ed/es/s/ly if ≥3 letters remain.
IRREGULAR = {"slept": "sleep", "woke": "wake", "ate": "eat", "went": "go", "gone": "go", "ran": "run",
    "met": "meet", "spent": "spend", "bought": "buy", "drank": "drink", "wrote": "write",
    "saw": "see", "seen": "see", "lost": "lose", "left": "leave", "told": "tell", "said": "say",
    "made": "make", "took": "take", "got": "get", "came": "come", "gave": "give", "found": "find",
    "cried": "cry", "tried": "try", "thought": "think", "brought": "bring", "taught": "teach",
    "fought": "fight", "kept": "keep", "sat": "sit", "paid": "pay", "sold": "sell", "held": "hold"}
GENERIC_DF = 0.25   # a keyword found in more than this share of the user's entries carries no signal
GENERIC_MIN_ENTRIES = 20   # SearchService.genericCutoffMinimumEntries: no share cutoff below this


def ask_stem(w):
    w = w.lower()
    if w in IRREGULAR:
        return IRREGULAR[w]
    for suf in ("ing", "ed", "es", "s", "ly"):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            return w[: -len(suf)]
    return w


def search_stem(w):
    """SearchService.searchStem: askStem, then a trailing "e" dropped (migraine/migraines meet)."""
    s = ask_stem(w)
    return s[:-1] if len(s) > 3 and s.endswith("e") else s


def search_words(text):
    """SearchService.words(in:): any non-letter, non-digit splits, apostrophes of both kinds included."""
    return re.findall(r"[^\W_]+", text.lower())


def word_stems(text):
    words, cur = [], ""
    for ch in text.lower():
        if ch.isalpha() or ch == "'":
            cur += ch
        else:
            words.append(cur); cur = ""
    words.append(cur)
    return {ask_stem(w) for w in words if w}


def kw_fixed(query, newest_first, mode, limit=10):
    """mode: "rank" (substring rule, most keywords matched first), "idf" (substring rule, IDF-weighted,
    generic keywords dropped), "stemidf" (the shipped SearchService.search: whole-word searchStem
    match, IDF-weighted, generic keywords dropped from GENERIC_MIN_ENTRIES entries up)."""
    kws = keywords(query)
    if mode == "stemidf":
        kws = sorted({search_stem(w) for w in search_words(query) if len(w) > 2 and w not in STOP})
        stems = {e["id"]: {search_stem(w) for w in search_words(e["text"] + " " + " ".join(e["tags"]))}
                 for e in newest_first}
        hit = lambda e, k: k in stems[e["id"]]
    else:
        hit = lambda e, k: k in e["text"].lower() or any(k in t.lower() for t in e["tags"])
    n = len(newest_first)
    weight = {}
    for k in kws:
        df = sum(hit(e, k) for e in newest_first)
        if df == 0:
            continue
        if mode == "rank":
            weight[k] = 1.0
        elif df / n <= GENERIC_DF or n < GENERIC_MIN_ENTRIES:
            weight[k] = math.log(n / df)
    scored = [(sum(w for k, w in weight.items() if hit(e, k)), -i, e) for i, e in enumerate(newest_first)]
    matched = [t for t in scored if t[0] > 0]
    if not matched:
        return newest_first[:limit], set()
    matched.sort(key=lambda t: (t[0], t[1]), reverse=True)
    return [e for _, _, e in matched[:limit]], {e["id"] for _, _, e in matched}


# --- embeddings ---------------------------------------------------------------------------------
def norm(v):
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]


def cos(a, b):
    return sum(x * y for x, y in zip(a, b))


def load_vectors():
    nl = json.load(open(os.path.join(OUT, "nl_vectors.json")))
    eg = json.load(open(os.path.join(OUT, "eg_vectors.json")))
    model = nl["nlc_model"]
    systems = {
        "nls": {k: norm(v) for k, v in nl["nls"].items()},
        "nlc": {k: norm(v) for k, v in nl["nlc_full"].items()},
        "eg768": {k: norm(v) for k, v in eg["eg"].items()},
        "eg256": {k: norm(v[:256]) for k, v in eg["eg"].items()},
    }
    sents = {k: [norm(v) for v in vs] for k, vs in nl["nlc_sent"].items()}
    # Optional GGUF runs through llama.cpp (gguf_embed.py): gguf_<name>.json -> system "<name>".
    for f in sorted(os.listdir(OUT)):
        if f.startswith("gguf_") and f.endswith(".json"):
            vecs = json.load(open(os.path.join(OUT, f)))["eg"]
            systems[f[5:-5]] = {k: norm(v) for k, v in vecs.items()}
            systems[f[5:-5] + "-256"] = {k: norm(v[:256]) for k, v in vecs.items()}   # Matryoshka
    return systems, sents, model


def scorer(name, systems, sents, model):
    """Returns f(qkey, entry) -> similarity or None (can't compare: no vector / other script model)."""
    if name == "nlc_sent":
        q = systems["nlc"]
        def f(qk, e):
            if model.get(qk) != model.get(e["id"]) or qk not in q or e["id"] not in sents:
                return None
            return max(cos(q[qk], s) for s in sents[e["id"]])
        return f
    vecs = systems[name]
    def f(qk, e):
        if qk not in vecs or e["id"] not in vecs:
            return None
        if name == "nlc" and model.get(qk) != model.get(e["id"]):
            return None
        return cos(vecs[qk], vecs[e["id"]])
    return f


def embed_search(sim, qk, newest_first, query=None, limit=10, boosted=None):
    kws = keywords(query) if query is not None else None
    scored = []
    for rank, e in enumerate(newest_first):
        s = sim(qk, e)
        if s is None:
            s = -9.0
        if boosted is not None:
            s += HYBRID_BOOST if e["id"] in boosted else 0.0
        elif kws:
            s += HYBRID_BOOST if kw_match(e, kws) else 0.0
        scored.append((-s, rank, e))
    scored.sort(key=lambda t: (t[0], t[1]))
    return [e for _, _, e in scored[:limit]]


# --- metrics ------------------------------------------------------------------------------------
def pool(top, newest_first):
    ids = {e["id"] for e in top}
    return top + [e for e in newest_first if e["id"] not in ids][:8]


def metrics(top, newest_first, gold):
    ids = [e["id"] for e in top]
    pids = {e["id"] for e in pool(top, newest_first)}
    r10 = sum(g in ids for g in gold) / len(gold)
    rp = sum(g in pids for g in gold) / len(gold)
    mrr = next((1 / (i + 1) for i, x in enumerate(ids) if x in gold), 0.0)
    return r10, rp, mrr


def main():
    qpath = os.path.join(OUT, "queries.tsv")   # monolingual sets carry their own questions
    if not os.path.exists(qpath):
        qpath = os.path.join(HERE, "cases", "queries.tsv")
    sizes = sorted(int(f[7:-6]) for f in os.listdir(OUT) if f.startswith("corpus_") and f.endswith(".jsonl"))
    with open(qpath, encoding="utf-8") as f:
        queries = list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    systems, sents, model = load_vectors()
    targets = {json.loads(l)["id"]: json.loads(l) for l in open(os.path.join(OUT, "corpus_0.jsonl"), encoding="utf-8")}

    # Label check: share of gold entries that keyword search would match.
    # kw: SearchService's own substring rule. signal: whole-word stems of keywords that are in at most
    # GENERIC_DF of the largest corpus (SearchService's stopwords are English, so "ich"/"mit" count in kw).
    print("== keyword overlap with gold (label check): kw / signal ==")
    largest = [json.loads(l) for l in open(os.path.join(OUT, f"corpus_{sizes[-1]}.jsonl"), encoding="utf-8")]
    stems_of = {e["id"]: word_stems(e["text"] + " " + " ".join(e["tags"])) for e in largest}
    for q in queries:
        kws = keywords(q["query"])
        gold = q["gold"].split(",")
        hit = sum(kw_match(targets[g], kws) for g in gold)
        signal = [k for k in {ask_stem(k) for k in kws}
                  if sum(k in st for st in stems_of.values()) <= GENERIC_DF * len(largest)]
        shit = sum(any(k in stems_of[g] for k in signal) for g in gold)
        print(f"{q['qid']:4} {q['class']:10} {hit}/{len(gold)} / {shit}/{len(gold)}  kws={kws}")

    gguf = [n for n in systems if n not in ("nls", "nlc", "eg768", "eg256")]
    sims = {n: scorer(n, systems, sents, model) for n in ["nls", "nlc", "nlc_sent", "eg768", "eg256"] + gguf}
    names = ["kw", "kw-rank", "kw-idf", "kw-stemidf", "nls", "nlc", "nlc_sent", "eg768", "eg256"] + gguf + [
             "hyb-nls", "hyb-nlc", "hyb-eg768", "hyb-eg256", "hybidf-nlc", "hybidf-eg768"]
    for n in gguf:   # fidelity of a quantized EmbeddingGemma-2 run against the fp32 PyTorch vectors
        if n.startswith("eg2"):
            same = [cos(systems[n][k], systems["eg768"][k]) for k in systems[n] if k in systems["eg768"]]
            print(f"{n} vs eg768 (PyTorch fp32): mean cosine {sum(same) / len(same):.4f}, min {min(same):.4f}")
    groups = [("lexical",), ("paraphrase",), ("abstract",), ("nonen",), ("paraphrase", "abstract"),
              ("paraphrase", "abstract", "nonen"), ("lexical", "paraphrase", "abstract", "nonen")]
    detail = []
    for size in sizes:
        corpus = [json.loads(l) for l in open(os.path.join(OUT, f"corpus_{size}.jsonl"), encoding="utf-8")]
        newest = sorted(corpus, key=lambda e: e["date"], reverse=True)
        res = {n: {} for n in names}
        for q in queries:
            gold, qk = set(q["gold"].split(",")), "q:" + q["qid"]
            for n in names:
                if n == "kw":
                    top = kw_search(q["query"], newest)
                elif n.startswith("kw-"):
                    top, _ = kw_fixed(q["query"], newest, n[3:])
                elif n.startswith("hybidf-"):
                    _, boosted = kw_fixed(q["query"], newest, "stemidf")
                    top = embed_search(sims[n[7:]], qk, newest, boosted=boosted)
                elif n.startswith("hyb-"):
                    top = embed_search(sims[n[4:]], qk, newest, query=q["query"])
                else:
                    top = embed_search(sims[n], qk, newest)
                res[n][q["qid"]] = metrics(top, newest, gold)
                if size == sizes[-1]:
                    detail.append([n, q["qid"], q["class"], q["lang"], f"{res[n][q['qid']][0]:.2f}",
                                   ",".join(sorted(gold - {e['id'] for e in top})), ",".join(e["id"] for e in top)])
        print(f"\n== corpus {len(corpus)} entries ({size} filler): R@10 / R@pool / MRR ==")
        print(f"{'system':10} " + " ".join(f"{'+'.join(g)[:22]:>22}" for g in groups))
        for n in names:
            cells = []
            for g in groups:
                qs = [q["qid"] for q in queries if q["class"] in g]
                if not qs:
                    cells.append("-".rjust(22)); continue
                m = [sum(res[n][x][i] for x in qs) / len(qs) for i in range(3)]
                cells.append(f"{m[0]:.2f}/{m[1]:.2f}/{m[2]:.2f}".rjust(22))
            print(f"{n:10} " + " ".join(cells))
        if size == sizes[-1] and any(q["class"] == "nonen" for q in queries):
            print("\nnonen by language (R@10):")
            for lang in sorted({q["lang"] for q in queries if q["class"] == "nonen"}):
                qs = [q["qid"] for q in queries if q["lang"] == lang]
                print(f"  {lang}: " + "  ".join(f"{n}={sum(res[n][x][0] for x in qs) / len(qs):.2f}" for n in names))
    with open(os.path.join(OUT, f"detail_{sizes[-1]}.tsv"), "w", encoding="utf-8") as f:
        f.write("system\tqid\tclass\tlang\tR@10\tmissed_gold\ttop10\n")
        for row in detail:
            f.write("\t".join(row) + "\n")


if __name__ == "__main__":
    sys.exit(main())
