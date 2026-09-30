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

# The follow-up chip strings live in their own FOLLOW_UP dict, not in the L["xx"] blocks.
FOLLOW_UP_KEYS = {"pickFollowUp", "partsLabel", "followUpQuestion"}

def follow_up_region(src, code):
    """(start, end) of code's `"xx": dict(...)` entry inside FOLLOW_UP."""
    top = src.index("\nFOLLOW_UP = {")
    close = src.index("\n}\n", top)
    entries = {m.group(1): m.start() for m in re.finditer(r'^    "(\w+)": dict\(', src[top:close], re.M)}
    a = top + entries[code]
    later = [top + o for o in entries.values() if top + o > a]
    return a, min(later + [close])

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
        if key in FOLLOW_UP_KEYS:
            fa, fb = follow_up_region(src[:a] + block + src[b:], code)
            whole = src[:a] + block + src[b:]
            region = whole[fa:fb]
            n = region.count(old)
            if n != 1:
                sys.exit(f"{code} {ch['id']}: original found {n} times in the {code} FOLLOW_UP entry — stale, ambiguous, or an f-string (edit by hand) — nothing written")
            whole = whole[:fa] + region.replace(old, new) + whole[fb:]
            # Re-split so the L block boundaries stay consistent for later changes.
            src = whole
            starts = {m.group(1): m.start() for m in re.finditer(r'^L\["(\w+)"\] = dict\(', src, re.M)}
            ends = sorted(list(starts.values()) + [src.index("\nBUCKET = ")])
            a = starts[code]; b = min(e for e in ends if e > a)
            block = src[a:b]
            applied += 1
            continue
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
