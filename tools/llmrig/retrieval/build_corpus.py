#!/usr/bin/env python3
"""Builds corpus_<n>.jsonl (n = 0, 150, 400 filler entries) from cases/targets.tsv plus seeded filler.
Filler is neutral everyday text that avoids every question topic in cases/queries.tsv. Some lines are
keyword traps: they contain a question keyword as a substring of an unrelated word ("carpet" ⊃ "pet",
"velvet" ⊃ "vet", "post office", "coffee table"). Every smaller corpus is a prefix of the larger one.
Usage: python3 build_corpus.py [trap_cap]   (writes into ./out, or ./out/cap<N> with a cap)
       python3 build_corpus.py --lang de [impersonal]
           monolingual set from cases/de/: out/de/corpus_{0,150,300}.jsonl + queries.tsv, filler from
           cases/de/filler.txt (first person, like the targets). With "impersonal": filler_impersonal.txt
           into out/de-impersonal/ (the first run's filler; fewer pronouns than the targets).
trap_cap limits how many filler entries may use each trap line. Uncapped, each trap appears ~20
times in 400 filler entries, far denser than a real journal; cap 2 is the realistic comparison."""
import csv, datetime, json, os, random, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
BASE = datetime.datetime(2026, 4, 11, 8, 0)
DAYS = 180

FILLER_EN = [
    "Grey and drizzly all day.",
    "Windy enough that the bins blew over.",
    "First frost on the car windows this morning.",
    "Hot and sticky, every window open.",
    "Fog so thick I couldn't see the end of the street.",
    "Picked up a parcel from the post office, the queue went round the corner.",
    "Ran errands: dry cleaning, stamps, batteries.",
    "Returned the wrong-size curtains.",
    "Got a key cut for the shed.",
    "Booked a haircut for next Thursday.",
    "Did two loads of laundry.",
    "Defrosted the freezer, finally.",
    "Removed the old shelf in the hallway.",
    "Vacuumed the carpet and the stairs.",
    "The washing machine is working again after the repair.",
    "Fixed the squeaky hinge on the cupboard.",
    "The bus didn't move for ten minutes at the roundabout.",
    "Train was on time for once.",
    "Roadworks on the high street again.",
    "Switched to the current timetable, the 7:12 is gone now.",
    "Watched two episodes of a cooking show, then turned off the lights.",
    "Listened to a radio interview about old bridges.",
    "Caught the end of a documentary about power plants.",
    "Put the headphones on for the walk back from the shop.",
    "The neighbors put up a new fence.",
    "A velvet armchair was left out on the pavement.",
    "Parents at the school gate were talking about the summer fete.",
    "Someone was burning leaves two gardens over.",
    "The plumber did a decent job on the kitchen sink.",
    "The old gym building on the corner is being knocked down.",
    "The bakery window had a huge wedding cake on display, quite a presentation.",
    "Changed the position of the sofa so the lamp reaches.",
    "Assembled a flat-pack coffee table.",
    "The cat next door was sleeping on our wall again.",
    "Found an old homework book from school in the attic.",
    "Replaced the batteries in the smoke alarm.",
    "Sorted the recycling into the new bins.",
    "The streetlight outside has been flickering all week.",
    "Took the car for its yearly service.",
    "A delivery van blocked the road for most of the morning.",
]
# Lines that contain a question keyword inside an unrelated word or sense.
TRAPS = {
    "Picked up a parcel from the post office, the queue went round the corner.",
    "Booked a haircut for next Thursday.",
    "Removed the old shelf in the hallway.",
    "Vacuumed the carpet and the stairs.",
    "The washing machine is working again after the repair.",
    "The bus didn't move for ten minutes at the roundabout.",
    "Switched to the current timetable, the 7:12 is gone now.",
    "Watched two episodes of a cooking show, then turned off the lights.",
    "Listened to a radio interview about old bridges.",
    "Caught the end of a documentary about power plants.",
    "Put the headphones on for the walk back from the shop.",
    "A velvet armchair was left out on the pavement.",
    "Parents at the school gate were talking about the summer fete.",
    "Someone was burning leaves two gardens over.",
    "The plumber did a decent job on the kitchen sink.",
    "The old gym building on the corner is being knocked down.",
    "The bakery window had a huge wedding cake on display, quite a presentation.",
    "Changed the position of the sofa so the lamp reaches.",
    "Assembled a flat-pack coffee table.",
    "The cat next door was sleeping on our wall again.",
    "Found an old homework book from school in the attic.",
}
FLAT_EN = ["Nothing much to report.", "An ordinary day.", "Quiet day, mostly admin.", "That was about it."]
FILLER_OTHER = {
    "de": ["Der Zug hatte zehn Minuten Verspätung.", "Ich habe Wäsche gewaschen und aufgehängt.",
           "Es hat den ganzen Nachmittag geregnet.", "Im Treppenhaus wird gestrichen."],
    "es": ["El autobús llegó tarde otra vez.", "Hice la colada y limpié el baño.",
           "Hoy hizo mucho viento.", "Pintaron la fachada del edificio de enfrente."],
    "fr": ["Le bus était en retard ce matin.", "J'ai fait deux machines de linge.",
           "Il y avait du vent toute la journée.", "Les voisins ont repeint leur porte."],
    "ja": ["電車が十分遅れた。", "洗濯物を二回干した。", "一日中風が強かった。", "隣の家が塀を直していた。"],
    "pt": ["O ônibus atrasou de novo.", "Lavei roupa e limpei o banheiro.", "Ventou muito o dia todo."],
}


