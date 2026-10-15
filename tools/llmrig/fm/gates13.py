#!/usr/bin/env python3
"""Round 13 gates (RUBRIC_FM.md): FMDailyGuard name casing, old vs new guard on the same raw outputs.
  gates13.py <results.jsonl> <old.jsonl> <new.jsonl> <dumpdir>
"""
import json, re, sys, collections

results, old, new, dump = sys.argv[1:5]
R = [json.loads(l) for l in open(results)]
O = {(r["case"], r["i"]): r for r in map(json.loads, open(old))}
N = {(r["case"], r["i"]): r for r in map(json.loads, open(new))}

def source(case):
    user = open(f"{dump}/{case}_fm_user.txt").read()
    head = user.split("Long-term context:")[0]
    return head.split("Recent entries:\n", 1)[-1]

def sentence_starts(text):
    """Character offsets where a sentence starts (text start, after .!?… or a newline)."""
    starts = {0}
    for m in re.finditer(r"[.!?…]['\"”’)]*\s+|\n+", text):
        starts.add(m.end())
    return starts

def caps_only_at_starts(word, text):
    """The entries write `word` capitalized only where a sentence starts (never mid-sentence)."""
    starts = sentence_starts(text)
    seen = False
    for m in re.finditer(r"\b" + re.escape(word) + r"\b", text, re.IGNORECASE):
        seen = True
        if m.group(0)[0].isupper() and m.start() not in starts:
            return False
    return seen

def wrong_caps(insight, src):
    """Words the insight capitalizes mid-sentence that the entries capitalize only at sentence starts."""
    starts = sentence_starts(insight)
    bad = set()
    for m in re.finditer(r"\b([A-ZÀ-Ý][\wÀ-ÿ']+)", insight):
        if m.start() in starts: continue
        w = m.group(1)
        if w.lower() in {"i", "you", "your"}: continue
        if caps_only_at_starts(w, src): bad.add(w)
    return bad

# Sanity: the new replay reproduces what fmrig showed.
mismatch = sum(1 for r in R if "raws" in r and
               ((r.get("fallback") is True) != (N[(r["case"], r["i"])].get("fallback") is True) or
                (r.get("fields", {}).get("insight") != N[(r["case"], r["i"])].get("insight"))))
print(f"sanity: new replay vs fmrig mismatches = {mismatch}")

# G1
g1 = []
for k, o in O.items():
    n = N[k]
    if o.get("fallback") != n.get("fallback") or o.get("attempt") != n.get("attempt") or o.get("dropped") != n.get("dropped") \
       or o.get("quote") != n.get("quote") or (o.get("insight") or "").lower() != (n.get("insight") or "").lower():
        g1.append(k)
print(f"G1 runs where old/new differ beyond letter case: {len(g1)} {g1[:5]}")
cased = [(k, O[k]['insight'], N[k]['insight']) for k in O if O[k].get("insight") and O[k].get("insight") != N[k].get("insight")]
print(f"   runs whose casing differs: {len(cased)}")
for k, a, b in cased[:12]: print(f"     {k[0]}#{k[1]}: old={a!r} new={b!r}")

# G2
def g2(rows):
    hits = []
    for k, r in rows.items():
        if r.get("insight"):
            bad = wrong_caps(r["insight"], source(k[0]))
            if bad: hits.append((k, sorted(bad)))
    return hits
g2o, g2n = g2(O), g2(N)
print(f"G2 shown insights with a sentence-start word capitalized mid-sentence: old={len(g2o)} new={len(g2n)}")
for k, b in g2o[:10]: print(f"     old {k[0]}#{k[1]}: {b}")
for k, b in g2n[:10]: print(f"     NEW {k[0]}#{k[1]}: {b}")

# G3
names = {"hold5_priya": "priya", "hold5_tomas": "tomás", "hold5_grief": "lena", "hold5_lisbon": "lisbon"}
shown3 = lower3 = 0
for k, r in N.items():
    if k[0] in names and r.get("insight"):
        shown3 += 1
        quote_and_insight = r["insight"]
        if re.search(r"\b" + names[k[0]] + r"\b", quote_and_insight): lower3 += 1
print(f"G3 lowercase names in shown insights (name cases): {lower3}/{shown3} = {100*lower3/max(shown3,1):.1f}%")
mentions = sum(1 for k, r in N.items() if k[0] in names and r.get("insight") and re.search(r"\b" + names[k[0]] + r"\b", r["insight"], re.I))
print(f"   (insights naming them at all: {mentions})")

# G4
runs = len(R); fb = sum(1 for r in R if r.get("fallback")); err = collections.Counter(r["case"] for r in R if "error" in r)
print(f"G4 fallback {fb}/{runs} = {100*fb/runs:.1f}%; errors by case: {dict(err)}")
per = collections.Counter(r["case"] for r in R if r.get("fallback"))
print(f"   fallback by case: {dict(per)}")
