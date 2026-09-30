#!/usr/bin/env python3
"""Scores Gemma's EMOTION_DETECT on mood/cases.tsv with the RUBRIC.md "Mood detection" rules.
Usage: MODEL=... python3 mood/run.py [system.txt] [seeds]"""
import csv, os, re, subprocess, sys, tempfile, collections
here = os.path.dirname(os.path.abspath(__file__))
rig = os.path.join(here, "..", ".build", "release", "rig")
system = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "system.txt")
seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
LABELS = ["Joyful","Grateful","Peaceful","Content","Energized","Hopeful","Anxious","Overwhelmed","Frustrated","Drained","Sad","Numb"]
HARD = {"Anxious","Overwhelmed","Frustrated","Drained","Sad","Numb"}

def recognized(raw):  # app's recognizedEmotion
    tok = next((t for t in re.split(r"[^0-9A-Za-zÀ-ÿ]+", raw) if t), raw)
    return next((l for l in LABELS if l.lower() == tok.lower()), None)

stats = collections.defaultdict(collections.Counter)
conf = collections.Counter()
with open(os.path.join(here, os.environ.get("CASES", "cases.tsv")), encoding="utf-8") as f, tempfile.TemporaryDirectory() as tmp:
    for row in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
        u = os.path.join(tmp, "u.txt"); p = os.path.join(tmp, "p.prompt")
        open(u, "w").write(row["text"])
        open(p, "w").write(subprocess.run([rig, "template", system, u], capture_output=True, text=True, check=True).stdout)
        out = subprocess.run([rig, "gen", p, "0.1", str(seeds), "30"], capture_output=True, text=True, check=True).stdout
        for line in out.splitlines():
            m = re.match(r"\[\d+\] (.*)$", line)
            if not m: continue
            raw = m.group(1).strip().strip('"')
            pred = recognized(raw)
            eff = pred or "Content"          # the app records Content when unrecognized
            gold = row["gold"]; s = stats[row["lang"]]
            s["n"] += 1
            s["exact"] += eff == gold
            s["bucket"] += (eff in HARD) == (gold in HARD)
            s["false_hard"] += gold not in HARD and eff in HARD
            s["missed_hard"] += gold in HARD and eff not in HARD
            s["gold_hard"] += gold in HARD; s["gold_ok"] += gold not in HARD
            s["unrec"] += pred is None
            if eff != gold: conf[(row["lang"], gold, eff if pred else f"?{raw[:12]}")] += 1
for lang, s in stats.items():
    n = s["n"]
    print(f"{lang}: n={n} EXACT {s['exact']/n:.0%}  BUCKET {s['bucket']/n:.0%}  "
          f"MISSED_HARD {s['missed_hard']}/{s['gold_hard']} ({s['missed_hard']/max(1,s['gold_hard']):.0%})  "
          f"FALSE_HARD {s['false_hard']}/{s['gold_ok']} ({s['false_hard']/max(1,s['gold_ok']):.0%})  UNREC {s['unrec']}")
print("confusions (lang, gold -> predicted): count")
for (lang, g, p), c in sorted(conf.items(), key=lambda x: -x[1]): print(f"  {lang} {g} -> {p}: {c}")
