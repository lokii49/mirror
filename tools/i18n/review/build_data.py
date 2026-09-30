#!/usr/bin/env python3
# Builds the native-speaker review page (https://claude.ai/artifact/Kcx8azzKgEv9YcHQKkmi9y) from
# tools/i18n/grounded_locales.py, the source of truth. Row ids are key|variant, as in `--csv`.
# Examples use only the synthetic sickDay fixture sentences from GroundedLocalizedTests.
#   python3 tools/i18n/review/build_data.py > /tmp/data.json, then replace __DATA__ in
#   template.html with that JSON ("</" escaped as "<\\/") and republish to the same URL.
import importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("g", os.path.join(HERE, "..", "grounded_locales.py"))
g = importlib.util.module_from_spec(spec); sys.argv = ["x"]; spec.loader.exec_module(g)
L = g.L
T, S, D, G, N = "tired", "stressed", "sad", "good", "neutral"
MOODS = [T, S, D, G, N]

INSTRUCTION = {"moodWord", "pickFollowUp", "partsLabel", "pickNudge", "pickNeutral", "pickDigest", "pickAsk", "pickMonthly", "entryLabel", "weekLabel", "monthLabel", "entriesLabel", "questionLabel"}
ANCHOR = {"open", "close", "joiner", "youWrote", "energyHard", "energyGood", "becomingSuffix", "releaseFallback", "askPrefix"}
kind = lambda k: "instruction" if k in INSTRUCTION else "anchor" if k in ANCHOR else "user"

GLOSS = {
    "youWrote": "You wrote: ",
    "open": "Opening quotation mark (goes before the writer's own sentence)",
    "close": "Closing quotation mark (goes after the writer's own sentence)",
    "feel": {
        T: ["That sounds like a day that took a lot out of you. Give yourself some rest tonight.", "You seem pretty worn out. A quiet, slow evening might help."],
        S: ["That sounds like a lot at once. Maybe it helps to start with one small thing.", "You seem under pressure. A short break might help you breathe."],
        D: ["That sounds heavy. Be gentle with yourself today.", "You seem low. It's okay to take things slowly."],
        G: ["That sounds like a good moment. Hold on to it.", "You seem lighter. It might be worth noticing what helped."],
        N: ["Glad you wrote it down.", "That's worth noticing."],
    },
    "theme": {T: "A week that took a lot of energy.", S: "A week with a lot of pressure.", D: "A hard week.", G: "A week with good moments.", N: "A week with ups and downs."},
    "energyHard": "It seemed hardest when you wrote: ",
    "energyGood": "It seemed lightest when you wrote: ",
    "buildingSuffix": "There's something to build on here.",
    "watchSuffix": "Keep an eye on this.",
    "boost": {T: "Plan a quiet evening just for yourself.", S: "Pick one small task you can finish today.", D: "Reach out to someone you trust.", G: "Do more of what felt good this week.", N: "Take five minutes for something that feels good."},
    "nextWeek": {T: "Protect your sleep and plan in breaks.", S: "Focus on just one important thing each day.", D: "Be patient with yourself and keep writing down how you feel.", G: "Keep doing what worked.", N: "Notice what gives you energy and what takes it away."},
    "askPrefix": "The closest things you've written:",
    "monthImage": {T: "A candle burning at both ends.", S: "A kettle about to boil.", D: "A grey sky that hasn't cleared yet.", G: "A window opening to the morning light.", N: "Weather that kept changing: sun, then rain, then sun again."},
    "monthTension": {T: "Between everything asking for your energy and the rest you need.", S: "Between what's expected of you and what you can carry.", D: "Between wanting to move on and the time you need to feel it.", G: "Between enjoying the good and wondering whether it will last.", N: "Between the days that drained you and the ones that gave energy back."},
    "monthQuestion": {T: "What could you let go of to have more energy next month?", S: "What one thing could you take off your plate next month?", D: "Who or what could support you a little more next month?", G: "What would help you keep more of this next month?", N: "What gave you energy this month, and how could you make more room for it?"},
    "momentLead": "On {date}, you wrote: ",
    "momentSuffix": "Moments like this say a lot about your month.",
    "becomingSuffix": "You seem to be learning to notice what's good for you.",
    "releaseSuffix": "Maybe it's time to stop holding on to this so tightly.",
    "releaseFallback": "Nothing this month seems to ask to be let go of. Keep noticing what's good for you.",
    "askHint": "If these don't fit, you may not have written about it yet.",
    "followUpQuestion": ["What's underneath {quote}?", "Do you want to write more about {quote}?"],
    "pickFollowUp": "Copy, word for word, the part of the journal entry the person would most want to write more about: a feeling, a worry, or something that happened to them. Output only that part.",
    "partsLabel": "Parts of the entry:",
    "moodWord": {T: "exhausted", S: "stressed", D: "sad", G: "good"},
    "pickNudge": "Copy, word for word, the sentence from the journal entry that best explains why the person felt {mood}. Output only that sentence.",
    "pickNeutral": "Copy, word for word, the sentence from the journal entry that shows the most important thing about the day. Output only that sentence.",
    "pickDigest": "Copy three sentences word for word from the journal entries, each on its own line: first the sentence that shows when the person seemed most exhausted, then a sentence about something good that is growing, then a sentence about something that might be weighing on them. Output only these three sentences.",
    "pickAsk": "Copy, word for word, the one sentence (or at most two) from the journal entries that best answer the question, each on its own line. Output only those sentences.",
    "pickMonthly": "Copy three sentences word for word from the journal entries, each on its own line: first a sentence about a moment that changed something this month, then a hopeful sentence, then a heavy sentence. Output only these three sentences.",
    "entryLabel": "Journal entry:", "weekLabel": "This week's journal entries:", "monthLabel": "This month's journal entries:",
    "entriesLabel": "Journal entries:", "questionLabel": "Question:",
}

