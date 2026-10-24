#!/usr/bin/env python3
"""Scores the Gemma Ask pick round (RUBRIC.md). Usage: python3 score.py <dump dir> [--spot <variant> <n>]
Reads <dump>/<qid>.json, <dump>/runs/<V>/<qid>.txt, out/pool.jsonl, cases/queries.tsv, cases/gold_sentences.tsv."""
import csv, glob, json, os, random, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIX = "The closest things you've written: "
# InsightService.askHardLeanWords / askGoodLeanWords
HARD = set("stress stressed stressing stressful worried worry worrying anxious anxiety sad upset angry anger frustrated frustrating overwhelmed tired exhausted drained lonely scared afraid hurt bothering bother struggle struggling difficult hardest worst down".split())
GOOD = set("happy happiest joy joyful grateful gratitude calm peaceful excited proud fun best love loved enjoy enjoyed glad hopeful".split())
LEAN_EXPECTED = {"p6", "p9", "a1", "a2", "a3", "a5", "a6"}


def load():
    pool = {r["id"]: r for r in map(json.loads, open(os.path.join(HERE, "out", "pool.jsonl")))}
    with open(os.path.join(HERE, "cases", "queries.tsv"), newline="") as f:
        queries = {r["qid"]: r for r in csv.DictReader(f, delimiter="\t")}
    override = dict(line.rstrip("\n").split("\t", 1) for line in open(os.path.join(HERE, "cases", "gold_sentences.tsv")))
    return pool, queries, override


def is_lean(question):
    words = set(re.split(r"[^a-z]+", question.lower()))
    return bool(words & (HARD | GOOD))


def parse(text, options):
    """validateGroundedAsk: the prefix, then 1-2 options separated by one space; a repeat is dropped."""
    text = text.strip()
    if not text.startswith(PREFIX):
        return None
    rest, quotes = text[len(PREFIX):], []
    while rest:
        match = next((o for o in options if rest.startswith(o)), None)
        if match is None or len(quotes) == 2:
            return None
        rest = rest[len(match):]
        if rest.startswith(" "):
            rest = rest[1:]
        if match not in quotes:
            quotes.append(match)
    return quotes or None


def main():
    dump = sys.argv[1]
    pool, queries, override = load()
    records = {json.load(open(p))["qid"]: json.load(open(p)) for p in glob.glob(os.path.join(dump, "*.json"))}
    lean = {q for q, r in queries.items() if is_lean(r["query"])}
    assert lean == LEAN_EXPECTED, lean
    sys.path.insert(0, HERE)
    from variants import option_sets

    def gold_texts(qid):
        return [override.get(g, pool[g]["original"]) for g in queries[qid]["gold"].split(",")]

    def relevant(qid, option, by_option):
        quote = by_option[option]["quote"]
        return any(quote in t for t in gold_texts(qid))

    answers = {}   # variant -> qid -> [list of option lists]
    unseen = {}
    for qid, rec in records.items():
        # Keyed by option, falling back to the quote: a repeated sentence can carry another entry's date in S0's
        # options (round-robin dedupe) than in the dump's (pool order). Scoring only uses the quote.
        by_quote = {s["quote"]: s for s in rec["sentences"]}
        by_option = {s["option"]: s for s in rec["sentences"]}
        sets = option_sets(rec)
        for o in sets["S0"]:
            by_option.setdefault(o, by_quote[o.split(', you wrote, "', 1)[1][:-1]])
        sem_all = [s["option"] for s in sorted(rec["sentences"], key=lambda s: -s["sem"])]
        lex_all = [s["option"] for s in sorted(rec["sentences"], key=lambda s: -s["lex"])]
        answers.setdefault("B1", {})[qid] = [sem_all[:1]]
        answers.setdefault("B2", {})[qid] = [sem_all[:2]]
        answers.setdefault("B1L", {})[qid] = [lex_all[:1]]
        for v in ("S0", "V1", "V2", "V3"):
            path = os.path.join(dump, "runs", v, f"{qid}.txt")
            if not os.path.exists(path):
                continue
            outs = []
            for line in open(path):
                m = re.match(r"\[\d+\] (.*)$", line.rstrip("\n"))
                if m:
                    outs.append(parse(m.group(1).replace("\\n", "\n"), sets[v]))
            answers.setdefault(v, {})[qid] = outs
            key = "lex" if v == "V2" else "sem"
            top3 = [o for o in sorted(sets[v], key=lambda o: -by_option[o][key])][:3]
            answers.setdefault(v + "+gate", {})[qid] = [None if q is None else q[:1] + [o for o in q[1:] if o in top3] for q in outs]
        rec["_by_option"], rec["_sets"] = by_option, sets

    def table(qids, title):
        print(f"\n### {title} ({len(qids)} questions)\n")
        print("| variant | answers | invalid | PREC | HIT | FIRST | TWO | UNSEEN | CEIL |")
        print("|---|---|---|---|---|---|---|---|---|")
        for v in ["S0", "S0+gate", "V1", "V1+gate", "V2", "V2+gate", "V3", "V3+gate", "B1", "B2", "B1L"]:
            if v not in answers or not all(q in answers[v] for q in qids):
                continue
            n = invalid = shown = rel = hit = first = two = uns = 0
            ceil = 0
            base = v.split("+")[0]
            for q in qids:
                rec = records[q]
                by = rec["_by_option"]
                opts = rec["_sets"].get(base, [s["option"] for s in rec["sentences"]])
                ceil += any(relevant(q, o, by) for o in opts)
                for a in answers[v][q]:
                    n += 1
                    if a is None:
                        invalid += 1
                        continue
                    flags = [relevant(q, o, by) for o in a]
                    shown += len(a); rel += sum(flags); hit += any(flags); first += flags[0]; two += len(a) == 2
                    uns += sum(not by[o]["inPrompt"] for o in a)
            pct = lambda x, d: f"{100 * x / d:.0f}%" if d else "-"
            print(f"| {v} | {n} | {invalid} | {pct(rel, shown)} | {pct(hit, n)} | {pct(first, n)} | {pct(two, n)} | {pct(uns, shown)} | {pct(ceil, len(qids))} |")

    allq = sorted(records)
    table([q for q in allq if q not in lean], "Decision set (non-lean)")
    table([q for q in allq if q in lean], "Lean questions (report only)")
    table([q for q in allq if queries[q]["class"] == "short"], "Short questions (subset of decision set)")
    rec0 = next(iter(records.values()))
    print(f"\nretrieval={rec0['retrieval']} wordEmbedding={rec0['wordEmbedding']}")

    if "--spot" in sys.argv:
        i = sys.argv.index("--spot")
        variant, n = sys.argv[i + 1], int(sys.argv[i + 2])
        rng = random.Random(7)
        items = []
        for v in (variant, "S0"):
            pick = [(q, o) for q in allq if q not in lean for a in answers[v][q] if a for o in a
                    if not relevant(q, o, records[q]["_by_option"])]
            items += [(v, q, o) for q, o in rng.sample(pick, min(n, len(pick)))]
        rng.shuffle(items)
        with open(os.path.join(dump, "spot_key.json"), "w") as f:
            json.dump(items, f)
        for k, (_, q, o) in enumerate(items):
            print(f"{k}\t{queries[q]['query']}\t{records[q]['_by_option'][o]['quote']}")


if __name__ == "__main__":
    main()
