#!/usr/bin/env python3
"""Reflection opener rotation on the rig (RUBRIC.md, "Reflection opener rotation").
Usage: MODEL=... python3 opener/run.py <dump_dir> <out_json> [n]"""
import glob, json, os, re, subprocess, sys, tempfile, collections
dump, out_json = sys.argv[1], sys.argv[2]
n = sys.argv[3] if len(sys.argv) > 3 else "10"
rig = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".build", "release", "rig")
OPENERS = json.loads(os.environ["OPENERS"]) if "OPENERS" in os.environ else ['You wrote, "', 'In your words, "', 'Something you wrote: "']
FIRST_PERSON = {"i", "i'm", "i've", "i'd", "i'll", "me", "my", "mine", "myself"}
CLINICAL = ["significant", "grappling", "well-being", "navigating", "processing", "emotional toll",
            "emotional weight", "emotional state", "it's understandable", "valid"]
res = collections.defaultdict(lambda: collections.defaultdict(list))
for prompt_path in sorted(glob.glob(os.path.join(dump, "*_gemma.prompt"))):
    case = os.path.basename(prompt_path).replace("_gemma.prompt", "")
    prompt0 = open(prompt_path).read(); gbnf0 = open(prompt_path.replace(".prompt", ".gbnf")).read()
    assert 'root ::= "You wrote, \\""' in gbnf0 and 'You wrote, "<copy' in prompt0, case
    for opener in OPENERS:
        prompt = prompt0.replace('You wrote, "<copy', opener + '<copy', 1)
        gbnf = gbnf0.replace('root ::= "You wrote, \\""', 'root ::= "' + opener[:-1] + '\\""', 1)
        with tempfile.TemporaryDirectory() as t:
            open(t + "/p", "w").write(prompt); open(t + "/g", "w").write(gbnf)
            out = subprocess.run([rig, "gengrammar", t + "/p", t + "/g", "0.45", n, "700"], capture_output=True, text=True).stdout
        for line in out.splitlines():
            m = re.match(r"\[\d+\] (.*)$", line)
            if not m: continue
            text = m.group(1).replace('\\"', '"').replace("\\n", "\n").strip()
            ok_open = text.startswith(opener)
            i = text.rfind('" ')
            feel = text[i + 2:] if i >= 0 else ""
            words = set(re.split(r"[^a-z']+", feel.lower().replace("’", "'")))
            shape = ok_open and feel.startswith(("That sounds ", "You seem ")) and feel.rstrip().endswith((".", "!", "?")) and not (words & FIRST_PERSON)
            clinical = [c for c in CLINICAL if c in feel.lower()]
            res[opener][case].append({"text": text, "feel": feel, "shape": bool(shape), "clinical": clinical})
json.dump(res, open(out_json, "w"), indent=1)
for opener in OPENERS:
    allr = [r for c in res[opener].values() for r in c]
    print(f"{opener!r}: outputs={len(allr)} SHAPE={sum(r['shape'] for r in allr)}/{len(allr)} CLINICAL={sum(bool(r['clinical']) for r in allr)} unique_feel={len({r['feel'] for r in allr})}")
