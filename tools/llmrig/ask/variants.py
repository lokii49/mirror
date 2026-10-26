#!/usr/bin/env python3
"""Writes each model variant's grammar (RUBRIC.md) next to the dump: <dump>/<qid>_<V>.gbnf for S0-V3.
Options are the app's own option strings from the dump; only the subset changes. S0 is the dumped grammar.
Usage: python3 variants.py <dump dir>"""
import glob, json, os, sys

PREFIX = "The closest things you've written: "
TOP = 8


def literal(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def grammar(options):
    return f'root ::= {literal(PREFIX)} datedq (" " datedq)?\ndatedq ::= ' + " | ".join(map(literal, options))


def option_sets(record):
    seen = [s for s in record["sentences"] if s["inPrompt"]]
    lex = sorted(seen, key=lambda s: -s["lex"])            # stable: ties keep pool order
    sem = sorted(seen, key=lambda s: -s["sem"])
    return {
        "S0": record["s0Options"],
        "V1": [s["option"] for s in seen],
        "V2": [s["option"] for s in lex[:TOP]],
        "V3": [s["option"] for s in sem[:TOP]],
    }


def main():
    dump = sys.argv[1]
    for path in sorted(glob.glob(os.path.join(dump, "*.json"))):
        record = json.load(open(path))
        for name, options in option_sets(record).items():
            if name == "S0":
                # Same escaping as the app's gbnfLiteral: rebuilding S0 must give the dumped grammar byte for byte.
                assert grammar(options) == open(os.path.join(dump, f"{record['qid']}_s0.gbnf")).read(), record["qid"]
            assert options, f"{record['qid']} {name}: no options"
            with open(os.path.join(dump, f"{record['qid']}_{name}.gbnf"), "w") as f:
                f.write(grammar(options))


if __name__ == "__main__":
    main()
