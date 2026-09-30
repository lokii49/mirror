#!/usr/bin/env python3
# Markdown version of the native-speaker review page, for pasting into another LLM or sending to a
# translator. Same data and row ids (key|variant, as in grounded_locales.py --csv) as the page.
#   python3 tools/i18n/review/build_md.py > ~/Downloads/mirror-translation-review.md
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
data = json.loads(subprocess.run([sys.executable, os.path.join(HERE, "build_data.py")], check=True, capture_output=True, text=True).stdout)

MOOD = {"tired": "drained", "stressed": "under pressure", "sad": "low", "good": "a good day", "neutral": "mixed or unclear"}
KIND = {
    "user": "shown to users — improve freely",
    "anchor": "shown to users — change only if needed (after release the app must keep recognizing the old wording)",
    "instruction": "read by the AI only — flag only if the meaning is wrong",
    "proposed": "proposed, not in the app yet",
}
INTRO = {
    "daily": "After an entry is saved, the app quotes one sentence from it and adds one short line. That line depends on the entry's mood. There are two versions per mood; the app rotates between them.",
    "digest": "Once a week, in six short sections. Three of them quote the writer.",
    "monthly": "Once a month, in six short sections.",
    "ask": "The writer asks a question about their journal. The app shows the closest sentences they wrote.",
    "followup": "While the writer is still typing, the app can show one question under their draft, built around one phrase cut from their own words.",
    "proposed": "Not in the app yet. It may be added under every Ask answer, because the on-device AI can't tell for sure whether a question is covered.",
    "model": "Optional. These tell a small (1B) on-device model which sentence to copy. Users never see them. Flag a line only if its meaning is wrong or confusing; keep any fix plain and literal. Don't polish the style.",
}

def seg(parts):
    return "".join(f"**{p['quote']}**" if "quote" in p else p["text"] for p in parts)

out = []
w = out.append
w("# mirror: translation review\n")
w("Interactive version: https://claude.ai/artifact/Kcx8azzKgEv9YcHQKkmi9y\n")
w("**How to use this file:** paste the *Instructions* section plus one language section into a model that is strong in that language (or send it to a native speaker). Ask it to review that language and reply in the format under *What to return*. Paste the reply back to Claude Code to apply it. All example journal text here is made up.\n")
w("---\n")
w("## Instructions for the reviewer\n")
w("""You are reviewing the fixed text of **mirror**, a private journaling app for iPhone. Its on-device AI never writes free text in these languages. It only picks one or more of the writer's own sentences, and the app wraps them in the fixed lines below. For example, a daily reflection is: *"You wrote: "<writer's sentence>" That sounds like a day that took a lot out of you."*

These fixed lines were translated from English without a native speaker. Check whether each one is **natural, warm, grammatical and correct** for a native reader.

**The voice:** a close, kind friend. Not a therapist, doctor, coach or customer-service agent. Short, gentle, never preachy.

**Rules:**
1. The writer's own words are shown in **bold** in the examples. Don't review them. The fixed lines must read well before or after *any* sentence the writer might have written.
2. The mood lines (`feel|…`) are also shown **on their own**, without the quote, on the home-screen widget and in the notification. They must make sense standalone.
3. The app doesn't know the writer's gender. No line may assume one.
4. Keep the placeholders `{date}`, `{mood}` and `{quote}` exactly as they are.
5. A natural phrasing matters more than a word-for-word match with the English meaning. But keep each line's intent and roughly its length.
6. Lines marked **change only if needed** are detection anchors: after release, the app recognizes saved reflections by this exact text. Suggest a change only if the line is actually wrong or unnatural, not to polish it.
7. Lines marked **read by the AI only** are instructions for a small (1B) on-device model. Flag only real meaning errors. Keep fixes simple and literal.
8. Quotation marks and spacing follow each language's own conventions. French uses « » with a non-breaking space inside them and before : ; ? !
9. Answer the questions at the end of your language's section.

### What to return

Reply with **one JSON block per language** in exactly this shape. Any line you don't list under `changes` counts as fine.

```json
{
  "mirrorTranslationReview": 1,
  "language": "fr",
  "reviewer": "<your name or model name>",
  "answers": {
    "register": "keep | switch | either",
    "registerNote": "",
    "gender": "no | yes",
    "genderNote": "",
    "ruForm": "keep | neutral   (Russian only)",
    "regional": "",
    "overall": 4,
    "comment": ""
  },
  "changes": [
    {
      "id": "feel|tired/1",
      "original": "<the line exactly as given>",
      "suggestion": "<your wording>",
      "why": "<short reason>"
    }
  ]
}
```

`overall` goes from 1 (clearly translated) to 5 (reads like a native writer).
""")
w("---\n")

