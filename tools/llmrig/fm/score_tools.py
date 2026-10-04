#!/usr/bin/env python3
"""Blind sheet + automatic checks for the FM rig (rubric: RUBRIC_FM.md).
  score_tools.py sheet <results.jsonl> <dumpdir> <out_dir>   -> blind.txt (shuffled, no labels), key.json
  score_tools.py report <key.json> <scores.json> <results.jsonl> <dumpdir>   -> per variant/case table
"""
import json, random, re, sys, collections

SCENE = set("""rain sky light sunlight sunset sunrise breeze wind air scent smell steam mug music melody silence sound
sounds birds window candle coffee tea blanket clouds cloud moon stars snow fog glow whisper whispers laughter
smell aroma warmth chill""".split())
OK_CAPS = {"you", "your", "mirrornotes", "i", "mum", "mom", "dad"}

def words(s): return re.findall(r"[a-z']+", s.lower().replace("’", "'"))

def source_of(dumpdir, case):
    return open(f"{dumpdir}/{case}_a1_user.txt").read()

def auto_flags(rec, source):
    text = rec.get("text", "")
    src = set(words(source))
    flags = []
    if "error" in rec: return ["ERROR"]
    if rec.get("quoteVerbatim") is False: flags.append("QUOTE_NOT_VERBATIM")
    if rec.get("earlierVerbatim") is False: flags.append("EARLIER_NOT_VERBATIM")
    scene = sorted({w for w in words(text) if w in SCENE and w not in src})
    if scene: flags.append("SCENE:" + ",".join(scene))
    caps = set()
    for m in re.finditer(r"(?<![.!?\"“]\s)(?<!^)\b([A-Z][a-z]+)\b", text):
        w = m.group(1)
        if w.lower() not in OK_CAPS and w.lower() not in src: caps.add(w)
    if caps: flags.append("NAME?:" + ",".join(sorted(caps)))
    if re.search(r"\b(I|my|me|I'm|I've)\b", re.sub(r"\"[^\"]*\"", "", text)): flags.append("FIRST_PERSON")
    return flags

def cmd_sheet(results, dumpdir, out):
    import os
    os.makedirs(out, exist_ok=True)
    rows = [json.loads(l) for l in open(results)]
    random.Random(20261002).shuffle(rows)
    key, lines = [], []
    for n, r in enumerate(rows, 1):
        key.append({"id": n, "variant": r["variant"], "case": r["case"], "i": r["i"], "flags": auto_flags(r, source_of(dumpdir, r["case"])), "seconds": r.get("seconds"), "error": r.get("error")})
        lines.append(f"[{n}] ({r['case']}) " + (r.get("text") or f"<<ERROR {r.get('error')}>>").replace("\n", " "))
    open(f"{out}/blind.txt", "w").write("\n".join(lines) + "\n")
    json.dump(key, open(f"{out}/key.json", "w"))
    print(len(rows), "outputs")

def cmd_report(keyf, scoresf, results, dumpdir):
    key = {k["id"]: k for k in json.load(open(keyf))}
    scores = {int(k): v for k, v in json.load(open(scoresf)).items()}
    agg = collections.defaultdict(lambda: collections.Counter())
    for i, k in key.items():
        s = scores.get(i)
        if not s: continue
        a = agg[(k["variant"], k["case"])]
        a["n"] += 1
        for m in ("MAIN", "INVENT", "SWAP", "TENSE", "FORMAT", "INSIGHT"):
            a[m] += 1 if s.get(m, 1) else 0
        a["PASS"] += 1 if all(s.get(m, 1) for m in ("MAIN", "INVENT", "SWAP", "TENSE", "FORMAT")) else 0
        a["flagged"] += 1 if k["flags"] else 0
    tot = collections.defaultdict(lambda: collections.Counter())
    for (v, c), a in sorted(agg.items()):
        tot[v].update(a)
    for v in ("free", "v1", "v2"):
        t = tot[v]
        print(f"{v}: n={t['n']} PASS={t['PASS']} ({100*t['PASS']/max(t['n'],1):.0f}%) MAIN={t['MAIN']} INVENT_ok={t['INVENT']} SWAP_ok={t['SWAP']} TENSE_ok={t['TENSE']} FORMAT_ok={t['FORMAT']} INSIGHT={t['INSIGHT']} autoflagged={t['flagged']}")
    print("per case PASS (free / v1 / v2):")
    cases = sorted({c for (_, c) in agg})
    for c in cases:
        print(f"  {c:12s}", " / ".join(f"{agg[(v,c)]['PASS']}/{agg[(v,c)]['n']}" for v in ("free", "v1", "v2")))

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "sheet": cmd_sheet(*sys.argv[2:5])
    elif cmd == "report": cmd_report(*sys.argv[2:6])
