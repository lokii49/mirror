#!/usr/bin/env python3
# Applies review replies (JSON blocks with "mirrorTranslationReview": 1, from the review page or
# review.md) to grounded_locales.py by exact-literal replacement inside each language's block.
# Every change's "original" must still match the current text, or nothing is written.
#   python3 tools/i18n/review/apply_review.py reply.md [--dry-run]
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "grounded_locales.py")
NB = " "

def lit(s):
    body = s.replace("\\", "\\\\").replace('"', '\\"')
    out = '"' + body.replace(NB, '"+NB+"') + '"'
    return out.replace('""+', "").replace('+""', "")

def blocks(text):
    for m in re.finditer(r"```json\s*(\{.*?\})\s*```", text, re.S):
        d = json.loads(m.group(1))
        if d.get("mirrorTranslationReview") == 1:
            yield d

reply = open(sys.argv[1]).read()
src = open(SRC).read()
starts = {m.group(1): m.start() for m in re.finditer(r'^L\["(\w+)"\] = dict\(', src, re.M)}
ends = sorted(list(starts.values()) + [src.index("\nBUCKET = ")])
skipped, applied = [], 0
for review in blocks(reply):
    code = review["language"]
    a = starts[code]; b = min(e for e in ends if e > a)
    block = src[a:b]
    for ch in review["changes"]:
        key = ch["id"].split("|")[0]
        if key == "askHint":
            skipped.append((code, ch["id"], "askHint lives in build_data.py ASK_HINT"))
            continue
        old, new = lit(ch["original"]), lit(ch["suggestion"])
        n = block.count(old)
        if n != 1:
            sys.exit(f"{code} {ch['id']}: original found {n} times in the {code} block — stale or ambiguous, nothing written")
        block = block.replace(old, new)
        applied += 1
    src = src[:a] + block + src[b:]
    starts = {m.group(1): m.start() for m in re.finditer(r'^L\["(\w+)"\] = dict\(', src, re.M)}
    ends = sorted(list(starts.values()) + [src.index("\nBUCKET = ")])
if "--dry-run" not in sys.argv:
    open(SRC, "w").write(src)
print(f"applied {applied}")
for s in skipped: print("skipped", *s)