# Proposed, not in the app: a fixed hint under every on-device Ask answer (decision 1).
ASK_HINT = {
    "de": "Wenn das nicht passt, hast du vielleicht noch nicht darüber geschrieben.",
    "es": "Si esto no encaja, quizás aún no has escrito sobre ello.",
    "fr": "Si ça ne correspond pas, tu n'as peut-être pas encore écrit à ce sujet.",
    "it": "Se non corrisponde, forse non ne hai ancora scritto.",
    "pt": "Se não for isso, talvez você ainda não tenha escrito sobre o assunto.",
    "ru": "Если это не то, возможно, у тебя ещё нет записей об этом.",
    "ja": "当てはまらない場合は、まだこのことについて書いていないのかもしれません。",
    "ko": "맞는 내용이 없다면, 아직 이 주제로는 쓰지 않았을 수도 있어요.",
    "zh": "如果不太相关，可能你还没有写过这件事。",
}

WHERE = {
    "daily": "Daily reflection",
    "digest": "Weekly digest",
    "monthly": "Monthly report",
    "ask": "Ask",
    "followup": "Follow-up question",
    "proposed": "Proposed, not in the app yet",
    "model": "Read by the AI only",
}
SECTIONS = [
    ("daily", ["youWrote", "open", "close", "feel"]),
    ("digest", ["theme", "energyHard", "energyGood", "buildingSuffix", "watchSuffix", "boost", "nextWeek"]),
    ("monthly", ["monthImage", "monthTension", "momentLead", "momentSuffix", "becomingSuffix", "releaseSuffix", "releaseFallback", "monthQuestion"]),
    ("ask", ["askPrefix"]),
    ("followup", ["followUpQuestion"]),
    ("proposed", ["askHint"]),
    ("model", ["moodWord", "pickNudge", "pickNeutral", "pickDigest", "pickAsk", "pickMonthly", "pickFollowUp", "partsLabel", "entryLabel", "weekLabel", "monthLabel", "entriesLabel", "questionLabel"]),
]
NOTES = {
    "feel": "Also shown on its own, without the quote, on the home-screen widget and in the notification.",
    "youWrote": "Followed directly by the writer's own sentence in quotation marks.",
    "energyHard": "Followed directly by the writer's own sentence in quotation marks.",
    "energyGood": "Followed directly by the writer's own sentence in quotation marks.",
    "momentLead": "{date} becomes a short date like the one in the example. Followed by the writer's sentence in quotation marks.",
    "buildingSuffix": "Comes right after one of the writer's own sentences (quoted).",
    "watchSuffix": "Comes right after one of the writer's own sentences (quoted).",
    "momentSuffix": "Comes right after the quoted sentence.",
    "becomingSuffix": "Comes right after a hopeful sentence the writer wrote (quoted).",
    "releaseSuffix": "Comes right after a heavy sentence the writer wrote (quoted).",
    "releaseFallback": "Shown instead when there's nothing heavy to quote.",
    "askPrefix": "Followed by one or two of the writer's sentences, each on its own line with its date.",
    "askHint": "Would appear under every answer from the on-device AI, because it can't tell for sure whether the question is covered.",
    "followUpQuestion": "Shown while the writer is still typing, under their draft. {quote} becomes one phrase cut from their own draft, in quotation marks (the opening and closing marks above), so the question must read well around any phrase. There are two versions; the app alternates.",
    "partsLabel": "Introduces a numbered list of parts of the draft that the AI chooses from.",
    "moodWord": "Inserted into the instruction below where {mood} is. It describes \"the person\", so it agrees with that noun (feminine in some languages), not with the writer.",
    "pickNudge": "Shown here with the first mood word filled in.",
}

