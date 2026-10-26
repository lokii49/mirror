#!/usr/bin/env python3
"""Round 2 (RUBRIC.md): B1 vs B1 + a second sentence above a score floor, on a semantic dump.
Usage: python3 score_second.py <dump dir> <pool.jsonl> <queries.tsv>"""
import csv, glob, json, os, sys

dump, pool_path, queries_path = sys.argv[1:4]
pool = {r["id"]: r for r in map(json.loads, open(pool_path))}
with open(queries_path, newline="") as f:
    queries = {r["qid"]: r for r in csv.DictReader(f, delimiter="\t")}
rows = []
for path in sorted(glob.glob(os.path.join(dump, "*.json"))):
    rec = json.load(open(path))
    if rec.get("retrieval") != "semantic":
        continue
    gold = [pool[g]["original"] for g in queries[rec["qid"]]["gold"].split(",")]
    ranked = sorted(rec["sentences"], key=lambda s: -s["sem"])     # stable: ties keep pool order
    rows.append((rec["qid"], ranked, [any(s["quote"] in t for t in gold) for s in ranked]))
assert {q for q, _, _ in rows} == set(queries), "every question dumped, semantically"


def rule(name, second):
    shown = rel = hit = two = sec = secrel = 0
    for _, ranked, flags in rows:
        pick = [0] + ([1] if len(ranked) > 1 and second(ranked) else [])
        shown += len(pick); rel += sum(flags[i] for i in pick); hit += any(flags[i] for i in pick)
        if len(pick) == 2:
            two += 1; sec += 1; secrel += flags[1]
    n = len(rows)
    pct = lambda a, b: f"{100 * a / b:.0f}%" if b else "-"
    print(f"| {name} | {pct(rel, shown)} | {pct(hit, n)} | {pct(two, n)} | {pct(secrel, sec)} |")


print(f"{len(rows)} questions\n\n| rule | PREC | HIT | TWO | SECOND |\n|---|---|---|---|---|")
rule("B1 (ships)", lambda r: False)
for floor in (0.40, 0.45, 0.50):
    rule(f"F{int(floor * 100)}: second if score >= {floor}", lambda r, f=floor: r[1]["sem"] >= f)
rule("B2 (always two)", lambda r: True)
print("\nmisses (B1 top sentence not gold):")
for q, ranked, flags in rows:
    if not flags[0]:
        print(f"  {q} {queries[q]['query']!r} -> {ranked[0]['quote']!r} ({ranked[0]['sem']:.3f})")