for lang in data["languages"]:
    code, ex = lang["code"], lang["examples"]
    reg = lang["register"]
    w(f"## {code}: {lang['name']} ({lang['english']})\n")
    w(f"**Written for:** {lang['variant']}  ")
    w(f"**Form of address:** {reg['context']}\n")

    w(f"### {code}: how it looks in the app\n")
    w("Made-up journal entry used in the examples:\n")
    w(f"> {ex['entry']}\n")
    w("**Daily reflection**\n")
    w(f"> {seg(ex['nudge'])}\n")
    w("**Home-screen widget and notification** (same line, no quote)\n")
    w(f"> {ex['widget']}\n")
    w("**Weekly digest** (section titles are translated separately; shown in English here)\n")
    for title, parts in ex["digest"]:
        w(f"> *{title}:* {seg(parts)}  ")
    w("")
    w("**Monthly report**\n")
    for title, parts in ex["monthly"]:
        w(f"> *{title}:* {seg(parts)}  ")
    w("")
    w(f"**Ask** — question: *{ex['question']}*\n")
    for line in ex["ask"]:
        w(f"> {seg(line)}  ")
    w(f">\n> *(proposed line under every answer)* {ex['askHint']}\n")
    w("**Follow-up question** (two versions; the app alternates)\n")
    for line in ex["followup"]:
        w(f"> {seg(line)}  ")
    w("")

    w(f"### {code}: lines to review\n")
    sections = []
    for r in lang["rows"]:
        if not sections or sections[-1][0] != r["section"]:
            sections.append((r["section"], []))
        sections[-1][1].append(r)
    for sec, rows in sections:
        if sec == "model":
            w(f"### {code}: optional — instructions the AI reads\n")
        else:
            w(f"#### {data['where'][sec]}\n")
        w(f"{INTRO[sec]}\n")
        for r in rows:
            rid = r["key"] + "|" + r["variant"]
            tags = [KIND[r["kind"]]]
            if r["mood"]:
                tags.insert(0, "mood: " + MOOD[r["mood"]])
            if r["variant"][-2:-1] == "/":
                tags.insert(1, f"version {r['variant'][-1]} of 2")
            w(f"- `{rid}` — {'; '.join(tags)}")
            w(f"  - **Text:** {r['text']}")
            w(f"  - **Meaning:** {r['gloss']}")
            if r["note"]:
                w(f"  - **Note:** {r['note']}")
        w("")

    w(f"### {code}: questions\n")
    w(f"1. **Form of address.** {reg['context']} The voice is meant to feel like a close, kind friend. Keep {reg['current']}, switch to {reg['other']}, or either is fine? (`register`, optional `registerNote`)")
    w("2. **Gender.** The app doesn't know whether the writer is a man, a woman, or neither. Does any line assume one? Which lines, and how would you fix them? (`gender`, `genderNote`)")
    if code == "ru":
        w("   - To avoid guessing, the Russian lines say «Ты написал(а):». A gender-free wording could be «Ты пишешь:» or «Из твоей записи:». Keep «написал(а)» or use a gender-free wording? Write your wording in `genderNote`. (`ruForm`)")
    w(f"3. **Region and style.** Written for: {lang['variant']} Anything that sounds regional, dated, stiff or machine-translated? (`regional`)")
    w("4. **Overall.** How natural does it sound, from 1 (clearly translated) to 5 (like a native writer)? Anything else? (`overall`, `comment`)\n")
    w("---\n")

print("\n".join(out))