SICK = {
    "de": "Kaum geschlafen, kam gegen 2 von einem späten Konzert zurück und mein Magen war die ganze Nacht schlecht. Um 10 aufgewacht, viel später als sonst. Saß mit Karan auf dem Balkon für ein kurzes Gespräch.",
    "es": "Casi no dormí, volví de un concierto tarde y tuve el estómago mal toda la noche. Me desperté a las 10, mucho más tarde de lo normal. Me senté con Karan en el balcón para charlar un rato.",
    "fr": "J'ai à peine dormi, je suis rentré tard d'un concert et j'ai eu mal au ventre toute la nuit. Je me suis réveillé à 10 heures, bien plus tard que d'habitude. J'ai discuté un moment avec Karan sur le balcon.",
    "it": "Ho dormito pochissimo, sono tornato tardi da un concerto e ho avuto mal di stomaco tutta la notte. Mi sono svegliato alle 10, molto più tardi del solito. Ho chiacchierato un po' con Karan sul balcone.",
    "pt": "Quase não dormi, voltei tarde de um show e fiquei com dor de estômago a noite toda. Acordei às 10, bem mais tarde do que o normal. Conversei um pouco com o Karan na varanda.",
    "ru": "Почти не спал, вернулся поздно с концерта, и всю ночь болел живот. Проснулся в 10, намного позже обычного. Посидел с Караном на балконе, немного поговорили.",
    "ja": "ほとんど眠れなかった。遅いコンサートから帰ってきて、一晩中お腹の調子が悪かった。いつもよりずっと遅い10時に起きた。バルコニーでカランと少し話した。",
    "ko": "거의 잠을 못 잤다. 늦은 콘서트에서 돌아와서 밤새 배가 아팠다. 평소보다 훨씬 늦은 10시에 일어났다. 발코니에서 카란과 잠깐 이야기를 나눴다.",
    "zh": "几乎没睡，听完晚场音乐会很晚才回来，整晚肚子都不舒服。比平时晚很多，十点才醒。和卡兰在阳台上聊了一会儿。",
}
# Real DateFormatter output for template "d MMM" on 12 Sep 2026 (swift, see dates.swift).
DATE = {"de": "12. Sept.", "es": "12 sept", "fr": "12 sept.", "it": "12 set", "pt": "12 de set.", "ru": "12 сент.", "ja": "9月12日", "ko": "9월 12일", "zh": "9月12日"}
QUESTION = {"de": "Wie habe ich in letzter Zeit geschlafen?", "es": "¿Cómo he dormido últimamente?", "fr": "Comment j'ai dormi ces derniers temps ?",
            "it": "Come ho dormito ultimamente?", "pt": "Como tenho dormido ultimamente?", "ru": "Как мне спалось в последнее время?",
            "ja": "最近よく眠れてる？", "ko": "요즘 잠은 잘 자고 있어?", "zh": "我最近睡得怎么样？"}

LANGS = {
    "de": {"name": "Deutsch", "english": "German", "variant": "Standard German.",
           "register": {"current": "du", "other": "Sie", "context": "The AI lines say du. The rest of the app's German is informal too."}},
    "es": {"name": "Español", "english": "Spanish", "variant": "Neutral Spanish that should read fine in Spain and Latin America, with tú (no vos).",
           "register": {"current": "tú", "other": "usted", "context": "The AI lines say tú."}},
    "fr": {"name": "Français", "english": "French", "variant": "France French, with « » quotes and a non-breaking space before : ; ? !",
           "register": {"current": "tu", "other": "vous", "context": "The AI lines say tu, like the app's other AI replies. The app's buttons and menus say vous. So one screen can show a vous button above a tu reflection."}},
    "it": {"name": "Italiano", "english": "Italian", "variant": "Standard Italian.",
           "register": {"current": "tu", "other": "Lei", "context": "The AI lines say tu."}},
    "pt": {"name": "Português (Brasil)", "english": "Portuguese (Brazil)", "variant": "Brazilian Portuguese, with você.",
           "register": {"current": "você", "other": "o senhor / a senhora", "context": "The AI lines say você."}},
    "ru": {"name": "Русский", "english": "Russian", "variant": "Standard Russian.",
           "register": {"current": "ты", "other": "вы", "context": "The AI lines say ты, like the app's other AI replies. The app's buttons and menus say вы. So one screen can show a вы button above a ты reflection."}},
    "ja": {"name": "日本語", "english": "Japanese", "variant": "Standard Japanese.",
           "register": {"current": "polite です・ます", "other": "casual (plain form)", "context": "The AI lines use polite です・ます and call the writer あなた."}},
    "ko": {"name": "한국어", "english": "Korean", "variant": "Standard Korean.",
           "register": {"current": "polite 해요체", "other": "casual 반말, or formal 합쇼체", "context": "The AI lines use 해요체."}},
    "zh": {"name": "中文（简体）", "english": "Chinese (Simplified)", "variant": "Simplified Chinese (Mainland).",
           "register": {"current": "你", "other": "您", "context": "The AI lines say 你."}},
}