def when(rng):
    return BASE + datetime.timedelta(days=rng.randrange(DAYS), minutes=rng.randrange(14 * 60))


def targets(case_dir=os.path.join(HERE, "cases")):
    rng = random.Random(7)
    with open(os.path.join(case_dir, "targets.tsv"), encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    return [{"id": r["id"], "lang": r["lang"], "tags": [t for t in r["tags"].split(",") if t],
             "text": r["text"], "date": when(rng).isoformat(), "filler": False} for r in rows]


def filler(n, trap_cap=None):
    rng = random.Random(11)
    seen, out, used = set(), [], {}
    while len(out) < n:
        if rng.random() < 0.12:
            lang = rng.choice(sorted(FILLER_OTHER))
            text = " ".join(rng.sample(FILLER_OTHER[lang], 2))
        else:
            lang = "en"
            parts = rng.sample(FILLER_EN, rng.choice([1, 2, 2, 3]))
            if rng.random() < 0.3:
                parts.append(rng.choice(FLAT_EN))
            text = " ".join(parts)
        if text in seen:
            continue
        if trap_cap is not None and lang == "en":
            traps = [p for p in parts if p in TRAPS]
            if any(used.get(p, 0) >= trap_cap for p in traps):
                continue
            for p in traps:
                used[p] = used.get(p, 0) + 1
        seen.add(text)
        out.append({"id": f"f{len(out):03d}", "lang": lang, "tags": [], "text": text,
                    "date": when(rng).isoformat(), "filler": True})
    return out


def lang_filler(lang, n, variant=None):
    name = f"filler_{variant}.txt" if variant else "filler.txt"
    pool = [l.strip() for l in open(os.path.join(HERE, "cases", lang, name), encoding="utf-8") if l.strip()]
    rng = random.Random(11)
    seen, out = set(), []
    while len(out) < n:
        text = ("" if lang == "ja" else " ").join(rng.sample(pool, rng.choice([1, 2, 2, 3])))
        if text in seen:
            continue
        seen.add(text)
        out.append({"id": f"f{len(out):03d}", "lang": lang, "tags": [], "text": text,
                    "date": when(rng).isoformat(), "filler": True})
    return out


def main_lang(lang, variant=None):
    case_dir = os.path.join(HERE, "cases", lang)
    out_dir = os.path.join(OUT, f"{lang}-{variant}" if variant else lang)
    os.makedirs(out_dir, exist_ok=True)
    shutil.copy(os.path.join(case_dir, "queries.tsv"), os.path.join(out_dir, "queries.tsv"))
    t, fill = targets(case_dir), lang_filler(lang, 300, variant)
    for n in (0, 150, 300):
        with open(os.path.join(out_dir, f"corpus_{n}.jsonl"), "w", encoding="utf-8") as f:
            for e in t + fill[:n]:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"{os.path.relpath(out_dir, HERE)}/corpus_{n}.jsonl: {len(t) + n} entries")


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--lang":
        return main_lang(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    cap = int(sys.argv[1]) if len(sys.argv) > 1 else None
    out_dir = OUT if cap is None else os.path.join(OUT, f"cap{cap}")
    os.makedirs(out_dir, exist_ok=True)
    t, fill = targets(), filler(400, cap)
    for n in (0, 150, 400):
        with open(os.path.join(out_dir, f"corpus_{n}.jsonl"), "w", encoding="utf-8") as f:
            for e in t + fill[:n]:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")
        print(f"{os.path.relpath(out_dir, HERE)}/corpus_{n}.jsonl: {len(t) + n} entries")


if __name__ == "__main__":
    main()
