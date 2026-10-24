#!/usr/bin/env python3
"""Builds out/pool.jsonl for the Gemma Ask pick round (RUBRIC.md): the English targets of
../retrieval/cases/targets.tsv, each wrapped in neutral filler sentences, plus filler entries of
4-7 neutral sentences. Every line: id, text, original (the target's own text, "" for filler), date.
--heldout: round 2's cases/heldout_targets.tsv into out/heldout_pool.jsonl, with its own seed."""
import csv, datetime, importlib.util, json, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RETRIEVAL = os.path.join(HERE, "..", "retrieval")
spec = importlib.util.spec_from_file_location("build_corpus", os.path.join(RETRIEVAL, "build_corpus.py"))
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)

FILLER_ENTRIES = 220
BASE = datetime.datetime(2026, 4, 11, 8, 0)
DAYS = 180


def main():
    heldout = "--heldout" in sys.argv
    rng = random.Random(20261024 if heldout else 20261023)
    source = os.path.join(HERE, "cases", "heldout_targets.tsv") if heldout else os.path.join(RETRIEVAL, "cases", "targets.tsv")
    with open(source, newline="") as f:
        targets = [r for r in csv.DictReader(f, delimiter="\t") if r["lang"] == "en"]
    sentences = list(bc.FILLER_EN)

    def when():
        return (BASE + datetime.timedelta(days=rng.randrange(DAYS), minutes=rng.randrange(14 * 60))).isoformat()

    rows = []
    for t in targets:
        before = rng.sample(sentences, rng.randrange(0, 3))
        after = rng.sample([s for s in sentences if s not in before], rng.randrange(1, 4))
        rows.append({"id": t["id"], "text": " ".join(before + [t["text"]] + after), "original": t["text"], "date": when()})
    for i in range(FILLER_ENTRIES):
        rows.append({"id": f"f{i}", "text": " ".join(rng.sample(sentences, rng.randrange(4, 8))), "original": "", "date": when()})
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    with open(os.path.join(HERE, "out", "heldout_pool.jsonl" if heldout else "pool.jsonl"), "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    lengths = [len(r["text"]) for r in rows]
    print(f"{len(rows)} entries ({len(targets)} targets), mean {sum(lengths) / len(lengths):.0f} chars")


if __name__ == "__main__":
    main()