def sentences(code, text):
    if code in ("ja", "zh"):
        return [s for s in re.split(r"(?<=[。！？])", text) if s]
    return [s for s in re.split(r"(?<=[.!?])\s+", text) if s]

def rows_for(code):
    d = dict(L[code]); d["askHint"] = ASK_HINT[code]
    rows = []
    for section, keys in SECTIONS:
        for k in keys:
            v = d[k]
            base = {"key": k, "section": section, "kind": "proposed" if k == "askHint" else kind(k), "note": NOTES.get(k, "")}
            if isinstance(v, dict):
                for mood in (MOODS if k != "moodWord" else [T, S, D, G]):
                    x = v[mood]
                    if isinstance(x, list):
                        for i, t in enumerate(x):
                            rows.append({**base, "variant": f"{mood}/{i+1}", "mood": mood, "text": t, "gloss": GLOSS[k][mood][i]})
                    else:
                        rows.append({**base, "variant": mood, "mood": mood, "text": x, "gloss": GLOSS[k][mood]})
            elif isinstance(v, list):
                for i, t in enumerate(v):
                    rows.append({**base, "variant": f"q/{i+1}", "mood": "", "text": t, "gloss": GLOSS[k][i]})
            else:
                text = v.replace("{mood}", d["moodWord"][T]) if k == "pickNudge" else v
                gloss = GLOSS[k].replace("{mood}", GLOSS["moodWord"][T]) if k == "pickNudge" else GLOSS[k]
                rows.append({**base, "variant": "", "mood": "", "text": text, "gloss": gloss})
    return rows

def examples_for(code):
    d = L[code]; o, c, j = d["open"], d["close"], d["joiner"]
    s = sentences(code, SICK[code])
    if len(s) == 4:   # ja, ko: first sentence is short; use the three that carry the day
        hard, watch, good = s[1], s[2], s[3]
    else:
        hard, watch, good = s[0], s[1], s[2]
    q = lambda x: {"quote": x}
    t = lambda x: {"text": x}
    date = DATE[code]
    return {
        "entry": SICK[code],
        "nudge": [t(d["youWrote"] + o), q(hard), t(c + j + d["feel"][T][0])],
        "widget": d["feel"][T][0],
        "digest": [
            ["This week's theme", [t(d["theme"][T])]],
            ["Your energy", [t(d["energyHard"] + o), q(hard), t(c)]],
            ["What's building", [t(o), q(good), t(c + j + d["buildingSuffix"])]],
            ["Watch out for", [t(o), q(watch), t(c + j + d["watchSuffix"])]],
            ["Mood boost", [t(d["boost"][T])]],
            ["Next week", [t(d["nextWeek"][T])]],
        ],
        "monthly": [
            ["Your month in one image", [t(d["monthImage"][T])]],
            ["The tension at the center", [t(d["monthTension"][T])]],
            ["A moment that shifted something", [t(d["momentLead"].replace("{date}", date) + o), q(hard), t(c + j + d["momentSuffix"])]],
            ["What you're becoming", [t(o), q(good), t(c + j + d["becomingSuffix"])]],
            ["What wants to be released", [t(o), q(watch), t(c + j + d["releaseSuffix"])]],
            ["Your question for next month", [t(d["monthQuestion"][T])]],
        ],
        "question": QUESTION[code],
        "followup": [[t(tpl.split("{quote}")[0] + o), q(hard), t(c + tpl.split("{quote}")[1])] for tpl in d["followUpQuestion"]],
        "ask": [[t(d["askPrefix"])], [t(f"{date} – {o}"), q(hard), t(c)], [t(f"{date} – {o}"), q(watch), t(c)]],
        "askHint": ASK_HINT[code],
    }

data = {"languages": [{"code": c, **LANGS[c], "rows": rows_for(c), "examples": examples_for(c)} for c in L], "where": WHERE}
for lang in data["languages"]:
    assert all(r["gloss"] for r in lang["rows"]), lang["code"]
    ids = [r["key"] + "|" + r["variant"] for r in lang["rows"]]
    assert len(ids) == len(set(ids)), lang["code"]
print(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
