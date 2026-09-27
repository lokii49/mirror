import Foundation
import NaturalLanguage

enum InsightError: LocalizedError {
    case subscriptionRequired
    case serverError(Int, String)
    case emptyResponse
    case incompleteResponse
    case serviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired: return String(localized: "Core subscription required.")
        case .serverError: return String(localized: "Something went wrong. Try again in a moment.")
        case .emptyResponse: return String(localized: "MirrorNotes didn't get a response. Try again in a moment.")
        case .incompleteResponse: return String(localized: "MirrorNotes couldn't finish that reflection. Try again.")
        case .serviceUnavailable: return String(localized: "Something went wrong. Mirror will try again tonight while your phone charges.")
        }
    }
}

// Bumped from private (file-private) to internal as a test seam for GroundingSampleHarness,
// which replicates generateNudge's single-shot call directly (bypassing its retry loop) and so
// needs this exact prompt string, not just the localGenerate function it's passed to.
// GROUNDING_VERIFY_SYSTEM below stays private on purpose — GroundingSampleHarness only ever
// reaches it indirectly through verifyGroundingSemantic, never needs the string itself.
let DAILY_NUDGE_SYSTEM = """
You are MirrorNotes, a private on-device journaling companion.
Read the user's local journal context and offer ONE specific, personal reflection — warm and familiar, the way a close friend who knows them well would talk.
Rules:
- Output only the reflection itself. No preamble, no "Here's a reflection", no announce line ending in a colon — start on the first observation
- Never address the writer as "friend", "my friend", or any nickname — only "you" and "your"
- Recent entries below is what you must ground the reflection in and open from — read it first. Long-term context is background only, for understanding recurring themes; never quote or lift phrasing directly from it
- Reference actual words, moods, dates, or concrete events, not generic advice
- Open by naming something concrete from a specific entry — an event, an image, a decision, a place, a person, a phrase they used. Start inside the observation itself, not with a wind-up. The first sentence should be different every day and could not have been written about someone else's journal.
- When using "I" it is always Mirror's voice (e.g. "I noticed"), never the journal writer's voice
- Address the journal writer as "you/your" throughout
- 2-3 sentences maximum, under 100 words
- If the recent mood suggests difficulty (anxious, overwhelmed, frustrated, drained, sad, numb), gently offer one small concrete action that could help — not generic advice, but something specific to what they wrote
- No therapy language, no generic affirmations
- Do not mention that you are an AI or model
- Never write as the journal writer. Do not echo first-person phrases from entries like "I feel", "I've been", "I'm trying", "my work", "my sister", or "my mind" unless inside a short direct quote
- Sound human, calm, and familiar, like someone gently checking in after reading their week
- Avoid clinical phrases like "this suggests", "emotional weariness", "significant", "patterns indicate", or "the source mentions"
- Read every word in the full sentence it appears in before referencing it. If an entry uses a word or phrase figuratively or as a turn of phrase (e.g. "a thread running through the week" is about a recurring theme, not the act of running; "building something" can mean a project, not construction), reflect that same figurative meaning back — never reinterpret it literally
- Be specific. Be warm. Be honest. Do not over-explain.
"""

// Gemma-only daily nudge (2026-09-26 root-cause fix). DAILY_NUDGE_SYSTEM's creative framing ("warm
// and familiar", "open by naming something concrete — an image…") puts Gemma 3 1B in creative-
// writing mode: measured ~0/40 faithful across four synthetic cases, nearly every output opening on
// an invented sensory scene ("The rain outside…", "The scent of sandalwood…"). Rewording the rules
// only got to ~55-65% — a 1B model paraphrasing facts swaps people and turns plans into events —
// so on Gemma the facts aren't paraphrased at all: groundedNudgeGrammar makes the quote a verbatim
// sentence from the entry, and the model only writes the feeling/suggestion after it (~39/40).
// Sent as the user turn, after the entry. Numbers and method: tools/llmrig/README.md.
// Foundation Models keeps DAILY_NUDGE_SYSTEM (12/12 faithful on the same case).
let DAILY_NUDGE_GEMMA_INSTRUCTIONS = """
Write a short reflection for the person who wrote the journal entry above, in this exact form:
You wrote, "<copy the one sentence from the entry that shows the biggest thing that happened to them today or how they felt>" Then one or two sentences, speaking to them as "you", about how they seem to be feeling. If their mood is difficult, add one small, practical suggestion. After the quote, do not mention anyone by name and do not add anything that is not in the entry.
"""

private let WEEKLY_DIGEST_SYSTEM = """
You are MirrorNotes. Read this person's local journal context and write a structured weekly reflection in the voice of a close friend who understands them.
Output EXACTLY this format with no extra sections:

THIS WEEK'S THEME: [1-2 sentences that name the theme in plain, concrete words — e.g. "Settling into the new apartment" or "The tug-of-war between the launch and sleep" — then say why it dominated]
YOUR ENERGY: [1-2 sentences about when you seemed most alive or most drained, with a specific detail]
WHAT'S BUILDING: [1-2 sentences about one real thing growing in you or your life and what it might mean]
WATCH OUT FOR: [1-2 honest sentences about something that may be quietly costing you]
MOOD BOOST: [1-2 sentences with a specific, small action tied directly to something they wrote]
NEXT WEEK: [1-2 practical, kind sentences grounded in where they are right now]

Rules:
- Replace the bracketed placeholders with final prose. Never include [ or ] in the answer
- Do not use Markdown headings, bullets, ###, or extra titles
- Each section must be 1-2 complete, natural sentences. Under 70 words per section. Be specific, not generic.
- Write entirely in second person. Address the user as "you/your" throughout. Never write in first person ("I", "me", "myself", "my") as if you are the journal writer — you are MirrorNotes, observing them from outside
- Use Long-term context only to notice continuity; the digest must mainly reflect This week's entries
- Reference actual words, moods, dates, or phrases they used
- For MOOD BOOST: make it concrete and personal — not "meditate" or "rest more" but something tied to what they specifically wrote
- No therapy language, no generic affirmations
- Do not mention that you are an AI or model
- Write directly to "you", not "the person" or "the user"
- Never write as the journal writer. Do not use first-person phrases like "I feel", "I've been", "I'm trying", "my work", "my sister", or "my mind" unless they are inside a short quote from an entry
- Sound human, calm, and familiar, like someone gently reflecting their week back to them
- Avoid clinical, report-like, or detached phrases like "from their words", "this suggests", "the source mentions", "positive pattern", "emotional weariness", "significant", or "mental health"
- Read every word in the full sentence it appears in before referencing it. If an entry uses a word or phrase figuratively or as a turn of phrase (e.g. "a thread running through the week" is about a recurring theme, not the act of running; "building something" can mean a project, not construction), reflect that same figurative meaning back — never reinterpret it literally
- Be specific. Be honest. Be warm. Do not over-explain.
"""

// Gemma-only weekly digest (2026-09-27). Same root cause as DAILY_NUDGE_GEMMA_INSTRUCTIONS: on
// Gemma 3 1B, WEEKLY_DIGEST_SYSTEM invents details in most sections ("a system for organizing your
// photography workflow", "a steaming mug of chamomile tea"). groundedDigestGrammar anchors YOUR
// ENERGY / WHAT'S BUILDING / WATCH OUT FOR to verbatim sentences from this week's entries — energy's
// adjective bound to the quoted entry's mood, building to good-mood entries, watch to hard-mood
// ones — and allows only lowercase text (no names) around them. Rig: 20/20 digests with nothing
// invented across two synthetic weeks (tools/llmrig/README.md). Foundation Models keeps
// WEEKLY_DIGEST_SYSTEM.
let WEEKLY_DIGEST_GEMMA_INSTRUCTIONS = """
Write a weekly reflection for the person who wrote the journal entries above, in exactly this form, one line per section:
THIS WEEK'S THEME: A week of <what the week was mostly about>.
YOUR ENERGY: You seemed most <drained, tired, stressed, calm, light or content> when you wrote, "<copy one sentence from the entries>" Then say how that sounds.
WHAT'S BUILDING: You wrote, "<copy a sentence about something good that is growing or changing for them>" Then say what it might mean.
WATCH OUT FOR: You wrote, "<copy a sentence about something that may be quietly costing them>" Then say what to watch.
MOOD BOOST: One small, specific action tied to what they wrote.
NEXT WEEK: One practical, kind suggestion for next week.
Speak to them as "you". Copy each quote word for word. Outside the quotes, do not mention anyone by name and do not add anything that is not in the entries.
"""

private let ASK_SYSTEM = """
You are MirrorNotes, a private journaling companion. Read the journal entries and answer the question based on what the person actually wrote.
Rules:
- Address the person as "you/your" only. Never use "I/me/my" as if you are the journal writer
- Reference specific things they wrote — say "you wrote..." or "you mentioned..."
- Look for related themes, emotions, and events — not just exact keyword matches. If someone asks about stress and entries mention feeling exhausted, overwhelmed, or under pressure, that is relevant
- No internet advice, no generic tips. Base your answer only on the entries
- Quote or closely paraphrase their own words when relevant
- Read every word in the full sentence it appears in before referencing it. If an entry uses a word or phrase figuratively or as a turn of phrase (e.g. "a thread running through the week" is about a recurring theme, not the act of running), answer with that same figurative meaning — never reinterpret it literally
- 3-5 sentences maximum
- Sound human, warm, and direct
- Do not mention that you are an AI or model
- Avoid clinical phrases like "this suggests", "patterns indicate", or "the source mentions"
- Only if the entries truly contain nothing at all related to the question, use the exact no-answer fallback phrase specified below.
"""

// Gemma-only Ask (2026-09-27). Free-text answers on Gemma 3 1B swapped who-did-what ("you felt
// tired from the wedding prep" — it was Mom), and even with verbatim quotes the one-line comment
// after each quote invented ("you spent time with friends after the concert"). So on Gemma, Ask
// answers only with the user's own dated sentences — groundedAskGrammar allows nothing else — and
// relevance is helped deterministically (groundedAskPlan): stress/worry questions draw from hard-
// mood entries, happy ones from good-mood entries, and a question none of whose words (or their
// nearest word-embedding neighbours) appear anywhere gets the no-answer phrase without a model run.
let ASK_GEMMA_INSTRUCTIONS = """
Answer the question below using only the journal entries above, in this exact form:
The closest things you've written: On <date>, you wrote, "<copy the one sentence that best answers the question>"
Add a second quote in the same form only if another sentence also directly answers the question.
Copy each quote word for word.
"""

private let MONTHLY_REPORT_SYSTEM = """
You are MirrorNotes. Read this person's full month of journal entries and write a deep monthly reflection about who they are becoming, what tensions are shaping them, and what they might not have noticed themselves.

Write exactly these six sections, each label followed by a colon and one complete sentence:

YOUR MONTH IN ONE IMAGE: One vivid metaphor for the feeling or texture of this month, stated directly as an image — e.g. "A house with every light on and no one home."
THE TENSION AT THE CENTER: The main recurring conflict or friction that ran through their entries.
A MOMENT THAT SHIFTED SOMETHING: One specific entry or phrase that changed something, even subtly.
WHAT YOU'RE BECOMING: Who they seem to be growing into, based on what they wrote.
WHAT WANTS TO BE RELEASED: One thing from this month worth consciously letting go.
YOUR QUESTION FOR NEXT MONTH: An honest open question for them to sit with, ending with a question mark.

Rules:
- Write entirely in second person — use "you" and "your" throughout. Never write as the journal writer
- Each section is one complete sentence, under 45 words
- Reference actual words, moods, dates, or phrases from their entries where possible
- Read every word in the full sentence it appears in before referencing it. If an entry uses a word or phrase figuratively or as a turn of phrase (e.g. "a thread running through the month" is about a recurring theme, not the act of running), reflect that same figurative meaning back — never reinterpret it literally
- Use the MONTH STATS block to ground observations in specifics
- No therapy language, no generic affirmations, no Markdown, no bullets
- Do not add any text outside these six sections
- Do not mention that you are an AI
- Be warm, specific, and honest
"""

// Gemma-only monthly report (2026-09-27). Same root cause as the nudge/digest: on Gemma 3 1B,
// MONTHLY_REPORT_SYSTEM opens with a preamble ("Okay, here's a deep monthly reflection…") and
// invents specifics ("During a conversation with Bruno, I realized…" — Bruno is a dog). The
// grammar from groundedMonthlyGrammar ties A MOMENT THAT SHIFTED SOMETHING to a real entry's date
// plus a verbatim sentence from it, WHAT YOU'RE BECOMING / WHAT WANTS TO BE RELEASED to quotes from
// good-/hard-mood entries, and keeps the image, tension and question to lowercase word-by-word text
// (no names, no double spaces) after fixed openers. Rig: 10/10 with nothing invented
// (tools/llmrig/README.md). Foundation Models keeps MONTHLY_REPORT_SYSTEM.
let MONTHLY_REPORT_GEMMA_INSTRUCTIONS = """
Write a monthly reflection for the person who wrote the journal entries above, in exactly this form, one line per section:
YOUR MONTH IN ONE IMAGE: A <short metaphor for how this month felt>.
THE TENSION AT THE CENTER: You seem pulled between <two things from their entries>.
A MOMENT THAT SHIFTED SOMETHING: On <date>, you wrote, "<copy one sentence from that day's entry>" Then say what it might have changed.
WHAT YOU'RE BECOMING: You wrote, "<copy a hopeful sentence>" You seem to be becoming someone who <...>.
WHAT WANTS TO BE RELEASED: You wrote, "<copy a heavy sentence>" Maybe it's time to let go of <...>.
YOUR QUESTION FOR NEXT MONTH: One honest, open question ending with a question mark.
Speak to them as "you". Copy each quote word for word. Outside the quotes, do not mention anyone by name and do not add anything that is not in the entries.
"""

private let EMOTION_DETECT_SYSTEM = """
You are MirrorNotes. Read this journal entry and identify the writer's primary emotional state.
Reply with EXACTLY one word from this list:
Joyful, Grateful, Peaceful, Content, Energized, Hopeful, Anxious, Overwhelmed, Frustrated, Drained, Sad, Numb
No explanation. No punctuation. One word only.
"""

// Semantic grounding self-check — the model verifying its OWN prior output, as a candidate for
// what the word-overlap guards (isUngrounded/sharesNoWordWithRecent/openingIsUngrounded) can't
// do: tell honest interpretation/paraphrase apart from invented detail. Real-device measurement
// (GroundingSampleHarness.swift) showed those guards miss 53% of fabrications at realistic
// corpus scale, and that the miss can't be fixed by retuning their thresholds — honest and
// fabricated text land in overlapping shared-word ranges. This is a genuinely different signal:
// it doesn't count matching words, it asks whether the REFLECTION's specific claims are
// actually supported.
//
// Deliberately checked against RECENT entries only, never background — same scope
// `openingIsUngrounded` already uses, for the same reason: DAILY_NUDGE_SYSTEM itself requires
// the reflection to ground in Recent entries and never lift phrasing from Long-term context, so
// verifying against background too would let the judge rationalize "supported" off the same
// large, coincidence-prone pool that lets the word-overlap checks miss at scale (see
// `openingIsUngrounded`'s own doc comment on why combined-pool scale is exactly the risk).
//
// Bumped from private to internal as a test seam for GroundingSampleHarness's uncontaminated
// confusion-matrix test, which bypasses InsightService.localGenerate entirely (that path's
// single internal retry injects a GROUNDED/FABRICATED vocabulary constraint on any validation
// failure, which contaminated the earlier — now corrected — confusion-matrix measurement) and
// so needs this exact prompt string directly, the same reasoning as DAILY_NUDGE_SYSTEM's own
// bump above.
let GROUNDING_VERIFY_SYSTEM = """
You are a strict fact-checker reviewing a reflection written about someone's recent journal entries.
Read the RECENT ENTRIES, then read the REFLECTION.
A reflection may interpret, paraphrase, or draw an emotional conclusion from what's written — that is fine.
A reflection is FABRICATED if it states a specific detail, image, event, sensation, or object that does not appear anywhere in the RECENT ENTRIES, even if the reflection also mentions something real.
Reply with EXACTLY one word: GROUNDED or FABRICATED.
No explanation. No punctuation. One word only.
"""

private let FOLLOW_UP_SYSTEM = """
You are MirrorNotes, reading a journal entry the person is currently writing, mid-draft. Ask exactly one short follow-up question that invites them to go deeper into what they just wrote — the way a thoughtful friend would ask "what do you mean by that?" or "what's underneath that?"
Rules:
- Exactly one question, ending in a question mark
- Under 18 words
- Reference something specific and concrete from what they wrote — a word, feeling, or detail. Do not ask a generic question that could apply to any entry
- Address them as "you/your" only
- Do not answer for them, do not summarize what they wrote, do not give advice
- No preamble, no quotation marks around the question, nothing before or after it
- Do not mention that you are an AI or model
"""

private let GUIDED_ENTRY_SYSTEM = """
You are MirrorNotes, helping someone start a journal entry through a short guided conversation. Ask exactly one open, inviting question to help them begin reflecting. The first question should be broad and welcoming — about their day, how they're feeling, or what's on their mind. Each later question should build naturally on what they just answered, going one layer deeper.
Rules:
- Exactly one question, ending in a question mark
- Under 18 words
- Address them as "you/your" only
- Do not answer for them, do not summarize what they said, do not give advice
- Do not repeat a question already asked earlier in this conversation
- No preamble, no quotation marks around the question, nothing before or after it
- Do not mention that you are an AI or model
"""

enum InsightService {
    // How many older-entry excerpts `buildMemoryBrief` quotes verbatim, shared
    // by the daily nudge and weekly digest (both via `buildUserMessage`) and by
    // Ask. 5 regularly overflowed the smallest of those budgets (daily nudge's
    // ~1,288 chars), silently truncating the last excerpt mid-sentence; 4 fits
    // all three with margin. (Monthly report's 600-char background budget is
    // too tight for excerpts at all regardless of this limit — untouched here.)
    // Also read by InsightSignalSource's disclosure label, so what it reports
    // as "quoted" can't drift from what was actually sent.
    static let memoryBriefExcerptLimit = 4
    // Bumped from private to internal as a test seam for GroundingSampleHarness.
    static let dailyNudgePromptBudget = 4_600
    private static let weeklyDigestPromptBudget = 4_800
    private static let monthlyReportPromptBudget = 6_200
    private static let askPromptBudget = 5_700
    private static let askNoAnswerSentinelEN = "You haven't written about this yet."
    // Keyed by the same language codes as the digest/report section labels below,
    // so the fallback always matches the language Ask was actually instructed to answer in.
    private static let askNoAnswerPhrases: [String: String] = [
        "en": "You haven't written about this yet.",
        "es": "Aún no has escrito sobre esto.",
        "fr": "Tu n'as pas encore écrit à ce sujet.",
        "de": "Darüber hast du noch nicht geschrieben.",
        "it": "Non hai ancora scritto di questo.",
        "ja": "まだこれについて書いていません。",
        "ko": "아직 이것에 대해 쓰지 않았어요.",
        "pt": "Você ainda não escreveu sobre isso.",
        "ru": "Ты ещё не писал(а) об этом.",
        "zh": "你还没有写过这个话题。",
    ]
    private static func askNoAnswerPhrase(for target: ResponseLanguageTarget?) -> String {
        guard let target, let phrase = askNoAnswerPhrases[target.code] else {
            return askNoAnswerSentinelEN
        }
        return phrase
    }
    private struct ResponseLanguageTarget {
        let code: String
        let name: String
    }

    /// First few words of each recent nudge, deduped and order-preserved, so the
    /// prompt can steer the model away from re-using an opening it just used. This
    /// replaced a fixed 10-phrase opener list that cycled by day-of-year — with
    /// entries written every ~8-10 days, that cycle kept landing on the same phrase.
    private static func priorNudgeOpenings(from recentNudges: [String], words: Int = 7) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for nudge in recentNudges {
            let opening = firstWords(nudge, count: words)
            guard !opening.isEmpty else { continue }
            let key = opening.lowercased()
            if seen.insert(key).inserted {
                result.append(opening)
            }
        }
        return result
    }

    private static func firstWords(_ text: String, count: Int) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(count)
            .joined(separator: " ")
    }

    /// Lowercases and strips leading/trailing punctuation from each word so "it," and "it" (or
    /// a sentence-ending word carrying a period) still count as the same shared word.
    private static func normalizedWordSet(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(separator: " ")
                .map { $0.trimmingCharacters(in: .alphanumerics.inverted) }
                .filter { !$0.isEmpty }
        )
    }

    /// True when `text`'s opening (first 7 words, same window `priorNudgeOpenings` keys on)
    /// overlaps too heavily with one of the openings the prompt already told the model to avoid.
    /// The prompt-side instruction alone isn't reliable — Gemma 3 1B has reproduced a banned
    /// opener near-verbatim even when it was named explicitly in the prompt (observed: two
    /// nudges 7 days apart both opened "The rain outside feels like a gentle ...", the second
    /// generated *after* the first was listed as something to avoid). This is the enforcement
    /// backstop.
    ///
    /// Deliberately NOT an exact-string match: a first pass compared the full 7-word window for
    /// equality, which the observed pair happened to satisfy, but that's brittle by luck — swap
    /// one word ("a gentle reminder" → "a soft reminder") and an exact match misses the same
    /// template repeat it exists to catch, since a 1B model's restatement of a banned opener is
    /// exactly the kind of near-miss this needs to hold. Instead this compares the two openings
    /// as bags of words (order-insensitive, so a word inserted, dropped, or swapped doesn't
    /// break the match) and flags a repeat once at least `minSharedWords` of the *shorter*
    /// opening's words are also present in the new text's opening.
    static func repeatsPriorOpening(_ text: String, openings: [String], minSharedWords: Int = 5) -> Bool {
        guard !openings.isEmpty else { return false }
        let candidateWords = normalizedWordSet(firstWords(text, count: 7))
        guard !candidateWords.isEmpty else { return false }
        return openings.contains { opening in
            let openingWords = normalizedWordSet(opening)
            guard !openingWords.isEmpty else { return false }
            let threshold = min(minSharedWords, openingWords.count)
            return candidateWords.intersection(openingWords).count >= threshold
        }
    }

    /// High-frequency English function/filler words excluded when checking whether a nudge
    /// shares any real vocabulary with the entries it's supposed to be grounded in. Content
    /// words (a place, a name, a concrete noun or verb an entry would actually contain) are
    /// what should overlap; two unrelated pieces of text sharing "the"/"feels"/"like" by
    /// coincidence shouldn't count as grounding. Deliberately does NOT include words from any
    /// specific observed fabrication ("gentle", "quiet", "reminder", etc.) — those are ordinary
    /// content words a real entry could legitimately contain ("finally carving out some quiet
    /// in the mornings"), and blacklisting them would make a genuinely grounded nudge that names
    /// them back unmatchable, defeating the guard on the exact entries it should pass. Overfitting
    /// this list to one sample was caught by advisor before commit.
    private static let groundingStopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "in", "on", "at", "to", "from", "with", "for", "by",
        "is", "are", "was", "were", "be", "been", "being", "it", "its", "this", "that", "these", "those",
        "i", "me", "my", "mine", "you", "your", "yours", "we", "our", "ours",
        "he", "she", "they", "them", "his", "her", "their", "theirs",
        "feels", "feel", "felt", "feeling", "like", "likes", "liked",
        "still", "just", "really", "very", "so", "too", "also",
        "more", "most", "much", "many", "some", "any", "all", "each", "every", "other", "another", "such",
        "no", "not", "only", "own", "same", "than", "then", "once", "here", "there", "when", "where", "why",
        "how", "what", "which", "who", "whom", "having", "do", "does", "did", "doing",
        "would", "could", "should", "might", "must", "can", "will", "shall", "have", "has", "had",
        "about", "again", "further", "out", "up", "down", "over", "under", "off", "into", "onto",
        "if", "as", "because", "while", "during", "before", "after", "something", "someone", "things", "thing",
    ]

    /// Words of 4+ letters, lowercased, punctuation-stripped, filler excluded. Anything shorter
    /// or on the stopword list is too common to mean the two texts are actually connected.
    private static func contentWords(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 && !groundingStopwords.contains($0) }
        )
    }

    /// True when `text` shares no real vocabulary at all with `sourceEntries` — a strong signal
    /// the model invented the reflection rather than reading what was actually written.
    /// DAILY_NUDGE_SYSTEM explicitly requires this ("Reference actual words, moods, dates, or
    /// concrete events, not generic advice" / "Open by naming something concrete from a
    /// specific entry"), so a genuinely grounded nudge — even heavily paraphrased — should still
    /// land on at least one shared non-filler word with its source. Observed failure this
    /// backstops: Gemma 3 1B generated "The rain outside feels like a gentle reminder of the
    /// quiet spaces you've been carving out lately" against entries about a Timer app launch and
    /// download counts (mood read: JOYFUL, CONTENT) — zero shared vocabulary, and a tone
    /// inverted from the entries' own. `repeatsPriorOpening` alone wouldn't have caught this: a
    /// *differently*-worded fabrication would pass it while remaining just as disconnected from
    /// the entries. Checked against `recent + background` (the full context sent to the model),
    /// not just `recent`, since the prompt also permits drawing on long-term recurring themes.
    ///
    /// Real user feedback ("lots of generic assumptions when I gave specific information")
    /// pointed at the gap the original one-shared-word threshold left open: a nudge can land one
    /// coincidental content word (e.g. both mention "work") and pass this guard while everything
    /// else in it is generic filler unconnected to what was actually written — the guard was
    /// checking for *zero* overlap (outright fabrication) but not for *thin* overlap (technically
    /// grounded, still not specific). Requires more shared words as the source has more
    /// vocabulary to draw from — a flat "2" would leave the exact same loophole open on a long
    /// entry or a week's worth of entries, just at a higher word count instead of one (see
    /// `minimumSharedWords` below) — and falls back to the original 1-word threshold for short
    /// entries, preserving the false-positive protection that threshold existed for.
    static func isUngrounded(_ text: String, sourceEntries: [Entry]) -> Bool {
        let nudgeWords = contentWords(text)
        guard !nudgeWords.isEmpty else { return false }
        let sourceWords = contentWords(sourceEntries.map(\.insightContext).joined(separator: " "))
        guard !sourceWords.isEmpty else { return false }
        let shared = nudgeWords.intersection(sourceWords)
        return shared.count < minimumSharedWords(sourceWordCount: sourceWords.count, nudgeWordCount: nudgeWords.count)
    }

    /// Catches a narrower, worse failure than `isUngrounded`'s whole-response aggregate: a
    /// fabricated OPENING claim riding through on genuine words mentioned later in the same
    /// response. `isUngrounded` counts shared vocabulary anywhere in the text, so a response that
    /// invents its lead sentence entirely but echoes 2-3 real nouns afterward can clear the
    /// combined-pool threshold untouched — the aggregate count says "grounded" while the one
    /// sentence a reader actually takes as the reflection is invented. DAILY_NUDGE_SYSTEM
    /// requires the opening specifically name something concrete from an entry ("Open by naming
    /// something concrete from a specific entry"); this checks that requirement directly instead
    /// of trusting the aggregate count to imply it.
    ///
    /// Real device case (2026-09-22): "The rain outside feels like a gentle echo of the quiet
    /// space you've been trying to create. You're planning a walk... and a book..." — rain/echo/
    /// space are invented (no entry mentions weather), but "walk"/"book"/"circling" from other
    /// entries elsewhere in the source pool let the whole response pass `isUngrounded` clean.
    ///
    /// Checked against `recent` ONLY, never `recent + background` — tried the combined pool
    /// first and it didn't catch the reference case above: with a ~20-entry background pool
    /// (hundreds of words), a fabricated opening has decent odds of coincidentally sharing one
    /// common-ish word ("outside", "quiet") with *something* in that much text, which is exactly
    /// the false-negative this check exists to close. `isUngrounded` already covers "is this
    /// grounded in background themes"; this checks a narrower, stricter thing DAILY_NUDGE_SYSTEM
    /// actually requires — "open by naming something concrete from a specific [recent] entry" —
    /// so it must be checked against exactly the entries that requirement names, same scope
    /// `sharesNoWordWithRecent` already uses for its own flat/unscaled bar. Unlike
    /// `sharesNoWordWithRecent`, this only inspects the opening sentence: a nudge whose opening is
    /// 100% invented but whose LATER sentences happen to reference something from `recent` would
    /// still slip past a whole-text-vs-recent check while failing the system prompt's actual
    /// requirement, which is specifically about the opening.
    ///
    /// Flat 1-word bar, never scaled, for the same reason `sharesNoWordWithRecent` uses one: a
    /// single sentence doesn't supply enough vocabulary to demand more than "shares anything real
    /// at all" without risking false positives on short, honestly-grounded openings.
    static func openingIsUngrounded(_ text: String, recentEntries: [Entry]) -> Bool {
        let openingWords = contentWords(firstSentence(text))
        guard !openingWords.isEmpty else { return false }
        let recentWords = contentWords(recentEntries.map(\.insightContext).joined(separator: " "))
        // Same floor as sharesNoWordWithRecent (InsightService.swift:403), same reasoning: a
        // returning user's single terse recent entry can't supply enough vocabulary for even an
        // honest opening to land on. Below the floor, defer entirely to isUngrounded's
        // combined-pool check rather than risking a false positive here — unlike a raised
        // threshold, a floor can only make this check MORE lenient, never flag something it
        // wouldn't already flag, so it carries none of the "tuned blind" regression risk a
        // stricter bar would (see openingIsUngrounded_thinRecentCorpus_flaggedNoFloorUnlikeSibling
        // in InsightValidationTests, which this closes).
        guard recentWords.count >= 4 else { return false }
        return openingWords.intersection(recentWords).isEmpty
    }

    /// Sentence, not a fixed word count — `repeatsPriorOpening`'s 7-word window is deliberately
    /// short (it's comparing against prior *openings*, keyed the same way), but a grounding check
    /// needs the whole claim: "The rain outside feels like a gentle echo of the quiet space
    /// you've been trying to create" is 13 words, and a 7-word cutoff would drop "quiet" — itself
    /// a genuine shared word in some source pools — before the sentence-ending clause completes.
    private static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?\n")) {
            return String(trimmed[..<range.lowerBound])
        }
        return trimmed
    }

    /// A deliberately weaker backstop than `isUngrounded` — flags text only when it shares
    /// ZERO real words with `recentEntries`, never scaled by corpus size. This exists alongside
    /// `isUngrounded(recent+background)`, not as a replacement for it: the combined-pool check
    /// stays exactly as tuned (see `minimumSharedWords`'s doc comment on why that tuning is
    /// fragile and shouldn't be touched blind).
    ///
    /// First shipped as `isUngrounded(text, sourceEntries: recent)` — reusing the SAME scaled
    /// threshold for `recent` alone. That regressed live within a day: real device testing
    /// (2026-09-20) showed the groundingFallback card on every attempt, for entries that were
    /// the user's genuine recent three. Reproduced in isUngrounded_genuinelyGroundedAgainstReal-
    /// RecentThree_notDetected — plausible MirrorNotes-voice reflections that echo one or two
    /// real specifics and paraphrase the rest (exactly how a 1B model actually writes) landed
    /// `minimumSharedWords` of 2-4 against a 3-entry recent set, and got flagged. The combined-
    /// pool check's scaling was tuned for corpora up to ~26 entries; applying it a second time to
    /// a corpus of 2-3 is a different regime it was never validated against — same class of
    /// mistake as the original flat-2/scaled-cap history this whole guard has already been
    /// through twice (see `minimumSharedWords`'s doc comment).
    ///
    /// A flat "shares nothing at all" bar is what actually matches the failure this exists to
    /// catch: the original rain incident had ZERO shared words with recent — any threshold, even
    /// 1, would have caught it — so there's no need to demand more than that and risk rejecting a
    /// genuinely paraphrased reflection along with it.
    static func sharesNoWordWithRecent(_ text: String, recentEntries: [Entry]) -> Bool {
        let nudgeWords = contentWords(text)
        guard !nudgeWords.isEmpty else { return false }
        let recentWords = contentWords(recentEntries.map(\.insightContext).joined(separator: " "))
        // `dailyNudgeContext` falls back to a single old entry (`Array(sorted.prefix(1))`) when
        // nothing is inside the 14-day window — a returning user writing again after a long gap.
        // A 2-3 word entry ("Going in a good phase!") gives an honestly-grounded reflection almost
        // no vocabulary to land on at all; demanding even one shared word from that thin a corpus
        // risks the exact false-positive this function exists to avoid. Same "too small to judge
        // fairly" floor `minimumSharedWords` already uses (`sourceWordCount >= 4`) — below it,
        // defer entirely to the combined-pool check rather than adding a second opinion here.
        guard recentWords.count >= 4 else { return false }
        return nudgeWords.isDisjoint(with: recentWords)
    }

    /// DEBUG-only diagnostic: prints only counts and thresholds, never words or text — a repeat
    /// of a live "every attempt fails grounding" report where the underlying issue could be
    /// either check (combined-pool scaled, or recent-only flat) and there's no way to tell which
    /// without seeing the actual numbers each one computed, which finalNudgeResult's fallback
    /// substitution otherwise throws away entirely.
    static func debugLogGroundingCheck(_ text: String, recent: [Entry], background: [Entry], label: String) {
        #if DEBUG
        let nudgeWords = contentWords(text)
        let combinedWords = contentWords((recent + background).map(\.insightContext).joined(separator: " "))
        let recentWords = contentWords(recent.map(\.insightContext).joined(separator: " "))
        let sharedCombined = nudgeWords.intersection(combinedWords).count
        let sharedRecent = nudgeWords.intersection(recentWords).count
        let threshold = minimumSharedWords(sourceWordCount: combinedWords.count, nudgeWordCount: nudgeWords.count)
        print("[nudge][\(label)] nudgeWords=\(nudgeWords.count) combinedWords=\(combinedWords.count) recentWords=\(recentWords.count) sharedCombined=\(sharedCombined)/\(threshold) sharedRecent=\(sharedRecent)")
        #endif
    }

    /// A terse entry ("Going in a good phase!") gives a genuinely grounded nudge only two or
    /// three real content words to land on at all — demanding 2 shared words there would make
    /// short-entry users fail this guard even when honestly grounded, the exact false-positive
    /// risk the original threshold was written to avoid. 4 was picked as the cutoff because it's
    /// comfortably above what a single short entry supplies (2-3 words) while still being below
    /// what any entry with a couple of real sentences reaches — the boundary matters less than
    /// having one at all; no user data pins down where short-entry users actually cluster yet.
    ///
    /// Above that floor, the requirement scales with `sourceWordCount`: a long entry, or a
    /// week's worth of entries feeding a digest, hands the model far more vocabulary to
    /// coincidentally land 2 words in without the rest of the reflection being any more specific
    /// — the same weak-signal problem the flat "1" had, reappearing at "2" for anyone who writes
    /// at length. Roughly 1 additional required word per 15 source content words, so a
    /// ~150-word entry (a substantial paragraph) needs 3 shared words instead of 2.
    ///
    /// Capped at a flat 4, not at `nudgeWordCount` — `sourceWordCount` isn't one entry's
    /// vocabulary, it's `recent + background` (up to ~23 entries for a nudge, the whole month
    /// for a monthly report), so it reaches into the hundreds or thousands on any real account.
    /// The old `min(scaled, nudgeWordCount)` cap looked like a safety net but wasn't one at that
    /// scale: `scaled` (e.g. 68 for 1000 source words) blows straight past a nudge's own ~25-40
    /// content words, so the cap became the binding constraint — silently demanding every single
    /// content word in the nudge appear in the source, which ordinary prose (and MirrorNotes'
    /// own voice: "noticed", "seems", "maybe") can't satisfy. That's what turned this into an
    /// ~80% fallback rate live, caught from a real device screenshot the same day the scaling
    /// landed. A flat ceiling keeps the short/long-single-entry behavior this scaling was written
    /// for (see the tests below) without the requirement running away on a large corpus.
    private static func minimumSharedWords(sourceWordCount: Int, nudgeWordCount: Int) -> Int {
        guard sourceWordCount >= 4 else { return 1 }
        let scaled = 2 + sourceWordCount / 15
        return min(scaled, 4, max(nudgeWordCount, 2))
    }

    /// The recent/background split a daily nudge is generated from. Factored out so
    /// `ungroundedDailyNudges` (a retroactive audit over already-generated nudges) reconstructs
    /// a past nudge's context with the exact same rule `generateNudge` used live, rather than a
    /// second hand-copied version of this logic silently drifting from it over time.
    ///
    /// `asOf` stands in for "now": pass `Date()` when generating live, or a past
    /// `Insight.generatedAt` with `entries` pre-filtered to `createdAt <= asOf` when
    /// reconstructing history — an entry written after a nudge was generated couldn't have been
    /// read by it, so including it here would corrupt the reconstruction.
    static func dailyNudgeContext(from entries: [Entry], asOf: Date) -> (recent: [Entry], background: [Entry]) {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: asOf) ?? asOf
        let withinWindow = sorted.filter { $0.createdAt >= cutoff }
        let recent = withinWindow.isEmpty ? Array(sorted.prefix(1)) : Array(withinWindow.prefix(3))
        let recentIDs = Set(recent.map(\.id))
        let background = Array(sorted.filter { !recentIDs.contains($0.id) }.prefix(20))
        return (recent, background)
    }

    /// Retroactively flags past daily nudges whose text shares no real vocabulary with the
    /// entries they were supposedly grounded in — the same `isUngrounded` check `generateNudge`
    /// now runs live, applied after the fact to nudges generated before this guard existed.
    /// Necessarily a reconstruction, not a stored record (`Insight` keeps no snapshot of its
    /// inputs — see `InsightSignalSource`'s doc comment for the same caveat on the on-device
    /// X-ray this mirrors): if an entry from that window has since been edited or deleted, the
    /// answer for that nudge may no longer be accurate.
    static func ungroundedDailyNudges(among insights: [Insight], allEntries: [Entry]) -> [Insight] {
        // Same filter generateNudge itself now applies (hasReadableContext, not the narrower
        // textDecryptionFailed — a photo-only or failed-voice-transcription entry has no
        // decryption failure but is just as unreadable) — without it, an entry unreadable at
        // audit time (not necessarily at generation time) would drop out of the reconstructed
        // context and could make a genuinely grounded nudge look fabricated on replay. Hoisted
        // out of the per-insight closure below — computed once here, not once per insight audited.
        let decryptableEntries = allEntries.filter(hasReadableContext)
        return insights
            .filter { $0.type == .dailyNudge }
            // A fallback row's own boilerplate ("MirrorNotes couldn't find today's reflection...")
            // shares no vocabulary with any entry by construction — it's the guard's own safe
            // placeholder, not a generated reflection that needs auditing. Without this, the
            // audit flags every fallback as "ungrounded" alongside genuine fabrications, burying
            // the one signal this tool exists to surface (a live 2026-09-22 run flagged 30 of 32
            // rows this way, 29 of which were fallback text).
            .filter { !isUngroundedFallback($0.content) }
            .filter { insight in
                let asOf = insight.generatedAt
                let priorEntries = decryptableEntries.filter { $0.createdAt <= asOf }
                let (recent, background) = dailyNudgeContext(from: priorEntries, asOf: asOf)
                // Same dual check as generateNudge's live guard — this audit exists specifically
                // to retroactively find insights the pre-fix combined-only check let through, so
                // it has to use the fixed check, not the one being audited against.
                return isUngrounded(insight.content, sourceEntries: recent + background)
                    || sharesNoWordWithRecent(insight.content, recentEntries: recent)
            }
            .sorted { $0.generatedAt < $1.generatedAt }
    }

    // True when an entry has nothing an LLM prompt or a grounding guard could actually read.
    // Broader than `Entry.textDecryptionFailed` on purpose: a locked-device Keychain failure is
    // one way `insightContext` ends up empty, but by that property's own implementation
    // (Entry.swift), a photo-only entry with no typed caption and no voice note, or a voice note
    // whose transcript and translation are both empty, produces the same empty string — not
    // separately verified live, but a direct read of what insightContext actually returns for
    // those shapes. Either way, formatEntries silently drops the entry, and isUngrounded/
    // sharesNoWordWithRecent/openingIsUngrounded all early-return "not ungrounded" against an
    // empty source word set. Filtering on the symptom (empty context) rather than one specific
    // cause (decryption) catches all of them with one check.
    static func hasReadableContext(_ entry: Entry) -> Bool {
        !entry.insightContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func generateNudge(entries: [Entry], recentNudges: [String] = []) async throws -> (text: String, engine: LLMEngine, degraded: Bool) {
        // Real device case (2026-09-25): mirrorApp.swift's own call site filters this too, but
        // generateWeeklyDigest/generateMonthlyReport/ask also have callers that never went through
        // that filter (InsightViewModel's retry paths, AskView) — filtering here, at the
        // chokepoint every caller passes through, means the guarantee holds regardless of what
        // the caller remembered to do.
        let entries = entries.filter(hasReadableContext)
        let (recent, background) = dailyNudgeContext(from: entries, asOf: Date())
        guard !recent.isEmpty else {
            // Nothing readable to ground in at all — generating here would mean the model
            // inventing a reflection from a blank prompt, then persisting the honest-sounding
            // fallback text as if a real attempt had been made and genuinely failed grounding.
            // Throwing instead means nothing gets saved for today; a later call with readable
            // entries can still succeed normally.
            throw InsightError.serviceUnavailable("no readable entries to ground a nudge in")
        }
        let languageInstruction = responseLanguageInstruction(for: responseLanguageTarget(from: recent + background), task: .dailyNudge)
        let grounded = groundedNudgePlan(recent: recent, background: background, recentNudges: recentNudges)
        let localized = localizedGroundedNudge(recent: recent, background: background, recentNudges: recentNudges)
        let nudgePlan = localized?.plan ?? grounded.plan
        let nudgeValidator: ((String) throws -> String)? = localized.map { $0.validator } ?? (grounded.quoteOptions.isEmpty ? nil : { text in
            try validateGroundedNudge(text, quoteOptions: grounded.quoteOptions)
        })
        if case .unsuitable = nudgePlan, !LocalLLMService.prefersFoundationModels {
            // Gemma is the only engine and today's writing has no quotable sentence (a one- or
            // two-word entry). Honest fallback without running a model that could only invent.
            return (dailyNudgeUngroundedFallback, .gemma, true)
        }

        var userMessage = buildUserMessage(
            title: "Daily reflection context",
            recentEntries: recent,
            backgroundEntries: background,
            maxChars: dailyNudgePromptBudget,
            includeRecurringTerms: false
        )
        // var, not let: grown with each failed attempt's own opening below. Real-device
        // measurement (GroundingSampleHarness.swift, Finding 3) found this was a live bug, not
        // theoretical — 12 of 15 real generations against one fixed corpus opened with a
        // near-identical fabricated template, because repeatsPriorOpening only ever checked
        // against PRIOR SAVED nudges (recentNudges, from already-persisted Insights), never
        // against this call's own earlier attempts. A 1B model's output distribution can be
        // peaked enough to hand back the same opening on attempt 2 that it gave on attempt 1
        // (this loop's own comment already names that risk for grounding, but the repeat-check
        // never got the same treatment) — so a user could retry three times and see the
        // identical bad opening substituted as the "final" result all three times.
        //
        // Not a total fix, by construction: detection necessarily lands one attempt behind
        // (attempt 2's check is the first one that can see attempt 1's opening, since it's
        // appended only after attempt 1 finishes). Attempts 1 and 2 can still repeat each other
        // once before the loop reacts — this reduces the repeat window from "all 3 attempts"
        // to "at most attempts 1-2," not to zero.
        var openings = priorNudgeOpenings(from: Array(recentNudges.prefix(4)))
        if !openings.isEmpty {
            userMessage += "\n\nYour recent reflections already opened with:\n"
                + openings.map { "- \"\($0)…\"" }.joined(separator: "\n")
                + "\nOpen today's reflection with a different first sentence built from a different concrete detail."
        }

        // Bounded retry loop, not a single one-shot retry: a 1B model's output distribution can
        // be peaked enough to reproduce the same ungrounded/repetitive pattern even after being
        // told exactly what it did wrong — observed live (see isUngrounded's doc comment): a
        // "rain outside..." fabrication survived a retry that named the violation explicitly,
        // because the old code accepted the retry unconditionally with no re-check. Looping
        // (capped at maxAttempts) keeps trying for a genuinely clean result instead, at the cost
        // of more generations per nudge on what's still a best-effort reflection — not
        // unbounded, so a model that never produces a clean result doesn't loop forever.
        let maxAttempts = 3
        var lastResult: (text: String, engine: LLMEngine)?
        var lastViolatesGrounding = false
        var currentUserMessage = userMessage

        for attempt in 1...maxAttempts {
            let result: (text: String, engine: LLMEngine)
            do {
                result = try await localGenerate(
                    systemPrompt: DAILY_NUDGE_SYSTEM,
                    userMessage: currentUserMessage,
                    task: .dailyNudge,
                    responseLanguageInstruction: languageInstruction,
                    gemmaPlan: nudgePlan,
                    gemmaValidator: nudgeValidator
                )
            } catch {
                // A later attempt throwing (contextExhausted on a repeat full pass is realistic
                // on the older/slower devices this guard's whole population runs) doesn't
                // invalidate an earlier valid-but-flawed result — a flawed-but-truthful nudge
                // beats no nudge at all that day. Only propagate if there's nothing to fall back
                // on yet. A fabricated one still isn't shown as-is — see the shared fallback
                // logic after the loop, which this jumps into instead of returning directly.
                guard let lastResult else { throw error }
                return finalNudgeResult(lastResult, violatesGrounding: lastViolatesGrounding)
            }

            // Not for grammar-path output: its opening is `You wrote, "` plus the first words of
            // the quote, and routine entries start alike ("Usual gym, went to…"), so two different
            // quotes collide on this 7-word check. A retry there is the same prompt with a new
            // seed — it picks the same quote, fails the same way three times, and a good
            // reflection comes back degraded (GroundedNudgeTests.similarRoutineOpening…). The
            // repeat guard for that format is groundedNudgeQuoteOptions dropping sentences quoted
            // by recent nudges.
            let isGroundedQuote: Bool = {
                guard result.engine == .gemma, case .grammarConstrained = nudgePlan else { return false }
                return true
            }()
            let violatesRepeat = !isGroundedQuote && repeatsPriorOpening(result.text, openings: openings)
            // Checked against `recent` alone too (via the flat sharesNoWordWithRecent backstop,
            // not a second scaled isUngrounded pass — see its doc comment for why reusing the
            // scaled threshold on a small corpus regressed live on 2026-09-20). DAILY_NUDGE_
            // SYSTEM's own rule is "ground the answer in Recent entries" — background is only for
            // reading recurring themes, not for supplying the actual grounding — but the
            // combined-pool check alone lets a fabrication clear the bar on coincidental overlap
            // with background filler once the corpus is large (up to ~20 background entries,
            // hundreds of words). Real device case (2026-09-19): a rain/"quiet moments"
            // fabrication shared zero vocabulary with the 3 recent entries (self-control, a Timer
            // app launch, MirrorNotes feedback) yet still rendered as a real reflection.
            // Grammar-path output was already checked quote-by-quote against the entry by the
            // plan's validator; these word-overlap heuristics exist for free prose and wrongly
            // reject verified Chinese/Japanese output, which has no spaces to split words on
            // (GroundedLocalizedTests.localizedNudgeSurvivesTheRealPipeline, "ja").
            let violatesGrounding = !isGroundedQuote && (isUngrounded(result.text, sourceEntries: recent + background)
                || sharesNoWordWithRecent(result.text, recentEntries: recent)
                || openingIsUngrounded(result.text, recentEntries: recent))
            #if DEBUG
            print("[nudge][attempt \(attempt)] rawChars=\(result.text.count) rawWords=\(result.text.split(separator: " ").count)")
            #endif
            debugLogGroundingCheck(result.text, recent: recent, background: background, label: "attempt \(attempt)")
            guard violatesRepeat || violatesGrounding else {
                return (result.text, result.engine, false)
            }

            lastResult = result
            lastViolatesGrounding = violatesGrounding
            guard attempt < maxAttempts else { break }

            // This attempt's own opening joins the avoid-list for the NEXT attempt's repeat
            // check — see the `var openings` comment above for why this has to happen here and
            // not just once before the loop. Deduped the same way priorNudgeOpenings already
            // dedupes prior-day openings, so a template repeated across attempts 1 and 2 doesn't
            // get added to the list twice.
            let thisAttemptOpening = firstWords(result.text, count: 7)
            if !thisAttemptOpening.isEmpty, !openings.contains(where: { $0.caseInsensitiveCompare(thisAttemptOpening) == .orderedSame }) {
                openings.append(thisAttemptOpening)
            }

            // Named the violation(s) directly rather than just repeating the general
            // instruction — a list buried in the prompt was already ignored once. Built fresh
            // from THIS attempt's violations each time (not accumulated across attempts), and
            // appended to the original userMessage rather than the previous retry message, so
            // the prompt doesn't balloon across attempts.
            var violationNotes: [String] = []
            if violatesRepeat {
                let violatedOpening = firstWords(result.text, count: 7)
                violationNotes.append("your reflection opened with \"\(violatedOpening)…\" — exactly what you were told to avoid.")
            }
            if violatesGrounding {
                violationNotes.append("your reflection didn't reference anything actually written in the entries above — no shared word, event, or detail. It read as generic, invented content rather than a reflection of what's there.")
            }
            currentUserMessage = userMessage + """


                IMPORTANT: \(violationNotes.joined(separator: " ")) Start over with a different first sentence, naming a specific word, event, or detail actually present in the entries above.
                """
        }

        // Exhausted maxAttempts without a clean result. lastResult is always set by this point:
        // the only path that could reach here with it unset (the first iteration throwing)
        // already returns/throws from inside the catch above instead of falling through.
        guard let lastResult else {
            throw InsightError.serviceUnavailable("nudge generation produced no result")
        }
        return finalNudgeResult(lastResult, violatesGrounding: lastViolatesGrounding)
    }

    // "Flawed beats none" only covers flaws that are still truthful (repetitive phrasing,
    // stylistic drift) — it never meant "fabricated beats none." A repeat-only violation still
    // reflects something real in the entries, just phrased like a prior nudge, so it's shown
    // with `degraded: true` softening the push notification exactly as before. A grounding
    // violation means the text has no real connection to what was written — after maxAttempts
    // couldn't produce anything better, showing it anyway would put fabricated content in front
    // of the user with nothing distinguishing it from a real reflection (degraded only affects
    // push-notification wording, never persisted on the Insight itself). Substituting the
    // honest `dailyNudgeUngroundedFallback` message keeps `hasDailyNudgeForToday` satisfied
    // (no repeated generation attempts today) without ever showing invented content as if it
    // were real.
    private static func finalNudgeResult(
        _ result: (text: String, engine: LLMEngine),
        violatesGrounding: Bool
    ) -> (text: String, engine: LLMEngine, degraded: Bool) {
        guard violatesGrounding else { return (result.text, result.engine, true) }
        return (dailyNudgeUngroundedFallback, result.engine, true)
    }

    // "Check back tomorrow" used to be the framing here, but it overpromises: the background
    // pre-gen pass that would produce tomorrow's nudge only runs when there's an entry newer
    // than this one (mirrorApp.preGenerateInsightsIfNeeded's own gate) — with no new writing,
    // nothing retries on its own, tomorrow or otherwise. Leads with the one thing that's
    // actually true and actionable instead.
    static let dailyNudgeUngroundedFallback = String(
        localized: "MirrorNotes couldn't find today's reflection clearly grounded in what you wrote. Add a bit more to today's entry and it'll try again."
    )

    /// Advisor-suggested detection: a fallback insight needs no schema change (no new field on
    /// `Insight`, no second CloudKit schema deploy stacked on the still-undeployed MoodCheckIn
    /// one) — plain content equality against these three constants is the whole mechanism, and
    /// it works retroactively on insights already saved before this existed.
    ///
    /// Real gap this closes, caught by advisor audit: the three constants below were reworded
    /// once already the same day this detection shipped (Mirror -> MirrorNotes, plus a full
    /// rewrite dropping "check back tomorrow"). Exact-equality-only would have silently stopped
    /// recognizing any fallback Insight already persisted with the old text — it would render as
    /// a normal `.loaded` card showing "Mirror couldn't find a digest..." verbatim, with no Try
    /// Again button, on data already sitting in the store. `legacyUngroundedFallbacks` keeps
    /// every prior wording matchable. This still isn't forward-proof — the next rewording has to
    /// remember to add today's current strings here too — but it's the deliberate tradeoff for
    /// staying schema-free; a `resolvedDigestState`-style pure function (flagged separately) is
    /// the more durable fix if this set grows unwieldy.
    static func isUngroundedFallback(_ content: String) -> Bool {
        content == dailyNudgeUngroundedFallback
            || content == weeklyDigestUngroundedFallback
            || content == monthlyReportUngroundedFallback
            || legacyUngroundedFallbacks.contains(content)
    }

    private static let legacyUngroundedFallbacks: Set<String> = [
        "Mirror couldn't find a reflection clearly grounded in today's entries. Check back tomorrow, or add a bit more to what you've written today.",
        "Mirror couldn't find a digest clearly grounded in this week's entries. Check back tomorrow, or write a bit more this week.",
        "Mirror couldn't find a report clearly grounded in this month's entries. Check back tomorrow, or write a bit more this month.",
    ]

    /// Fewer than this many entries in the current week → not enough to find a
    /// week's theme; the call sites show the "write more this week" state instead
    /// of generating a thin digest.
    static let weeklyDigestMinimumWeekEntries = 3

    /// Fewer than this many entries this month (checked only once
    /// `DateHelpers.isInLastWeekOfMonth` is also true — see the call sites) → not enough to
    /// reflect the month meaningfully. Previously two separate thresholds (10 near month-end, 20
    /// otherwise) let a report generate mid-month purely on entry count, before the month was
    /// actually over — one threshold now that generation itself is gated on being in the last
    /// week, not on this number alone.
    static let monthlyReportMinimumEntries = 10

    /// Whether a cached weekly digest is due for regeneration. True only when
    /// BOTH hold: the 24h cooldown since it was generated has elapsed (bounds LLM
    /// cost — same guard the monthly report uses), and at least one entry in the
    /// current week is newer than the digest (there's genuinely new material).
    /// The second condition matters because a digest can be generated mid-week
    /// (on-demand from the view) and then go stale as the rest of the week fills
    /// in under a "THIS WEEK'S THEME" label that promises freshness.
    static func weeklyDigestIsStale(generatedAt: Date, newestWeekEntry: Date?) -> Bool {
        guard let newestWeekEntry else { return false }
        let cooldownElapsed = Date().timeIntervalSince(generatedAt) >= 24 * 60 * 60
        return cooldownElapsed && newestWeekEntry > generatedAt
    }

    /// The digest is explicitly "this week" — `WeeklyDigestView`, the C1 widget,
    /// and the `THIS WEEK'S THEME` section header all say so. `weekEntries` is the
    /// current ISO week only and is the sole source of the theme; `allEntries`
    /// (which includes them) is passed as long-term background for continuity in
    /// `WHAT'S BUILDING` / `NEXT WEEK`, never as digest material.
    static func generateWeeklyDigest(weekEntries: [Entry], allEntries: [Entry]) async throws -> (text: String, engine: LLMEngine) {
        // Same empty-context guard as generateNudge — see hasReadableContext's doc comment.
        let weekEntries = weekEntries.filter(hasReadableContext)
        let allEntries = allEntries.filter(hasReadableContext)
        guard !weekEntries.isEmpty else {
            throw InsightError.serviceUnavailable("no readable entries to ground a weekly digest in")
        }
        let thisWeek = weekEntries.sorted { $0.createdAt > $1.createdAt }
        let weekIDs = Set(weekEntries.map(\.id))
        let priorWeeks = allEntries
            .filter { !weekIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        let languageSource = thisWeek.isEmpty ? priorWeeks : thisWeek
        let languageInstruction = responseLanguageInstruction(for: responseLanguageTarget(from: languageSource), task: .weeklyDigest)
        let recentEntries = Array(thisWeek.prefix(12))
        let backgroundEntries = Array(priorWeeks.prefix(14))
        let userMessage = buildUserMessage(
            title: "Weekly digest context",
            recentEntries: recentEntries,
            backgroundEntries: backgroundEntries,
            maxChars: weeklyDigestPromptBudget
        )
        let grounded = groundedDigestPlan(weekEntries: recentEntries, languageSource: languageSource)
        let localized = localizedGroundedDigest(weekEntries: recentEntries, languageSource: languageSource)
        let digestPlan = localized?.plan ?? grounded.plan
        let digestValidator: ((String) throws -> String)? = localized.map { $0.validator } ?? (grounded.quoteOptions.isEmpty ? nil : { text in
            try validateGroundedDigest(text, quoteOptions: grounded.quoteOptions)
        })
        if case .unsuitable = digestPlan, !LocalLLMService.prefersFoundationModels {
            // Gemma-only device and nothing quotable this week (only one- or two-word entries).
            return (weeklyDigestUngroundedFallback, .gemma)
        }

        // Same isUngrounded backstop and bounded-retry-loop shape as generateNudge (see its doc
        // comment for the motivating "rain outside..." incident) — applied to the whole digest
        // (all six sections) rather than per-section, since WEEKLY_DIGEST_SYSTEM's "reference
        // actual words, moods, dates, or phrases" rule applies to the digest as a whole, and a
        // digest has far more words than a nudge to land a real one in, so the same
        // one-shared-word threshold is if anything looser here, not stricter.
        //
        // No repeatsPriorOpening equivalent here — scoped to grounding only, per what was asked.
        // Absence of an observed repeated-template failure for digests is NOT evidence it can't
        // happen: the nudge repeat was only caught because a user happened to scroll its history
        // list, and PastDigestCard (X-ray-wired the same way) could be sitting on an unnoticed
        // duplicate right now. Left open, not ruled out.
        let sourceEntries = recentEntries + backgroundEntries
        let maxAttempts = 3
        var lastResult: (text: String, engine: LLMEngine)?
        var currentUserMessage = userMessage

        for attempt in 1...maxAttempts {
            let result: (text: String, engine: LLMEngine)
            do {
                result = try await localGenerate(
                    systemPrompt: WEEKLY_DIGEST_SYSTEM,
                    userMessage: currentUserMessage,
                    task: .weeklyDigest,
                    responseLanguageInstruction: languageInstruction,
                    gemmaPlan: digestPlan,
                    gemmaValidator: digestValidator
                )
            } catch {
                // Every path that reaches lastResult here already failed the grounding check
                // (the only early-return above is the clean-result case) — so falling back to
                // it, unlike generateNudge's fail-open where a repeat-only violation is still
                // truthful, would mean showing fabricated content. Use the honest fallback
                // instead, same as the exhaustion path below.
                guard let previous = lastResult else { throw error }
                return (weeklyDigestUngroundedFallback, previous.engine)
            }

            // Same dilution fix as generateNudge: `sourceEntries` (recent + background, up to
            // 26 entries) can be large enough that a fabrication clears the combined-pool
            // minimum on coincidental overlap with background filler. `recentEntries` alone
            // (this week only) via the flat sharesNoWordWithRecent backstop — not a second
            // scaled isUngrounded pass, which regressed live against a small corpus (see that
            // function's doc comment).
            // Grammar-path output is verified by the plan's validator — see generateNudge.
            if result.engine == .gemma, case .grammarConstrained = digestPlan { return result }
            guard isUngrounded(result.text, sourceEntries: sourceEntries)
                || sharesNoWordWithRecent(result.text, recentEntries: recentEntries) else { return result }

            lastResult = result
            guard attempt < maxAttempts else { break }

            currentUserMessage = userMessage + """


                IMPORTANT: your digest above didn't reference anything actually written in the entries above — no shared word, event, or detail in any section. It read as generic, invented content rather than a reflection of what's there. Start over, naming a specific word, event, or detail actually present in the entries above.
                """
        }

        guard let lastResult else {
            throw InsightError.serviceUnavailable("weekly digest generation produced no result")
        }
        return (weeklyDigestUngroundedFallback, lastResult.engine)
    }

    // Same overpromise problem as the nudge's old copy, worse here: weeklyDigestIsStale needs
    // BOTH a 24h cooldown AND a week-entry newer than this insight's own generatedAt — since
    // this fallback's generatedAt is "now," a same-day "check back tomorrow" with no new
    // writing would find nothing stale to regenerate. UI-side retry (bypassing the cache
    // entirely) is the real unblock — see InsightService.isUngroundedFallback and the
    // groundingFallback state it drives.
    static let weeklyDigestUngroundedFallback = String(
        localized: "MirrorNotes couldn't find this week's digest clearly grounded in your entries. Try again, or write a bit more this week."
    )

    // Previously had no grounding backstop at all, unlike generateNudge/generateWeeklyDigest —
    // a single unconditional localGenerate call. Same isUngrounded check and bounded-retry-loop
    // shape added here, checked against `allEntries` (which already includes monthEntries, so
    // that alone covers everything the prompt draws vocabulary from — see
    // buildMonthlyReportMessage's recentBlock/backgroundBlock, both sourced from these two sets).
    static func generateMonthlyReport(monthEntries: [Entry], allEntries: [Entry]) async throws -> (text: String, engine: LLMEngine) {
        // Same empty-context guard as generateNudge — see hasReadableContext's doc comment.
        let monthEntries = monthEntries.filter(hasReadableContext)
        let allEntries = allEntries.filter(hasReadableContext)
        guard !monthEntries.isEmpty else {
            throw InsightError.serviceUnavailable("no readable entries to ground a monthly report in")
        }
        let languageInstruction = responseLanguageInstruction(for: responseLanguageTarget(from: monthEntries), task: .monthlyReport)
        let userMessage = buildMonthlyReportMessage(monthEntries: monthEntries, allEntries: allEntries)
        let grounded = groundedMonthlyPlan(monthEntries: monthEntries)
        if case .unsuitable = grounded.plan, !LocalLLMService.prefersFoundationModels {
            // Gemma-only device and nothing quotable this month (only one- or two-word entries).
            return (monthlyReportUngroundedFallback, .gemma)
        }
        let maxAttempts = 3
        var lastResult: (text: String, engine: LLMEngine)?
        var currentUserMessage = userMessage

        for attempt in 1...maxAttempts {
            let result: (text: String, engine: LLMEngine)
            do {
                result = try await localGenerate(
                    systemPrompt: MONTHLY_REPORT_SYSTEM,
                    userMessage: currentUserMessage,
                    task: .monthlyReport,
                    responseLanguageInstruction: languageInstruction,
                    gemmaPlan: grounded.plan,
                    gemmaValidator: grounded.quoteOptions.isEmpty ? nil : { text in
                        try validateGroundedMonthly(text, quoteOptions: grounded.quoteOptions)
                    }
                )
            } catch {
                guard let previous = lastResult else { throw error }
                return (monthlyReportUngroundedFallback, previous.engine)
            }

            // Same dilution fix as generateNudge/generateWeeklyDigest: `allEntries` can span a
            // user's whole history, easily large enough for a fabrication to clear the combined
            // threshold on coincidental overlap. `monthEntries` alone (this month only) via the
            // flat sharesNoWordWithRecent backstop, not a second scaled isUngrounded pass (see
            // that function's doc comment for why the scaled version regressed on a small corpus).
            // Grammar-path output is verified by the plan's validator — see generateNudge.
            if result.engine == .gemma, case .grammarConstrained = grounded.plan { return result }
            guard isUngrounded(result.text, sourceEntries: allEntries)
                || sharesNoWordWithRecent(result.text, recentEntries: monthEntries) else { return result }

            lastResult = result
            guard attempt < maxAttempts else { break }

            currentUserMessage = userMessage + """


                IMPORTANT: your report above didn't reference anything actually written in the entries above — no shared word, event, or detail in any section. It read as generic, invented content rather than a reflection of what's there. Start over, naming a specific word, event, or detail actually present in the entries above.
                """
        }

        guard let lastResult else {
            throw InsightError.serviceUnavailable("monthly report generation produced no result")
        }
        return (monthlyReportUngroundedFallback, lastResult.engine)
    }

    // Same reasoning as weeklyDigestUngroundedFallback — "check back tomorrow" could mean
    // "check back next month" once isInLastWeekOfMonth's window closes, and even inside that
    // window nothing regenerates without a newer entry. UI-side retry is the real unblock.
    static let monthlyReportUngroundedFallback = String(
        localized: "MirrorNotes couldn't find this month's report clearly grounded in your entries. Try again, or write a bit more this month."
    )

    static func ask(question: String, entries: [Entry]) async throws -> (text: String, engine: LLMEngine) {
        // Same empty-context filter as generateNudge/generateWeeklyDigest/generateMonthlyReport
        // — see hasReadableContext's doc comment. Unlike those, no throw-when-empty here: Ask
        // already has its own honest "you haven't written about this yet" sentinel for when
        // nothing relevant is found (askNoAnswerPhrase below), which is the right UX for an
        // interactive query with no readable entries, not a thrown error.
        let entries = entries.filter(hasReadableContext)
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let relevant = SearchService.search(query: question, in: sorted, limit: 10)
        let relevantIDs = Set(relevant.map(\.id))
        let background = sorted.filter { !relevantIDs.contains($0.id) }.prefix(8)
        let target = responseLanguageTarget(from: relevant + Array(background), extraText: question) ?? responseLanguageTargetFromCurrentLocale()
        let languageInstruction = responseLanguageInstruction(for: target, task: .ask)
        let grounded = groundedAskPlan(question: question, pool: relevant + Array(background), languageCode: target?.code)
        if grounded.noAnswer && !LocalLLMService.prefersFoundationModels {
            return (askNoAnswerPhrase(for: target), .gemma)
        }
        let localized = localizedGroundedAsk(question: question, pool: relevant + Array(background))
        let askPlan = grounded.noAnswer ? .unsuitable : (localized?.plan ?? grounded.plan)
        let askValidator: ((String) throws -> String)? = localized.map { $0.validator } ?? (grounded.quoteOptions.isEmpty ? nil : { text in
            try validateGroundedAsk(text, quoteOptions: grounded.quoteOptions)
        })
        if case .unsuitable = askPlan, !grounded.noAnswer, !LocalLLMService.prefersFoundationModels {
            return (askNoAnswerPhrase(for: target), .gemma)
        }
        return try await localGenerate(
            systemPrompt: ASK_SYSTEM,
            userMessage: buildAskMessage(
                entries: relevant,
                backgroundEntries: Array(background),
                question: question
            ),
            task: .ask,
            responseLanguageInstruction: languageInstruction,
            askNoAnswerPhrase: askNoAnswerPhrase(for: target),
            gemmaPlan: askPlan,
            gemmaValidator: askValidator
        )
    }

    static func detectEmotion(text: String) async throws -> String {
        let trimmed = String(text.prefix(3000))
        // Emotion detection isn't saved as an Insight (it sets Entry.mood directly), so which
        // engine ran doesn't need attribution — .engine is discarded here. If a future pass
        // ever persists mood provenance (e.g. an Entry-level "detected by" field), this is the
        // line to revisit.
        let response = try await localGenerate(
            systemPrompt: EMOTION_DETECT_SYSTEM,
            userMessage: trimmed,
            task: .emotion,
            responseLanguageInstruction: nil
        )
        return normalizeEmotion(response.text)
    }

    // Research/validation stage only — not yet called from generateNudge or any production
    // path. See GROUNDING_VERIFY_SYSTEM's doc comment for why this exists and its scope choice.
    // Never throws — fails CLOSED (isFabricated=true) on anything, not just an unparseable
    // response: matching this whole guard system's existing philosophy ("flawed beats none, but
    // never fabricated beats none" — finalNudgeResult's comment), an inconclusive verdict is not
    // evidence of grounding. This includes localGenerate itself throwing — its internal
    // validate-retry exhausting on an unparseable response surfaces as
    // InsightError.incompleteResponse, which an earlier version of this function let propagate
    // uncaught, making the "fails closed" promise in this comment false whenever that happened
    // (caught live by GroundingSampleHarness's polarity-flip test, which hit exactly this path).
    static func verifyGroundingSemantic(nudgeText: String, recentEntries: [Entry]) async -> (isFabricated: Bool, raw: String) {
        let entriesBlock = formatEntries(recentEntries, maxChars: 3_000)
        let userMessage = """
            RECENT ENTRIES:
            \(entriesBlock)

            REFLECTION:
            \(nudgeText)
            """
        let response: (text: String, engine: LLMEngine)
        do {
            response = try await localGenerate(
                systemPrompt: GROUNDING_VERIFY_SYSTEM,
                userMessage: userMessage,
                task: .groundingVerification,
                responseLanguageInstruction: nil
            )
        } catch {
            return (true, "<verification generation failed: \(error)>")
        }
        guard let verdict = recognizedGroundingVerdict(response.text) else {
            return (true, response.text)
        }
        return (verdict == .fabricated, response.text)
    }

    // Never persisted as an Insight — ephemeral, in-editor-only, discarded once the chip is
    // dismissed or the entry is saved. Keeps this feature schema-free: WriteView holds the
    // question in @State only, matching the security rule that draft-adjacent text stays
    // entirely on-device and un-cached.
    static func generateFollowUp(currentText: String) async throws -> (text: String, engine: LLMEngine) {
        let trimmed = String(currentText.suffix(3000))
        let target = responseLanguageTarget(from: [], extraText: trimmed) ?? responseLanguageTargetFromCurrentLocale()
        let languageInstruction = responseLanguageInstruction(for: target, task: .followUp)
        return try await localGenerate(
            systemPrompt: FOLLOW_UP_SYSTEM,
            userMessage: trimmed,
            task: .followUp,
            responseLanguageInstruction: languageInstruction
        )
    }

    // Tier 2 ("Talk it out", writing-roadmap.md) — a guided, multi-turn entry starter.
    // Deliberately reuses the .followUp task rather than adding a new LocalLLMTask case: the
    // output shape (one short question, ending in "?") is identical, only the system prompt and
    // conversation framing differ, so the existing validator/cleaning/retry machinery for
    // .followUp applies unchanged. Every turn is caller-held @State (see TalkItOutView) — never
    // persisted, never written anywhere until the user explicitly inserts the composed result
    // into a real draft.
    static func generateGuidedQuestion(conversationSoFar: [(question: String, answer: String)]) async throws -> (text: String, engine: LLMEngine) {
        let userMessage: String
        if conversationSoFar.isEmpty {
            userMessage = "This is the start of a new guided journal entry. Ask your first question."
        } else {
            let transcript = conversationSoFar
                .map { "Q: \($0.question)\nA: \($0.answer)" }
                .joined(separator: "\n\n")
            userMessage = "Conversation so far:\n\(transcript)\n\nAsk the next question."
        }
        let allAnswers = conversationSoFar.map(\.answer).joined(separator: " ")
        let target = responseLanguageTarget(from: [], extraText: allAnswers) ?? responseLanguageTargetFromCurrentLocale()
        let languageInstruction = responseLanguageInstruction(for: target, task: .followUp)
        return try await localGenerate(
            systemPrompt: GUIDED_ENTRY_SYSTEM,
            userMessage: userMessage,
            task: .followUp,
            responseLanguageInstruction: languageInstruction
        )
    }

    // Gemma's system prompts are English, so without an explicit directive it tends
    // to answer in English even when the journal content is not. Emotion detection
    // is intentionally skipped because it must return the persisted English mood key.
    private static func responseLanguageInstruction(for target: ResponseLanguageTarget?, task: LocalLLMTask) -> String? {
        // groundingVerification skipped for the same reason emotion is: it must return exactly
        // one of two fixed English tokens (GROUNDED/FABRICATED), not localized prose.
        guard task != .emotion, task != .groundingVerification else { return nil }
        guard let target = target ?? responseLanguageTargetFromCurrentLocale() else { return nil }
        // Every base prompt is already English. For an English target the templates below read
        // "Respond only in English. Do not use English unless quoting the user's own words." — a
        // direct contradiction that shipped to every English-writing user from 0e31e03 (2026-07-05)
        // until 2026-09-26. Foundation Models shrugged it off; a 1B model can't.
        guard target.code != "en" else { return nil }

        switch task {
        case .weeklyDigest, .monthlyReport:
            let labels = localizedSectionLabels(for: task, languageCode: target.code)
            return """
            Use exactly these section labels instead of any English labels listed above:
            \(labels.joined(separator: "\n"))

            Write all reflection prose after each label only in \(target.name). Do not use English in the prose unless quoting the user's own words.
            """
        case .dailyNudge, .ask, .followUp:
            return "Respond only in \(target.name). Do not use English unless quoting the user's own words."
        case .emotion, .groundingVerification:
            return nil
        }
    }

    private static func localizedSectionLabels(for task: LocalLLMTask, languageCode: String) -> [String] {
        let labels: [[String: String]]
        switch task {
        case .weeklyDigest:
            labels = weeklyDigestSectionLabels
        case .monthlyReport:
            labels = monthlyReportSectionLabels
        case .dailyNudge, .ask, .emotion, .followUp, .groundingVerification:
            return []
        }
        return labels.map { section in
            section[languageCode] ?? section["en"] ?? ""
        }
    }

    private static func responseLanguageTarget(from entries: [Entry], extraText: String? = nil) -> ResponseLanguageTarget? {
        var scores: [String: Double] = [:]

        if let extraText {
            scoreDetectedLanguage(in: extraText, multiplier: 1.4, into: &scores)
        }

        for entry in entries {
            scoreDetectedLanguage(in: entry.text, multiplier: 1.0, into: &scores)

            for voiceNote in entry.voiceNotes {
                if let code = normalizedLanguageCode(voiceNote.languageCode) {
                    let transcriptLength = voiceNote.transcript?.count ?? 0
                    scores[code, default: 0] += Double(max(120, transcriptLength))
                }
                scoreDetectedLanguage(in: voiceNote.transcript, multiplier: 1.0, into: &scores)
            }
        }

        guard let code = scores.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        return responseLanguageTarget(forCode: code)
    }

    private static func responseLanguageTargetFromCurrentLocale() -> ResponseLanguageTarget? {
        guard let code = Locale.current.language.languageCode?.identifier else { return nil }
        return responseLanguageTarget(forCode: code)
    }

    private static func scoreDetectedLanguage(in text: String?, multiplier: Double, into scores: inout [String: Double]) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 20 else { return }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.35,
              let code = normalizedLanguageCode(language.rawValue)
        else { return }

        scores[code, default: 0] += Double(min(trimmed.count, 1_500)) * confidence * multiplier
    }

    private static func responseLanguageTarget(forCode rawCode: String) -> ResponseLanguageTarget? {
        guard let code = normalizedLanguageCode(rawCode) else { return nil }
        let knownNames: [String: String] = [
            "en": "English",
            "es": "Spanish",
            "ja": "Japanese",
            "zh": "Chinese (Simplified)",
            "de": "German",
            "fr": "French",
            "pt": "Portuguese",
            "ko": "Korean",
            "it": "Italian",
            "ru": "Russian",
        ]
        let name = knownNames[code]
            ?? Locale(identifier: "en").localizedString(forLanguageCode: code)
            ?? Locale(identifier: "en").localizedString(forIdentifier: code)
        guard let name, !name.isEmpty else { return nil }
        return ResponseLanguageTarget(code: code, name: name)
    }

    private static func normalizedLanguageCode(_ rawCode: String?) -> String? {
        let raw = rawCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        let locale = Locale(identifier: raw)
        if let code = locale.language.languageCode?.identifier.lowercased(), code != "und" {
            return code
        }

        let fallback = raw
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first?
            .lowercased()
        guard let fallback, fallback != "und" else { return nil }
        return fallback
    }

    // Bumped from private to internal (same-file scope otherwise) as a test seam for
    // GroundingSampleHarness, which needs to call the raw single-shot generation directly (no
    // retry loop, no grounding-fallback substitution) to see what Gemma actually produced before
    // any guard intervened — same reasoning as this file's header comment on `validate`/
    // `cleaned*Output()`.
    static func localGenerate(
        systemPrompt basePrompt: String,
        userMessage: String,
        task: LocalLLMTask,
        responseLanguageInstruction: String?,
        askNoAnswerPhrase: String? = nil,
        gemmaPlan: LocalLLMService.GemmaPlan = .samePrompt,
        gemmaValidator: ((String) throws -> String)? = nil
    ) async throws -> (text: String, engine: LLMEngine) {
        let systemPrompt: String
        if let instruction = responseLanguageInstruction {
            systemPrompt = basePrompt + "\n\n" + instruction
        } else {
            systemPrompt = basePrompt
        }
        let finalSystemPrompt: String
        if task == .ask {
            let phrase = askNoAnswerPhrase ?? askNoAnswerSentinelEN
            finalSystemPrompt = systemPrompt + "\n\nIf the entries truly contain nothing related to the question, respond exactly: \(phrase)"
        } else {
            finalSystemPrompt = systemPrompt
        }
        // Grammar-constrained Gemma output has its own shape (a verbatim quote, which the generic
        // first-person check would reject for containing the writer's own "my"/"I"), so it gets
        // the plan's validator instead. Foundation Models output always takes the generic path.
        func validated(_ result: (text: String, engine: LLMEngine)) throws -> String {
            if result.engine == .gemma, case .grammarConstrained = gemmaPlan, let gemmaValidator {
                return try gemmaValidator(result.text)
            }
            return try validate(result.text, for: task, askNoAnswerPhrase: askNoAnswerPhrase)
        }
        do {
            do {
                let first = try await queuedGenerate(systemPrompt: finalSystemPrompt, userMessage: userMessage, task: task, gemmaPlan: gemmaPlan)
                return (try validated(first), first.engine)
            } catch InsightError.emptyResponse, InsightError.incompleteResponse, LocalLLMError.emptyResponse {
                let retryMessage = retryUserMessage(original: userMessage, task: task)
                let second = try await queuedGenerate(systemPrompt: finalSystemPrompt, userMessage: retryMessage, task: task, gemmaPlan: gemmaPlan)
                return (try validated(second), second.engine)
            } catch LocalLLMError.contextExhausted {
                await LocalLLMService.shared.resetContext()
                let second = try await queuedGenerate(systemPrompt: finalSystemPrompt, userMessage: userMessage, task: task, gemmaPlan: gemmaPlan)
                return (try validated(second), second.engine)
            }
        } catch let error as InsightError {
            throw error
        } catch {
            throw InsightError.serviceUnavailable(error.localizedDescription)
        }
    }

    private static func queuedGenerate(systemPrompt: String, userMessage: String, task: LocalLLMTask, gemmaPlan: LocalLLMService.GemmaPlan = .samePrompt) async throws -> (text: String, engine: LLMEngine) {
        let raw = try await LLMGenerationQueue.shared.run {
            try await LocalLLMService.shared.generate(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                task: task,
                gemmaPlan: gemmaPlan
            )
        }
        // Grammar-constrained output is already in final shape and holds a verbatim quote of the
        // user's own words. The cleaners below rewrite first person ("I felt" -> "you felt") and
        // strip brackets/asterisks — applied here they would corrupt the quote.
        if raw.engine == .gemma, case .grammarConstrained = gemmaPlan {
            return (raw.text.trimmingCharacters(in: .whitespacesAndNewlines), raw.engine)
        }

        let cleaned: String
        switch task {
        case .weeklyDigest:
            cleaned = raw.text.cleanedDigestOutput()
        case .monthlyReport:
            cleaned = raw.text.cleanedMonthlyReportOutput()
        case .dailyNudge, .ask, .emotion, .followUp, .groundingVerification:
            cleaned = raw.text.cleanedInsightOutput()
        }
        return (cleaned, raw.engine)
    }

    private static func retryUserMessage(original: String, task: LocalLLMTask) -> String {
        """
        \(original)

        IMPORTANT:
        Your previous response was incomplete or malformed. Write the full final answer again from the beginning.
        Finish with a complete sentence and final punctuation.
        Do not continue the previous answer.
        \(retryConstraint(for: task))
        """
    }

    private static func retryConstraint(for task: LocalLLMTask) -> String {
        switch task {
        case .dailyNudge:
            return "Return only 2-3 complete sentences under 100 words."
        case .weeklyDigest:
            return "Return exactly the required six labeled lines. Every section must have 1-2 complete sentences after the colon, under 70 words per section."
        case .monthlyReport:
            return "Return exactly the six required labeled sections from the system prompt. The image section must start with a vivid metaphor. The final question section must end with a question mark. Every other section must end with a complete sentence."
        case .ask:
            return "Return only 3-5 complete sentences. Do not invent facts not in the entries."
        case .emotion:
            return "Return exactly one allowed mood word and nothing else."
        case .followUp:
            return "Return exactly one short question, ending with a question mark, under 18 words. Nothing before or after it."
        case .groundingVerification:
            return "Return exactly one word: GROUNDED or FABRICATED. Nothing else."
        }
    }

    // Internal (not private) so InsightValidationTests can exercise it directly via
    // @testable import — this is the one seam the fixture-based structural test harness
    // (see .claude/2.1.0-design-plan.md, Track A1) needs into otherwise-private validation
    // logic. No other access change: validateWeeklyDigest/validateMonthlyReport/etc. stay
    // private and are reached only through this dispatch, same as production callers.
    static func validate(_ text: String, for task: LocalLLMTask, askNoAnswerPhrase: String? = nil) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InsightError.emptyResponse }

        switch task {
        case .dailyNudge:
            // DAILY_NUDGE_SYSTEM explicitly sanctions "I noticed ..." as Mirror's own voice
            // ("never the journal writer's voice") — .strictExceptMirrorNoticed blocks every
            // other journal-writer-shaped "I ..."/"my ..." construction but tolerates that one,
            // matching the prompt's own carve-out instead of a blanket ban or a blanket pass.
            return try validateCompleteProse(
                trimmed,
                minimumCharacters: 45,
                maximumWords: 120,
                allowedSentenceRange: 1...4,
                firstPersonPolicy: .strictExceptMirrorNoticed
            )
        case .ask:
            let expectedPhrase = askNoAnswerPhrase ?? askNoAnswerSentinelEN
            if trimmed == askNoAnswerSentinelEN || trimmed == expectedPhrase {
                return expectedPhrase
            }
            // ASK_SYSTEM grants no Mirror-voice exception at all ("Address the person as
            // you/your only") — .strict, not .strictExceptMirrorNoticed.
            return try validateCompleteProse(
                trimmed,
                minimumCharacters: 35,
                maximumWords: 140,
                allowedSentenceRange: 1...6,
                firstPersonPolicy: .strict
            )
        case .weeklyDigest:
            return try validateWeeklyDigest(trimmed)
        case .monthlyReport:
            return try validateMonthlyReport(trimmed)
        case .emotion:
            guard recognizedEmotion(trimmed) != nil else {
                throw InsightError.incompleteResponse
            }
            return trimmed
        case .followUp:
            return try validateFollowUp(trimmed)
        case .groundingVerification:
            guard recognizedGroundingVerdict(trimmed) != nil else {
                throw InsightError.incompleteResponse
            }
            return trimmed
        }
    }

    private static func validateFollowUp(_ text: String) throws -> String {
        guard text.hasSuffix("?") else { throw InsightError.incompleteResponse }
        guard text.count >= 8, text.count <= 160 else { throw InsightError.incompleteResponse }
        // Reject if a second question mark shows up mid-string — a sign the model produced
        // more than the "exactly one question" the prompt asks for, not a single clean ask.
        guard text.filter({ $0 == "?" }).count == 1 else { throw InsightError.incompleteResponse }
        guard !containsJournalWriterFirstPerson(text) else { throw InsightError.incompleteResponse }
        return text
    }

    // .strictExceptMirrorNoticed exists only for dailyNudge's sanctioned "I noticed" — see the
    // call site in validate(). Every other task that checks first person at all (ask, and
    // validateWeeklyDigest/validateMonthlyReport below) uses .strict.
    private enum FirstPersonPolicy {
        case strict
        case strictExceptMirrorNoticed
    }

    private static func validateCompleteProse(
        _ text: String,
        minimumCharacters: Int,
        maximumWords: Int,
        allowedSentenceRange: ClosedRange<Int>,
        firstPersonPolicy: FirstPersonPolicy
    ) throws -> String {
        guard text.count >= minimumCharacters else { throw InsightError.incompleteResponse }
        guard endsAsCompleteSentence(text) else { throw InsightError.incompleteResponse }
        guard !hasDanglingEnding(text) else { throw InsightError.incompleteResponse }
        // A 1B model sometimes acknowledges the task ("Okay, you've got it. Let's
        // see what you can offer.") before the real reflection — no journal grounds
        // it, and length/first-person/ending checks all pass it. Reject so the
        // existing retry produces a clean answer.
        guard !startsWithMetaPreamble(text) else { throw InsightError.incompleteResponse }
        switch firstPersonPolicy {
        case .strict:
            guard !containsJournalWriterFirstPerson(text) else { throw InsightError.incompleteResponse }
        case .strictExceptMirrorNoticed:
            guard !containsJournalWriterFirstPerson(text, allowMirrorNoticed: true) else { throw InsightError.incompleteResponse }
        }

        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count <= maximumWords else { throw InsightError.incompleteResponse }

        let sentences = text.filter { ".!?".contains($0) }.count
        guard allowedSentenceRange.contains(max(1, sentences)) else { throw InsightError.incompleteResponse }
        return text
    }

    private static func validateWeeklyDigest(_ text: String) throws -> String {
        let normalizedText = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let requiredHeaders = weeklyDigestSectionLabels.map { Array($0.values) }

        for (index, headerAliases) in requiredHeaders.enumerated() {
            guard let body = digestBody(for: headerAliases, at: index, in: normalizedText, headers: requiredHeaders) else {
                throw InsightError.incompleteResponse
            }
            guard body.count >= 20,
                  body.count <= 400,
                  endsAsCompleteSentence(body),
                  !hasDanglingEnding(body),
                  !containsJournalWriterFirstPerson(body) else {
                throw InsightError.incompleteResponse
            }
        }

        return normalizedText
    }

    private static func validateMonthlyReport(_ text: String) throws -> String {
        let normalizedText = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")

        guard normalizedText.count >= 80 else { throw InsightError.incompleteResponse }

        let requiredHeaders = monthlyReportSectionLabels.map { Array($0.values) }
        let questionHeaderAliases = monthlyReportSectionLabels[5].map(\.value)

        for (index, headerAliases) in requiredHeaders.enumerated() {
            guard let body = digestBody(for: headerAliases, at: index, in: normalizedText, headers: requiredHeaders) else {
                throw InsightError.incompleteResponse
            }
            guard body.count >= 15,
                  body.count <= 350,
                  endsAsCompleteSentence(body),
                  !hasDanglingEnding(body),
                  !containsJournalWriterFirstPerson(body) else {
                throw InsightError.incompleteResponse
            }
            // The closing question must end with "?"
            if !Set(headerAliases).isDisjoint(with: questionHeaderAliases) {
                guard body.trimmingCharacters(in: .whitespacesAndNewlines).last == "?" else {
                    throw InsightError.incompleteResponse
                }
            }
        }

        return normalizedText
    }

    /// True when the response opens with a short sentence that acknowledges the
    /// request rather than reflecting — a preamble to strip by rejecting. Narrow
    /// on purpose: the first sentence must be short, match a meta-acknowledgment
    /// shape, AND be followed by more text (so a legitimate reflection that
    /// merely opens with "Okay," is untouched). Exercised via `validate(_:for:)`
    /// in InsightValidationTests, same as the other prose gates here.
    private static func startsWithMetaPreamble(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // ":" is a delimiter too — an announce line ("Here's a reflection for you:")
        // has no "." before the colon, so without it the whole first paragraph
        // reads as one long "sentence" and the ≤12-word guard below bails.
        guard let end = trimmed.firstIndex(where: { ".!?:".contains($0) }) else { return false }
        let first = String(trimmed[..<end]).lowercased()
        let rest = trimmed[trimmed.index(after: end)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return false }
        guard first.split(whereSeparator: { " \n".contains($0) }).count <= 12 else { return false }

        let metaPhrases = [
            "you've got it", "you got it", "here we go", "here you go",
            "let's see what you", "let's take a look", "let me take a look",
            "let me look at", "here's what i", "here is what i",
            "here's your reflection", "here is your reflection",
            "here's a reflection", "as you requested", "as requested",
            "let's begin", "let's get started", "let's dive in",
            "what you can offer", "let's do this", "on it",
        ]
        if metaPhrases.contains(where: { first.contains($0) }) { return true }

        let bareAcks: Set<String> = [
            "okay", "ok", "alright", "sure", "got it", "understood",
            "no problem", "of course", "certainly", "sounds good", "will do",
        ]
        let stripped = first.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?-–—"))
        return bareAcks.contains(stripped)
    }

    private static func endsAsCompleteSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?".contains(last)
    }

    private static func hasDanglingEnding(_ text: String) -> Bool {
        let lower = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .lowercased()

        let danglingEndings = [
            " and", " but", " because", " so", " while", " although", " though", " with", " without",
            " into", " toward", " towards", " about", " around", " through", " from", " for", " to",
            " it seems like", " it sounds like"
        ]
        return danglingEndings.contains { lower.hasSuffix($0) }
    }

    // allowMirrorNoticed: true removes "notice|noticed" from the blocked-verb group — the one
    // "I ..." construction DAILY_NUDGE_SYSTEM sanctions as Mirror's own voice. Every other
    // caller (ask, weeklyDigest, monthlyReport) uses the default false — their prompts grant
    // no such exception.
    private static func containsJournalWriterFirstPerson(_ text: String, allowMirrorNoticed: Bool = false) -> Bool {
        let verbGroup = allowMirrorNoticed
            ? "am|seem|feel|felt|think|thought|work|try|tried|need|needed|want|wanted|sound|sounds|plan|planned|can|could|will|would|should|have|had|was|were"
            : "am|seem|feel|felt|think|thought|work|try|tried|need|needed|want|wanted|notice|noticed|sound|sounds|plan|planned|can|could|will|would|should|have|had|was|were"
        let blockedPatterns = [
            "\\bI\\s+(\(verbGroup))\\b",
            #"\bI'm\b"#,
            #"\bI['’]m\b"#,
            #"\bI['’]ll\b"#,
            #"\bI['’]ve\b"#,
            #"\bI['’]d\b"#,
            #"\bmy\s+(work|mind|sister|brother|mother|father|friend|friends|family|project|life|week|mood|energy|journal|entry|entries|well-being)\b"#,
            #"\bme\s+(feel|felt|think|notice|noticed|want|need)\b"#
        ]

        return blockedPatterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func digestBody(for headerAliases: [String], at index: Int, in text: String, headers: [[String]]) -> String? {
        guard let headerRange = headerAliases
            .lazy
            .compactMap({ text.range(of: "\($0):", options: [.caseInsensitive, .diacriticInsensitive]) })
            .min(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }
        let afterHeader = String(text[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var bodyEnd = afterHeader.endIndex

        for nextHeaderAliases in headers.dropFirst(index + 1) {
            if let nextRange = nextHeaderAliases
                .lazy
                .compactMap({ afterHeader.range(of: "\($0):", options: [.caseInsensitive, .diacriticInsensitive]) })
                .min(by: { $0.lowerBound < $1.lowerBound }) {
                bodyEnd = nextRange.lowerBound
                break
            }
        }

        return String(afterHeader[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Shared with WeeklyDigestView / MonthlyReportView so prompt-side labels and
    // display-side parsing never drift apart into two copies.
    static let weeklyDigestSectionLabels: [[String: String]] = [
        [
            "en": "THIS WEEK'S THEME", "de": "THEMA DIESER WOCHE", "es": "TEMA DE ESTA SEMANA",
            "fr": "THEME DE LA SEMAINE", "it": "TEMA DELLA SETTIMANA", "ja": "今週のテーマ",
            "ko": "이번 주의 주제", "pt": "TEMA DA SEMANA", "ru": "ТЕМА ЭТОЙ НЕДЕЛИ",
            "zh": "本周主题",
        ],
        [
            "en": "YOUR ENERGY", "de": "DEINE ENERGIE", "es": "TU ENERGIA",
            "fr": "TON ENERGIE", "it": "LA TUA ENERGIA", "ja": "あなたのエネルギー",
            "ko": "당신의 에너지", "pt": "SUA ENERGIA", "ru": "ТВОЯ ЭНЕРГИЯ",
            "zh": "你的能量",
        ],
        [
            "en": "WHAT'S BUILDING", "de": "WAS SICH AUFBAUT", "es": "LO QUE ESTA CRECIENDO",
            "fr": "CE QUI SE CONSTRUIT", "it": "COSA STA CRESCENDO", "ja": "育っているもの",
            "ko": "쌓여 가는 것", "pt": "O QUE ESTA SE FORMANDO", "ru": "ЧТО НАРАСТАЕТ",
            "zh": "正在累积的东西",
        ],
        [
            "en": "WATCH OUT FOR", "de": "ACHTE AUF", "es": "CUIDADO CON",
            "fr": "A SURVEILLER", "it": "FAI ATTENZIONE A", "ja": "気をつけたいこと",
            "ko": "주의할 점", "pt": "FIQUE ATENTO A", "ru": "НА ЧТО ОБРАТИТЬ ВНИМАНИЕ",
            "zh": "需要留意",
        ],
        [
            "en": "MOOD BOOST", "de": "STIMMUNGSSCHUB", "es": "IMPULSO DE ANIMO",
            "fr": "COUP DE POUCE POUR L'HUMEUR", "it": "SPINTA PER L'UMORE", "ja": "気分を上げること",
            "ko": "기분 전환", "pt": "IMPULSO DE HUMOR", "ru": "ПОДДЕРЖКА НАСТРОЕНИЯ",
            "zh": "情绪助推",
        ],
        [
            "en": "NEXT WEEK", "de": "NAECHSTE WOCHE", "es": "LA PROXIMA SEMANA",
            "fr": "LA SEMAINE PROCHAINE", "it": "LA PROSSIMA SETTIMANA", "ja": "来週",
            "ko": "다음 주", "pt": "PROXIMA SEMANA", "ru": "СЛЕДУЮЩАЯ НЕДЕЛЯ",
            "zh": "下周",
        ],
    ]

    static let monthlyReportSectionLabels: [[String: String]] = [
        [
            "en": "YOUR MONTH IN ONE IMAGE", "de": "DEIN MONAT IN EINEM BILD", "es": "TU MES EN UNA IMAGEN",
            "fr": "TON MOIS EN UNE IMAGE", "it": "IL TUO MESE IN UN'IMMAGINE", "ja": "一枚のイメージで見る今月",
            "ko": "한 장면으로 본 이번 달", "pt": "SEU MES EM UMA IMAGEM", "ru": "ТВОЙ МЕСЯЦ В ОДНОМ ОБРАЗЕ",
            "zh": "用一个画面概括你的这个月",
        ],
        [
            "en": "THE TENSION AT THE CENTER", "de": "DIE SPANNUNG IM ZENTRUM", "es": "LA TENSION CENTRAL",
            "fr": "LA TENSION AU CENTRE", "it": "LA TENSIONE AL CENTRO", "ja": "中心にある葛藤",
            "ko": "중심에 있는 긴장", "pt": "A TENSAO CENTRAL", "ru": "ЦЕНТРАЛЬНОЕ НАПРЯЖЕНИЕ",
            "zh": "核心张力",
        ],
        [
            "en": "A MOMENT THAT SHIFTED SOMETHING", "de": "EIN MOMENT, DER ETWAS VERSCHOBEN HAT", "es": "UN MOMENTO QUE MOVIO ALGO",
            "fr": "UN MOMENT QUI A DEPLACE QUELQUE CHOSE", "it": "UN MOMENTO CHE HA SPOSTATO QUALCOSA", "ja": "何かが変わった瞬間",
            "ko": "무언가가 달라진 순간", "pt": "UM MOMENTO QUE MUDOU ALGO", "ru": "МОМЕНТ, КОТОРЫЙ ЧТО-ТО СДВИНУЛ",
            "zh": "让某些东西发生变化的时刻",
        ],
        [
            "en": "WHAT YOU'RE BECOMING", "de": "WER DU WIRST", "es": "EN QUIEN TE ESTAS CONVIRTIENDO",
            "fr": "CE QUE TU DEVIENS", "it": "CIO CHE STAI DIVENTANDO", "ja": "あなたがなりつつあるもの",
            "ko": "당신이 되어 가는 모습", "pt": "NO QUE VOCE ESTA SE TORNANDO", "ru": "КЕМ ТЫ СТАНОВИШЬСЯ",
            "zh": "你正在成为的样子",
        ],
        [
            "en": "WHAT WANTS TO BE RELEASED", "de": "WAS LOSGELASSEN WERDEN WILL", "es": "LO QUE QUIERE SER SOLTADO",
            "fr": "CE QUI VEUT ETRE RELACHE", "it": "COSA VUOLE ESSERE LASCIATO ANDARE", "ja": "手放したがっているもの",
            "ko": "놓아주고 싶은 것", "pt": "O QUE QUER SER LIBERADO", "ru": "ЧТО ПРОСИТСЯ ОТПУСТИТЬ",
            "zh": "想被放下的东西",
        ],
        [
            "en": "YOUR QUESTION FOR NEXT MONTH", "de": "DEINE FRAGE FUER DEN NAECHSTEN MONAT", "es": "TU PREGUNTA PARA EL PROXIMO MES",
            "fr": "TA QUESTION POUR LE MOIS PROCHAIN", "it": "LA TUA DOMANDA PER IL PROSSIMO MESE", "ja": "来月への問い",
            "ko": "다음 달을 위한 질문", "pt": "SUA PERGUNTA PARA O PROXIMO MES", "ru": "ТВОЙ ВОПРОС НА СЛЕДУЮЩИЙ МЕСЯЦ",
            "zh": "给下个月的你的问题",
        ],
    ]

    /// Body text of the FIRST labeled section of a digest / monthly-report string
    /// — "THIS WEEK'S THEME" for a weekly digest, "YOUR MONTH IN ONE IMAGE" for a
    /// monthly report — for the home-screen widget bridge (`WidgetBridge`). Only
    /// that one section crosses the app-group boundary; the full six-section
    /// insight doesn't fit a widget.
    ///
    /// `labels` is the same `weeklyDigestSectionLabels` / `monthlyReportSectionLabels`
    /// table `WeeklyDigestView.parseDigest` and `MonthlyReportCard.extractBody`
    /// use, so the widget and the on-screen card can't disagree about where a
    /// section starts. The header match (`"<alias>:"`) is the same too — and it's
    /// defeated by `**`-wrapped headers, so this strips the same markdown noise
    /// `parseDigest` does. Stored `Insight.content` is already `cleaned…Output()`
    /// (headers un-wrapped, colon-normalized) but a caller may pass raw text.
    ///
    /// Returns nil if the first section's header isn't present.
    static func firstSectionBody(of content: String, labels: [[String: String]]) -> String? {
        guard let firstSection = labels.first else { return nil }
        let normalized = content
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        func headerRange(_ aliases: [String], in text: Substring) -> Range<String.Index>? {
            aliases
                .lazy
                .compactMap { text.range(of: "\($0):", options: [.caseInsensitive, .diacriticInsensitive]) }
                .min(by: { $0.lowerBound < $1.lowerBound })
        }

        guard let start = headerRange(Array(firstSection.values), in: Substring(normalized)) else { return nil }
        let afterHeader = normalized[start.upperBound...]

        var bodyEnd = afterHeader.endIndex
        for section in labels.dropFirst() {
            if let next = headerRange(Array(section.values), in: afterHeader) {
                bodyEnd = next.lowerBound
                break
            }
        }

        let body = afterHeader[..<bodyEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n", with: "\n")
        return body.isEmpty ? nil : body
    }

    private static func buildMonthlyReportMessage(monthEntries: [Entry], allEntries: [Entry]) -> String {
        let totalWords = monthEntries.reduce(0) { $0 + $1.wordCount }
        let avgWords = monthEntries.isEmpty ? 0 : totalWords / monthEntries.count
        let voiceCount = monthEntries.filter { $0.source == .voice || $0.hasVoiceNotes }.count

        let moodCounts = Dictionary(grouping: monthEntries.compactMap(\.mood), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        let moodSummary = moodCounts.prefix(5).map { "\($0.key) \($0.value)x" }.joined(separator: ", ")

        let cal = Calendar.current
        let weekGroups = Dictionary(grouping: monthEntries) { entry -> Int in
            cal.component(.weekOfYear, from: entry.createdAt)
        }
        let weeklyBreakdown = weekGroups.sorted { $0.key < $1.key }
            .map { "Week \($0.key): \($0.value.count) \($0.value.count == 1 ? "entry" : "entries")" }
            .joined(separator: ", ")

        let moodArc = monthEntries
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap(\.mood)
            .prefix(12)
            .joined(separator: " → ")

        let statsBlock = """
        MONTH STATS:
        Entries this month: \(monthEntries.count)
        Total words written: \(totalWords)
        Average words per entry: \(avgWords)
        Voice note entries: \(voiceCount)
        Mood arc (oldest → newest): \(moodArc.isEmpty ? "no moods recorded" : moodArc)
        Mood summary: \(moodSummary.isEmpty ? "not enough mood data" : moodSummary)
        Weekly breakdown: \(weeklyBreakdown.isEmpty ? "not available" : weeklyBreakdown)
        """

        let sortedMonth = monthEntries.sorted { $0.createdAt > $1.createdAt }
        let monthIDs = Set(monthEntries.map(\.id))
        let backgroundEntries = Array(allEntries
            .filter { !monthIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(20))

        let recentBlock = formatEntries(sortedMonth, maxChars: 3_600)
        let backgroundBlock = buildMemoryBrief(from: backgroundEntries, maxChars: 600)

        let today = Date().formatted(date: .abbreviated, time: .omitted)
        let message = """
        Monthly deep report context

        Today: \(today)

        \(statsBlock)

        Older context (before this month):
        \(backgroundBlock)

        This month's entries (newest first):
        \(recentBlock)
        """
        return clipped(message, maxChars: monthlyReportPromptBudget)
    }

    // Bumped from private to internal as a test seam for GroundingSampleHarness — see
    // localGenerate's comment above.
    static func buildUserMessage(
        title: String,
        recentEntries: [Entry],
        backgroundEntries: [Entry],
        maxChars: Int,
        includeRecurringTerms: Bool = true
    ) -> String {
        let recentBlock = formatEntries(recentEntries, maxChars: Int(Double(maxChars) * 0.72))
        let backgroundBlock = buildMemoryBrief(from: backgroundEntries, maxChars: Int(Double(maxChars) * 0.28), includeRecurringTerms: includeRecurringTerms)
        #if DEBUG
        // Lengths and entry counts only — never the block contents.
        print("[nudge][prompt:\(title)] recentEntries=\(recentEntries.count) recentBlockChars=\(recentBlock.count) isRecentEmpty=\(recentBlock == "No entries available.") backgroundEntries=\(backgroundEntries.count) backgroundBlockChars=\(backgroundBlock.count)")
        #endif

        let today = Date().formatted(date: .abbreviated, time: .omitted)
        // Recent entries first, Long-term context second. Originally tried as a fix for a 1B
        // model sharing ZERO words with `recent` on real device logs (2026-09-20), on the
        // hypothesis that background-first gave its more "quotable" brief undue priority. That
        // hypothesis measured as a no-op: output length and shared-word counts were identical
        // before and after this reorder (the actual cause turned out to be the recurring-terms
        // keyword list in Long-term context — see `includeRecurringTerms`). Kept anyway because
        // it matches the system prompt's own stated priority ("ground the answer in Recent
        // entries") and cost nothing to keep — not because it's confirmed to change model
        // behavior.
        return """
        \(title)

        Today: \(today)

        Recent entries:
        \(recentBlock)

        Long-term context:
        \(backgroundBlock)
        """
    }

    private static func buildAskMessage(entries: [Entry], backgroundEntries: [Entry], question: String) -> String {
        let backgroundBlock = buildMemoryBrief(from: backgroundEntries, maxChars: 1_300)
        let entryBlock = formatEntries(entries, maxChars: 3_800)
        let message = """
        Long-term context:
        \(backgroundBlock)

        Most relevant entries:
        \(entryBlock)

        Question: \(question)
        Look carefully at all the entries above for related themes, emotions, or events before answering.
        """
        return clipped(message, maxChars: askPromptBudget)
    }

    private static func formatEntries(_ entries: [Entry], maxChars: Int) -> String {
        guard !entries.isEmpty else { return "No entries available." }
        var remaining = maxChars
        var blocks: [String] = []

        for (index, entry) in entries.enumerated() {
            let date = entry.createdAt.formatted(date: .abbreviated, time: .omitted)
            let mood = entry.mood.map { "Mood: \($0)" } ?? "Mood: not specified"
            let source = entry.source == .voice ? "Source: voice note" : "Source: written entry"
            let context = entry.insightContext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !context.isEmpty else { continue }

            let header = "Entry \(index + 1) - \(date)\n\(mood). \(source)."
            let budget = max(280, min(1100, remaining - header.count - 24))
            guard budget > 0 else { break }
            let body = clipped(context, maxChars: budget)
            let block = "\(header)\n\(body)"
            blocks.append(block)
            remaining -= block.count
            if remaining <= 300 { break }
        }

        return blocks.joined(separator: "\n---\n")
    }

    // internal, not private — same pattern as `selectRepresentativeExcerpts` and `validate`,
    // bumped for MemoryBriefBudgetTests to exercise the real truncation path directly.
    static func buildMemoryBrief(from entries: [Entry], maxChars: Int, includeRecurringTerms: Bool = true) -> String {
        guard !entries.isEmpty else { return "No older context available yet." }

        let total = entries.count
        let dated = entries.map(\.createdAt).sorted()
        let dateRange: String
        if let first = dated.first, let last = dated.last {
            dateRange = "\(first.formatted(date: .abbreviated, time: .omitted)) to \(last.formatted(date: .abbreviated, time: .omitted))"
        } else {
            dateRange = "unknown date range"
        }

        let moodCounts = Dictionary(grouping: entries.compactMap(\.mood), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\($0.key) \($0.value)x" }
            .joined(separator: ", ")

        let recurringTerms = recurringKeywords(from: entries)
        let voiceCount = entries.filter { $0.source == .voice || $0.hasVoiceNotes }.count
        // A5 (see .claude/2.1.0-design-plan.md): was `entries.prefix(5)` — pure recency, so a
        // short "quick check-in" from yesterday always displaced a substantive entry from
        // three weeks ago, even one worth spotting as a recurring pattern. Aggregate stats
        // above (moodCounts/recurringTerms/dateRange) still read the full `entries` window
        // upstream callers already bounded by recency (20/14 entries) — only which 5 of those
        // get quoted as excerpts changes here.
        // 5 excerpts at 220 chars each plus the stats header above (~280 chars)
        // regularly exceeded this function's ~1,288-char budget in the daily
        // nudge, so the final `clipped(brief, maxChars:)` below was silently
        // hard-truncating the last excerpt mid-sentence. 4 fits with margin.
        let excerpts = selectRepresentativeExcerpts(from: entries, limit: memoryBriefExcerptLimit)
            .map { entry in
                let date = entry.createdAt.formatted(date: .abbreviated, time: .omitted)
                return "- \(date): \(clipped(entry.insightContext, maxChars: 220))"
            }
            .joined(separator: "\n")

        // The recurring-terms line is a bare comma-separated word list — real device logging
        // (2026-09-20) showed a 1B model on the daily nudge path lifting 2-3 words straight from
        // it verbatim (matching background, never recent) instead of engaging with the prose in
        // Recent entries: a labeled list next to "open by naming something concrete" reads as a
        // ready-made answer, easier than parsing paragraphs. `includeRecurringTerms: false` (used
        // by generateNudge only, where the prompt explicitly requires grounding in Recent entries
        // specifically) drops the line entirely rather than trying to word-guard a shortcut that
        // survived a prompt reorder already. Weekly digest / monthly report / Ask keep it — they
        // don't have this reported failure, and reformatting them blind risks the same kind of
        // unverified regression `minimumSharedWords`' tuning history already caused twice.
        let recurringLine = includeRecurringTerms
            ? "\nRecurring words/themes: \(recurringTerms.isEmpty ? "not enough repeated terms" : recurringTerms.joined(separator: ", "))."
            : ""
        let brief = """
        Older entries reviewed: \(total) (\(dateRange)).
        Common moods: \(moodCounts.isEmpty ? "not enough mood labels" : moodCounts).\(recurringLine)
        Voice-note entries: \(voiceCount).
        Representative older excerpts:
        \(excerpts)
        """

        return clipped(brief, maxChars: maxChars)
    }

    /// How much an entry is worth surfacing as a long-term-context excerpt, independent of
    /// recency. The negative-mood bonus is gated to short entries (< shortEntryWordThreshold)
    /// — it exists to rescue a brief-but-meaningful check-in ("Rough day. Overwhelmed.") that
    /// word count alone would never surface, not to advantage negative mood in general. A flat
    /// bonus with no such gate was tried first and failed a realistic-mix check (advisor
    /// review, 2026-09-04): mood is auto-detected on nearly every entry and roughly half of
    /// MirrorTheme.moodOptions are negative, so in a typical window where most entries happen
    /// to be negative-mood at ordinary journal length, the bonus stacked on top of word count
    /// and crowded out a long, calm, reflective entry entirely — see
    /// ContextSelectionTests.realisticMixedPool_doesNotCrowdOutLongCalmEntry. Gating the bonus
    /// to entries already too short to compete on word count avoids that: once an entry is
    /// substantive by length, mood doesn't need to help it (or hurt everything else).
    private static let shortEntryWordThreshold = 100
    private static let shortNegativeEntryBonus = 150

    private static func substantivenessScore(_ entry: Entry) -> Int {
        var score = entry.wordCount
        if entry.wordCount < shortEntryWordThreshold,
           let mood = entry.mood, MirrorTheme.negativeMoods.contains(mood) {
            score += shortNegativeEntryBonus
        }
        return score
    }

    // Internal (not private) so InsightValidationTests can exercise it — same testable seam
    // as InsightService.validate above.
    //
    // Picks the `limit` most substantive entries from `entries` (by substantivenessScore, tied
    // scores broken toward more recent) rather than the first `limit` in whatever order they
    // arrive. Callers already bound `entries` to a recency window upstream (buildMemoryBrief's
    // callers cap `background` at 20/14 entries) — this only re-ranks which of those get
    // quoted as excerpts, then re-sorts the selection back to recency order for display so
    // excerpts still read newest-first. Falls back to plain recency ordering when there's
    // nothing to trim (ranking would be a no-op).
    static func selectRepresentativeExcerpts(from entries: [Entry], limit: Int) -> [Entry] {
        guard entries.count > limit else {
            return entries.sorted { $0.createdAt > $1.createdAt }
        }
        return entries
            .sorted { a, b in
                let scoreA = substantivenessScore(a)
                let scoreB = substantivenessScore(b)
                if scoreA != scoreB { return scoreA > scoreB }
                return a.createdAt > b.createdAt
            }
            .prefix(limit)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private static func recurringKeywords(from entries: [Entry]) -> [String] {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "because", "been", "being", "could", "didnt", "does", "dont",
            "feel", "feeling", "felt", "from", "have", "just", "like", "more", "really", "still", "that",
            "their", "there", "thing", "think", "this", "today", "very", "want", "were", "what", "when",
            "with", "work", "would", "your", "journal", "entry", "voice", "note"
        ]
        let words = entries
            .flatMap { $0.insightContext.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) }
            .filter { $0.count > 3 && !stopWords.contains($0) && Int($0) == nil }

        return Dictionary(grouping: words, by: { $0 })
            .mapValues(\.count)
            .filter { $0.value >= 2 }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(10)
            .map(\.key)
    }

    private static func clipped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func normalizeEmotion(_ response: String) -> String {
        recognizedEmotion(response) ?? "Content"
    }

    private static func recognizedEmotion(_ response: String) -> String? {
        let cleaned = response
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first { !$0.isEmpty } ?? response
        return MirrorTheme.moodOptions.first { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
    }

    enum GroundingVerdict {
        case grounded
        case fabricated
    }

    // Same shape as recognizedEmotion: takes the first alphanumeric token, matches
    // case-insensitively. Anything else (empty, neither word, both words, extra prose the model
    // ignored the "one word only" instruction for) returns nil, which verifyGroundingSemantic
    // treats as fabricated — see its comment on failing closed.
    static func recognizedGroundingVerdict(_ response: String) -> GroundingVerdict? {
        let cleaned = response
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first { !$0.isEmpty } ?? response
        if cleaned.caseInsensitiveCompare("GROUNDED") == .orderedSame { return .grounded }
        if cleaned.caseInsensitiveCompare("FABRICATED") == .orderedSame { return .fabricated }
        return nil
    }

}

// Not private (see InsightService.validate above for why): InsightValidationTests exercises
// the full repair-then-validate pipeline these production call sites use, not validate() in
// isolation, so cleanedInsightOutput/cleanedDigestOutput/cleanedMonthlyReportOutput need the
// same testable-internal seam. softenDigestFragments stays private — it's an internal helper
// of cleanedDigestOutput, not a pipeline stage tests need to call directly.
extension String {
    /// A 1B model sometimes prefixes the reflection with an announce line that
    /// ends in a colon — "Okay, here's a reflection for you:", "Here's your
    /// reflection, friend:". Drop it so the insight opens on the actual
    /// observation. Conservative: only fires when a short leading segment ends
    /// with the first colon (no sentence break before it), carries an announce-y
    /// marker, and real prose follows.
    func strippingLeadingMetaPreamble() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return trimmed }
        if let stop = trimmed.firstIndex(where: { ".!?\n".contains($0) }), stop < colon {
            return trimmed
        }
        let head = String(trimmed[..<colon]).lowercased()
        let tail = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let headWords = head.split(whereSeparator: { " \n".contains($0) })
        guard tail.count >= 40, headWords.count <= 15 else { return trimmed }

        let firstWord = headWords.first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.!?-–—")) ?? ""
        let opensWithAck = ["okay", "ok", "alright", "sure", "right", "so"].contains(firstWord)

        let announceMarkers = [
            #"\bhere'?s\b"#, #"\bhere is\b"#, #"\bhere you go\b"#,
            #"\breflection\b"#, #"\bbased on (your|the)\b"#,
            #"\bas (requested|you asked|you requested)\b"#,
        ]
        let announces = announceMarkers.contains {
            head.range(of: $0, options: [.regularExpression]) != nil
        }
        guard opensWithAck || announces else { return trimmed }
        return tail
    }

    /// The model picking up "voice of a close friend" and addressing the writer
    /// as "friend" — a vocative, not a reference to anyone in their entries
    /// (those are never called just "friend"). Runs before the " my " → " your "
    /// rewrite below so "my friend" is caught in its original form too.
    func strippingFriendVocative() -> String {
        replacingOccurrences(of: #"(?i)\s*,\s*(my|your)\s+friend\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*(my|your)\s+friend\s*,\s*"#, with: "", options: .regularExpression)
    }

    func cleanedInsightOutput() -> String {
        strippingLeadingMetaPreamble()
            .strippingFriendVocative()
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: #"\bI seem\b"#, with: "You seem", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "I feel", with: "You seem", options: .caseInsensitive)
            .replacingOccurrences(of: #"\bI felt\b"#, with: "you felt", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI work\b"#, with: "you work", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI try\b"#, with: "you try", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI tried\b"#, with: "you tried", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI need\b"#, with: "you need", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI needed\b"#, with: "you needed", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI want\b"#, with: "you want", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI wanted\b"#, with: "you wanted", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI plan\b"#, with: "you plan", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI planned\b"#, with: "you planned", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI can\b"#, with: "you can", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI could\b"#, with: "you could", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI will\b"#, with: "you will", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI would\b"#, with: "you would", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI should\b"#, with: "you should", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "I’ve been", with: "you’ve been", options: .caseInsensitive)
            .replacingOccurrences(of: "I'm trying", with: "you're trying", options: .caseInsensitive)
            .replacingOccurrences(of: "I am trying", with: "you're trying", options: .caseInsensitive)
            // Placed after "I am trying" above so that specific phrase still matches first —
            // these generic am/was/were rules only catch what's left. Closes a gap
            // InsightValidationTests found: containsJournalWriterFirstPerson's blocked-verb
            // list already includes am/was/were, but nothing here repaired them, so an "I was
            // overwhelmed..." leak reached the user unrepaired. dailyNudge/ask now also reject
            // it as a backstop (see FirstPersonPolicy in validateCompleteProse below) — but
            // repairing it here is strictly better than rejecting it: the output stays usable
            // instead of forcing a retry.
            .replacingOccurrences(of: #"\bI am\b"#, with: "you are", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI was\b"#, with: "you were", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bI were\b"#, with: "you were", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "I’ll", with: "you could", options: .caseInsensitive)
            .replacingOccurrences(of: "I'll", with: "you could", options: .caseInsensitive)
            .replacingOccurrences(of: "I'm", with: "you're", options: .caseInsensitive)
            .replacingOccurrences(of: "I’ve", with: "you've", options: .caseInsensitive)
            .replacingOccurrences(of: "I've", with: "you've", options: .caseInsensitive)
            .replacingOccurrences(of: " I'd ", with: " you could ", options: .caseInsensitive)
            .replacingOccurrences(of: " my ", with: " your ", options: .caseInsensitive)
            .replacingOccurrences(of: " My ", with: " Your ", options: .caseInsensitive)
            .replacingOccurrences(of: " me ", with: " you ", options: .caseInsensitive)
            .replacingOccurrences(of: "the person", with: "you", options: .caseInsensitive)
            .replacingOccurrences(of: "the user", with: "you", options: .caseInsensitive)
            .replacingOccurrences(of: "their words", with: "your words", options: .caseInsensitive)
            .replacingOccurrences(of: "their week", with: "your week", options: .caseInsensitive)
            .replacingOccurrences(of: "their life", with: "your life", options: .caseInsensitive)
            .replacingOccurrences(of: "they are", with: "you are", options: .caseInsensitive)
            .replacingOccurrences(of: "they're", with: "you're", options: .caseInsensitive)
            .replacingOccurrences(of: "they feel", with: "you feel", options: .caseInsensitive)
            .replacingOccurrences(of: "they felt", with: "you felt", options: .caseInsensitive)
            .replacingOccurrences(of: "they wrote", with: "you wrote", options: .caseInsensitive)
            .replacingOccurrences(of: #"\btheir\b"#, with: "your", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bthey\b"#, with: "you", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "the source mentions", with: "you wrote", options: .caseInsensitive)
            .replacingOccurrences(of: "this suggests that you are", with: "it sounds like you're", options: .caseInsensitive)
            .replacingOccurrences(of: "this suggests you are", with: "it sounds like you're", options: .caseInsensitive)
            .replacingOccurrences(of: "this suggests", with: "it sounds like", options: .caseInsensitive)
            .replacingOccurrences(of: "emotional weariness", with: "tiredness", options: .caseInsensitive)
            .replacingOccurrences(of: "mental health", with: "well-being", options: .caseInsensitive)
            // "significant"/"patterns indicate" are banned explicitly in DAILY_NUDGE_SYSTEM
            // and WEEKLY_DIGEST_SYSTEM but were unguarded here — another gap
            // InsightValidationTests found (no repair, no validator check, either prompt).
            // "significant" alone is NOT rewritten unconditionally — unlike the other phrases
            // here, it's an ordinary word with everyday non-clinical use, and every prompt also
            // instructs the model to quote the writer's own words; a global replace would
            // silently corrupt a genuine quote like "this felt significant to me". Scoped to
            // the two clinical collocations the prompts' own example phrasing implies instead.
            .replacingOccurrences(of: "patterns indicate", with: "it looks like", options: .caseInsensitive)
            .replacingOccurrences(of: #"\bsomething significant\b"#, with: "something real", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\bsignificant pattern"#, with: "real pattern", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanedMonthlyReportOutput() -> String {
        var result = cleanedInsightOutput()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let headers = InsightService.monthlyReportSectionLabels.flatMap { Array($0.values) }

        for header in headers {
            result = result.replacingOccurrences(of: "\(header)\n", with: "\(header):\n")
            result = result.replacingOccurrences(of: "\(header) -", with: "\(header):")
        }

        result = result
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed != "---"
            }
            .joined(separator: "\n")

        return result
    }

    func cleanedDigestOutput() -> String {
        var result = cleanedInsightOutput()
            .replacingOccurrences(of: "\u{2019}", with: "'")  // curly → straight apostrophe
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let headers = InsightService.weeklyDigestSectionLabels.flatMap { Array($0.values) }

        for header in headers {
            result = result.replacingOccurrences(of: "\(header)\n", with: "\(header):\n")
            result = result.replacingOccurrences(of: "\(header) -", with: "\(header):")
        }

        result = result
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed != "---"
            }
            .joined(separator: "\n")

        return softenDigestFragments(result)
    }

    private func softenDigestFragments(_ text: String) -> String {
        let replacements: [(String, String)] = [
            ("YOUR ENERGY:\nDrained, from your words", "YOUR ENERGY:\nYou sound drained this week, especially in the places where your words keep circling back to pressure and recovery."),
            ("YOUR ENERGY: Drained, from your words", "YOUR ENERGY: You sound drained this week, especially in the places where your words keep circling back to pressure and recovery."),
            ("YOUR ENERGY:\nDrained", "YOUR ENERGY:\nYou sound drained this week, and it makes sense given how much you have been carrying."),
            ("YOUR ENERGY: Drained", "YOUR ENERGY: You sound drained this week, and it makes sense given how much you have been carrying."),
            ("WHAT'S BUILDING:\nPositive Patterns and Awareness", "WHAT'S BUILDING:\nYou are starting to notice what actually helps you steady yourself, even if it is still hard to make room for it."),
            ("WHAT'S BUILDING: Positive Patterns and Awareness", "WHAT'S BUILDING: You are starting to notice what actually helps you steady yourself, even if it is still hard to make room for it.")
        ]

        return replacements.reduce(text) { partial, replacement in
            partial.replacingOccurrences(of: replacement.0, with: replacement.1, options: .caseInsensitive)
        }
    }
}

extension Entry {
    var insightContext: String {
        var parts: [String] = []
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plain.isEmpty {
            parts.append(plain)
        }

        for (index, voiceNote) in voiceNotes.enumerated() {
            let transcript = voiceNote.transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translation = voiceNote.englishTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !transcript.isEmpty || !translation.isEmpty else { continue }

            // Skip transcript block when the entry text IS the transcript (pure voice entry)
            // to avoid sending the same content twice to the LLM.
            let transcriptIsAlreadyEntryText = !transcript.isEmpty && transcript == plain
            if transcriptIsAlreadyEntryText && translation.isEmpty { continue }

            var block = "Voice note \(index + 1):"
            if let languageName = voiceNote.languageName, !languageName.isEmpty {
                block += "\nLanguage: \(languageName)"
            }
            if !transcript.isEmpty {
                block += "\nTranscript: \(transcript)"
            }
            if !translation.isEmpty, translation != transcript {
                block += "\nEnglish translation: \(translation)"
            }
            parts.append(block)
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Grounded daily nudge (Gemma)
//
// On Gemma the factual part of a daily reflection is a verbatim quote, enforced by a GBNF grammar
// whose only allowed quotes are sentences cut from the user's own entry — so it can't swap people,
// turn a plan into an event, or invent a scene; those were the measured failure modes of every
// free-paraphrase prompt (tools/llmrig/README.md). After the quote the grammar allows only
// "That sounds …"/"You seem …" plus an optional "Maybe …"/"Try …", in lowercase letters: no
// capitals means no names, so nobody can be credited with anything outside the quote.

extension InsightService {
    static let groundedNudgePrefix = "You wrote, \""
    static let groundedNudgeMaxQuoteChars = 200
    static let groundedNudgeMinQuoteWords = 4
    // Bounds the grammar's size. Entries rarely have more quotable sentences than this; a long
    // one just offers its first 24.
    static let groundedNudgeMaxQuoteOptions = 24
    private static let groundedNudgeWindowWords = 25

    /// The Gemma plan for a daily nudge, with the quote options its validator needs.
    /// English only: the grammar's fixed phrases and lowercase-only character class are English.
    /// Other languages keep DAILY_NUDGE_SYSTEM on Gemma (`.samePrompt`) — not yet measured.
    static func groundedNudgePlan(recent: [Entry], background: [Entry], recentNudges: [String]) -> (plan: LocalLLMService.GemmaPlan, quoteOptions: [String]) {
        let target = responseLanguageTarget(from: recent + background) ?? responseLanguageTargetFromCurrentLocale()
        guard (target?.code ?? "en") == "en" else { return (.samePrompt, []) }
        let source = groundedNudgeSourceEntries(recent)
        let options = groundedNudgeQuoteOptions(from: source, excludingQuotesIn: recentNudges)
        guard !options.isEmpty else { return (.unsuitable, []) }
        return (.grammarConstrained(userMessage: groundedNudgeUserMessage(source), grammar: groundedNudgeGrammar(quotes: options)), options)
    }

    /// The most recent entry plus any others written the same day. Only these are quoted: with
    /// earlier entries in view, Gemma blended yesterday into today ("working from home" pulled
    /// from the previous entry).
    static func groundedNudgeSourceEntries(_ recent: [Entry]) -> [Entry] {
        guard let newest = recent.first else { return [] }
        return recent.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: newest.createdAt) }
    }

    static func groundedNudgeUserMessage(_ source: [Entry]) -> String {
        let isToday = source.first.map { Calendar.current.isDateInToday($0.createdAt) } ?? true
        let heading: String
        switch (isToday, source.count) {
        case (true, 1): heading = "Today's journal entry:"
        case (true, _): heading = "Today's journal entries:"
        case (false, 1): heading = "Most recent journal entry:"
        case (false, _): heading = "Most recent journal entries:"
        }
        return "\(heading)\n\(formatEntries(source, maxChars: 3_000))\n\n\(DAILY_NUDGE_GEMMA_INSTRUCTIONS)"
    }

    /// Verbatim sentences (or clause/word-window chunks of over-long ones) from the entries,
    /// deduped, minus any quoted by a recent nudge so routine entries ("Usual gym…") don't
    /// produce the same reflection two days running — unless that would leave nothing.
    static func groundedNudgeQuoteOptions(from entries: [Entry], excludingQuotesIn recentNudges: [String] = []) -> [String] {
        var seen = Set<String>()
        var options: [String] = []
        for entry in entries {
            for quote in groundedQuoteCandidates(of: entry) where seen.insert(quote).inserted {
                options.append(quote)
            }
        }
        let fresh = options.filter { option in
            !recentNudges.contains { $0.hasPrefix(groundedNudgePrefix + option + "\"") }
        }
        return Array((fresh.isEmpty ? options : fresh).prefix(groundedNudgeMaxQuoteOptions))
    }

    /// Quotable sentences from an entry's text plus any voice transcript that isn't the text itself.
    static func groundedQuoteCandidates(of entry: Entry) -> [String] {
        var texts = [entry.text]
        for note in entry.voiceNotes {
            if let transcript = note.transcript, !transcript.isEmpty, transcript != entry.text {
                texts.append(transcript)
            }
        }
        return texts.flatMap(groundedNudgeQuoteCandidates(in:))
    }

    static func groundedNudgeQuoteCandidates(in text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let collapsed = rawLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let line = collapsed.replacing(/^(?:[-*•◦▪·☐☑✓✔]|\d{1,3}[.)]|\[[ xX]\])\s+/, with: "")
            guard !line.isEmpty else { continue }
            for sentence in splitAfter(line, boundaries: ".!?…", immediate: "。！？") {
                for chunk in fittedToQuoteLength(sentence) {
                    let trimmed = chunk.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—–-，、；："))
                    // Chinese/Japanese don't put spaces between words, so "4 words" is measured
                    // as 8 characters there instead.
                    let longEnough = containsCJK(trimmed)
                        ? trimmed.count >= groundedMinCJKQuoteChars
                        : trimmed.split(separator: " ").count >= groundedNudgeMinQuoteWords
                    if longEnough && trimmed.count <= groundedNudgeMaxQuoteChars {
                        result.append(trimmed)
                    }
                }
            }
        }
        return result
    }

    static let groundedMinCJKQuoteChars = 8
    private static let groundedCJKWindowChars = 60

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF, 0x1100...0x11FF: return true
            default: return false
            }
        }
    }

    /// Splits after any `boundaries` character that's followed by a space, and right after any
    /// `immediate` character (CJK punctuation, which takes no space), keeping every character —
    /// concatenating the pieces reproduces `text` exactly, so any run of pieces is verbatim.
    private static func splitAfter(_ text: String, boundaries: String, immediate: String = "") -> [String] {
        var pieces: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            if immediate.contains(c) || (c == " " && i > 0 && boundaries.contains(chars[i - 1])) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// A sentence within the quote limit as-is; a longer one cut into consecutive clause runs;
    /// a clause still too long (unpunctuated voice transcripts) cut into word windows.
    private static func fittedToQuoteLength(_ sentence: String) -> [String] {
        guard sentence.count > groundedNudgeMaxQuoteChars else { return [sentence] }
        var chunks: [String] = []
        var current = ""
        for clause in splitAfter(sentence, boundaries: ",;:—–", immediate: "，、；：") {
            if clause.count > groundedNudgeMaxQuoteChars {
                if !current.isEmpty { chunks.append(current); current = "" }
                if !clause.contains(" ") {
                    // Unspaced CJK run: fixed character windows instead of word windows.
                    let chars = Array(clause)
                    stride(from: 0, to: chars.count, by: groundedCJKWindowChars).forEach { start in
                        chunks.append(String(chars[start..<min(start + groundedCJKWindowChars, chars.count)]))
                    }
                    continue
                }
                let words = clause.split(separator: " ")
                stride(from: 0, to: words.count, by: groundedNudgeWindowWords).forEach { start in
                    chunks.append(words[start..<min(start + groundedNudgeWindowWords, words.count)].joined(separator: " "))
                }
            } else if current.count + clause.count > groundedNudgeMaxQuoteChars {
                chunks.append(current)
                current = clause
            } else {
                current += clause
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static func groundedNudgeGrammar(quotes: [String]) -> String {
        let alternatives = quotes.map(gbnfLiteral).joined(separator: " | ")
        return """
        root ::= "You wrote, \\"" quote "\\" " feel (" " tip)?
        quote ::= \(alternatives)
        feel ::= ("That sounds " | "You seem ") words "."
        tip ::= ("Maybe " | "Try ") words "."
        words ::= [a-z0-9 ,;:'’()-]{6,150}
        """
    }

    private static func gbnfLiteral(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The part of a nudge that may leave the app (home-screen widget, lock-screen preview): a
    /// grounded nudge's opening quote is the user's own journal sentence, so outside the app only
    /// the "You seem…/That sounds…" line after it is shown. The line after the quote can't contain
    /// a double quote (the grammar's character class excludes it), so the quote ends at the last
    /// `" `. Any other nudge is returned unchanged.
    static func nudgeTextForOutsideApp(_ text: String) -> String {
        // (opening, closer) for English and every localized grounded nudge. Neither the English
        // line after the quote nor the fixed localized lines contain their language's closing mark.
        let shapes = [(groundedNudgePrefix, "\" ")] + groundedLocales.values.map { ($0.youWrote + $0.open, $0.close + $0.joiner) }
        for (opening, closer) in shapes where text.hasPrefix(opening) {
            guard let close = text.range(of: closer, options: .backwards),
                  close.lowerBound > text.index(text.startIndex, offsetBy: opening.count)
            else { continue }
            let rest = text[close.upperBound...].trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? text : rest
        }
        return text
    }

    /// Re-checks the grammar's guarantees after generation. The wrapper's sampler silently drops a
    /// grammar that fails to parse, and unconstrained Gemma asked for a quote invents one — so
    /// "the grammar should guarantee it" isn't trusted: the quote must be exactly one of the
    /// options and what follows must have the grammar's shape and no journal-writer first person.
    static func validateGroundedNudge(_ text: String, quoteOptions: [String]) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quote = quoteOptions.first(where: { trimmed.hasPrefix(groundedNudgePrefix + $0 + "\" ") }) else {
            throw InsightError.incompleteResponse
        }
        let afterQuote = String(trimmed.dropFirst(groundedNudgePrefix.count + quote.count + 2))
        // After the quote Mirror is talking to "you", so any first person there is the model
        // slipping into the writer's voice ("…and my stomach still hurts"). Stricter than
        // containsJournalWriterFirstPerson, whose "my" patterns only cover a fixed noun list.
        guard afterQuote.hasPrefix("That sounds ") || afterQuote.hasPrefix("You seem "),
              endsAsCompleteSentence(afterQuote),
              !containsGroundedFirstPerson(afterQuote)
        else { throw InsightError.incompleteResponse }
        return trimmed
    }

    private static let groundedNudgeFirstPersonWords: Set<String> = [
        "i", "i'm", "i've", "i'd", "i'll", "me", "my", "mine", "myself",
    ]

    private static func containsGroundedFirstPerson(_ text: String) -> Bool {
        let words = Set(text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && $0 != "'" }
            .map(String.init))
        return !words.isDisjoint(with: groundedNudgeFirstPersonWords)
    }

    // MARK: Weekly digest

    static let groundedDigestMaxOptionsPerBucket = 24
    static let groundedDigestHardMoodWords = ["drained", "stressed", "tired"]
    static let groundedDigestGoodMoodWords = ["light", "calm", "content"]

    /// English-only, like the nudge. Quote options come from this week's entries, split by the
    /// entry's mood so the grammar can bind "most drained" to hard-mood sentences, "most light" to
    /// good-mood ones, WHAT'S BUILDING to good-mood and WATCH OUT FOR to hard-mood. An empty bucket
    /// (a week of only good days) falls back to every option rather than dropping the section.
    static func groundedDigestPlan(weekEntries: [Entry], languageSource: [Entry]) -> (plan: LocalLLMService.GemmaPlan, quoteOptions: [String]) {
        let target = responseLanguageTarget(from: languageSource) ?? responseLanguageTargetFromCurrentLocale()
        guard (target?.code ?? "en") == "en" else { return (.samePrompt, []) }
        var all: [String] = [], good: [String] = [], hard: [String] = []
        var seen = Set<String>()
        for entry in weekEntries {
            for quote in groundedQuoteCandidates(of: entry) where seen.insert(quote).inserted {
                all.append(quote)
                guard let mood = entry.mood else { continue }
                if MirrorTheme.negativeMoods.contains(mood) { hard.append(quote) } else { good.append(quote) }
            }
        }
        guard !all.isEmpty else { return (.unsuitable, []) }
        let cap = groundedDigestMaxOptionsPerBucket
        let goodOptions = Array((good.isEmpty ? all : good).prefix(cap))
        let hardOptions = Array((hard.isEmpty ? all : hard).prefix(cap))
        let message = "This week's journal entries:\n\(formatEntries(weekEntries, maxChars: 4_000))\n\n\(WEEKLY_DIGEST_GEMMA_INSTRUCTIONS)"
        let grammar = groundedDigestGrammar(good: goodOptions, hard: hardOptions)
        return (.grammarConstrained(userMessage: message, grammar: grammar), Array(Set(goodOptions + hardOptions)))
    }

    static func groundedDigestGrammar(good: [String], hard: [String]) -> String {
        let labels = weeklyDigestSectionLabels.map { $0["en"] ?? "" }
        let alt: ([String]) -> String = { $0.map(gbnfLiteral).joined(separator: " | ") }
        let hardWords = groundedDigestHardMoodWords.map { "\"\($0)\"" }.joined(separator: " | ")
        let goodWords = groundedDigestGoodMoodWords.map { "\"\($0)\"" }.joined(separator: " | ")
        return """
        root ::= theme "\\n" energy "\\n" building "\\n" watch "\\n" boost "\\n" next
        theme ::= "\(labels[0]): A week of " words "."
        energy ::= "\(labels[1]): You seemed most " ((\(hardWords)) " when you wrote, \\"" hardq | (\(goodWords)) " when you wrote, \\"" goodq) "\\" " ("That sounds " | "It sounds like ") words "."
        building ::= "\(labels[2]): You wrote, \\"" goodq "\\" " ("That sounds like " | "It feels like ") words "."
        watch ::= "\(labels[3]): You wrote, \\"" hardq "\\" " ("Watch whether " | "Notice if ") words "."
        boost ::= "\(labels[4]): " ("Try " | "Maybe ") words "."
        next ::= "\(labels[5]): " ("Next week, " | "Maybe ") words "."
        goodq ::= \(alt(good))
        hardq ::= \(alt(hard))
        words ::= [a-z0-9 ,;:'’()-]{8,120}
        """
    }

    // MARK: Ask

    static let groundedAskPrefix = "The closest things you've written: "
    static let groundedAskMaxOptions = 40

    private static let askQuestionStopWords: Set<String> = [
        "how", "what", "when", "where", "who", "whom", "why", "which", "has", "have", "had", "been",
        "my", "me", "i", "i'm", "am", "is", "are", "was", "were", "do", "does", "did", "doing", "going",
        "the", "a", "an", "to", "of", "at", "in", "on", "for", "with", "about", "from", "and", "or",
        "lately", "recently", "ever", "any", "anything", "something", "it", "its", "this", "that",
        "these", "those", "be", "feel", "feeling", "felt", "think", "things", "thing", "much", "many",
        "can", "could", "should", "would", "will", "more", "most", "time", "times", "really",
    ]
    static let askHardLeanWords: Set<String> = [
        "stress", "stressed", "stressing", "stressful", "worried", "worry", "worrying", "anxious",
        "anxiety", "sad", "upset", "angry", "anger", "frustrated", "frustrating", "overwhelmed",
        "tired", "exhausted", "drained", "lonely", "scared", "afraid", "hurt", "bothering",
        "bother", "struggle", "struggling", "difficult", "hardest", "worst", "down",
    ]
    static let askGoodLeanWords: Set<String> = [
        "happy", "happiest", "joy", "joyful", "grateful", "gratitude", "calm", "peaceful", "excited",
        "proud", "fun", "best", "love", "loved", "enjoy", "enjoyed", "glad", "hopeful",
    ]

    enum AskLean { case hard, good }

    static func askLean(of question: String) -> AskLean? {
        let words = Set(question.lowercased().split { !$0.isLetter }.map(String.init))
        if !words.isDisjoint(with: askHardLeanWords) { return .hard }
        if !words.isDisjoint(with: askGoodLeanWords) { return .good }
        return nil
    }

    // Irregular past forms common in journal writing, so "How has my sleep been?" finds "slept".
    private static let askIrregularStems: [String: String] = [
        "slept": "sleep", "woke": "wake", "ate": "eat", "went": "go", "gone": "go", "ran": "run",
        "met": "meet", "spent": "spend", "bought": "buy", "drank": "drink", "wrote": "write",
        "saw": "see", "seen": "see", "lost": "lose", "left": "leave", "told": "tell", "said": "say",
        "made": "make", "took": "take", "got": "get", "came": "come", "gave": "give", "found": "find",
        "cried": "cry", "tried": "try", "thought": "think", "brought": "bring", "taught": "teach",
        "fought": "fight", "kept": "keep", "sat": "sit", "paid": "pay", "sold": "sell", "held": "hold",
    ]

    static func askStem(_ word: String) -> String {
        let lower = word.lowercased()
        if let irregular = askIrregularStems[lower] { return irregular }
        for suffix in ["ing", "ed", "es", "s", "ly"] where lower.hasSuffix(suffix) && lower.count - suffix.count >= 3 {
            return String(lower.dropLast(suffix.count))
        }
        return lower
    }

    private static func askStems(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && $0 != "'" }.map { askStem(String($0)) })
    }

    /// The question's content-word stems, widened with each word's nearest English word-embedding
    /// neighbours when that embedding is available ("sleep" → nap, asleep, night, restful…).
    /// `embeddingAvailable` is false on devices/simulators without the asset — then the terms are
    /// stems only, too narrow to justify a no-answer.
    static func askTerms(for question: String) -> (terms: Set<String>, embeddingAvailable: Bool) {
        let words = question.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
            .filter { $0.count >= 3 && !askQuestionStopWords.contains($0) }
        var terms = Set(words.map(askStem))
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return (terms, false) }
        for word in words {
            embedding.neighbors(for: word, maximumCount: 8).forEach { terms.insert(askStem($0.0)) }
        }
        return (terms, true)
    }

    static func askEntryMentions(_ terms: Set<String>, _ entry: Entry) -> Bool {
        !askStems(in: entry.insightContext).isDisjoint(with: terms)
    }

    /// English-only. `noAnswer` means Gemma shouldn't be asked at all (see the check below) —
    /// "How is my guitar practice going?" with no guitar anywhere. Otherwise the answer is 1–2
    /// dated verbatim quotes.
    static func groundedAskPlan(question: String, pool: [Entry], languageCode: String?) -> (plan: LocalLLMService.GemmaPlan, quoteOptions: [String], noAnswer: Bool) {
        guard (languageCode ?? "en") == "en" else { return (.samePrompt, [], false) }
        let lean = askLean(of: question)
        let (terms, embeddingAvailable) = askTerms(for: question)
        let mentioning = terms.isEmpty ? [] : pool.filter { askEntryMentions(terms, $0) }
        // No-answer only when the check is trustworthy: an embedding to widen the terms with, a
        // question with content words and no emotional lean, and still no entry mentioning any of
        // it. Otherwise Gemma answers with the closest sentences, framed as exactly that.
        if embeddingAvailable, lean == nil, !terms.isEmpty, mentioning.isEmpty {
            return (.unsuitable, [], true)
        }
        var candidates: [Entry]
        switch lean {
        case .hard: candidates = pool.filter { $0.mood.map(MirrorTheme.negativeMoods.contains) ?? false }
        case .good: candidates = pool.filter { $0.mood.map { !MirrorTheme.negativeMoods.contains($0) } ?? false }
        case nil: candidates = mentioning + pool.filter { entry in !mentioning.contains { $0.id == entry.id } }
        }
        if candidates.isEmpty { candidates = pool }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "d MMM"
        let perEntry = candidates.map { ($0, groundedQuoteCandidates(of: $0)) }
        var options: [String] = []
        var seen = Set<String>()
        for round in 0..<(perEntry.map(\.1.count).max() ?? 0) {
            for (entry, quotes) in perEntry where round < quotes.count && seen.insert(quotes[round]).inserted {
                options.append("On \(dayFormatter.string(from: entry.createdAt)), you wrote, \"\(quotes[round])\"")
            }
        }
        options = Array(options.prefix(groundedAskMaxOptions))
        guard !options.isEmpty else { return (.unsuitable, [], true) }
        let message = "Journal entries:\n\(formatEntries(candidates, maxChars: 3_800))\n\n\(ASK_GEMMA_INSTRUCTIONS)Question: \(question)"
        let grammar = """
        root ::= "\(groundedAskPrefix)" datedq (" " datedq)?
        datedq ::= \(options.map(gbnfLiteral).joined(separator: " | "))
        """
        return (.grammarConstrained(userMessage: message, grammar: grammar), options, false)
    }

    /// The prefix, then one or two quote options separated by a single space, nothing else. The
    /// grammar can't forbid picking the same quote twice (the simulator pipeline did, twice), so a
    /// repeat is dropped here rather than shown.
    static func validateGroundedAsk(_ text: String, quoteOptions: [String]) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(groundedAskPrefix) else { throw InsightError.incompleteResponse }
        var rest = Substring(trimmed.dropFirst(groundedAskPrefix.count))
        var quotes: [String] = []
        while !rest.isEmpty {
            guard quotes.count < 2, let quote = quoteOptions.first(where: { rest.hasPrefix($0) }) else { throw InsightError.incompleteResponse }
            rest = rest.dropFirst(quote.count)
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
            if !quotes.contains(quote) { quotes.append(quote) }
        }
        guard !quotes.isEmpty else { throw InsightError.incompleteResponse }
        return groundedAskPrefix + quotes.joined(separator: " ")
    }

    // MARK: Monthly report

    // A MOMENT body is "On 23 Sep, you wrote, \"<quote>\" It seems to have <≤16 words>." and must
    // stay inside validateMonthlyReport's 350-char section limit, so monthly quotes are shorter.
    static let groundedMonthlyMaxQuoteChars = 170
    static let groundedMonthlyMaxMoments = 40
    // Kept out of WHAT WANTS TO BE RELEASED, whose fixed opener is "Maybe it's time to let go of":
    // a simulator run paired it with "Grandpa's birthday would have been today." Grief isn't a
    // friction to drop. These entries still reach A MOMENT THAT SHIFTED SOMETHING.
    static let groundedMonthlyGriefMoods: Set<String> = ["Sad", "Numb"]

    /// English-only. Options are taken round-robin across the month's entries (first sentence of
    /// each entry, then second…) so a busy last week can't crowd out the rest of the month.
    static func groundedMonthlyPlan(monthEntries: [Entry]) -> (plan: LocalLLMService.GemmaPlan, quoteOptions: [String]) {
        let target = responseLanguageTarget(from: monthEntries) ?? responseLanguageTargetFromCurrentLocale()
        guard (target?.code ?? "en") == "en" else { return (.samePrompt, []) }
        let entries = monthEntries.sorted { $0.createdAt > $1.createdAt }
        let perEntry = entries.map { entry in
            (entry, groundedQuoteCandidates(of: entry).filter { $0.count <= groundedMonthlyMaxQuoteChars })
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "d MMM"
        var moments: [String] = [], good: [String] = [], hard: [String] = []
        var seen = Set<String>()
        let rounds = perEntry.map(\.1.count).max() ?? 0
        for round in 0..<rounds {
            for (entry, quotes) in perEntry where round < quotes.count {
                let quote = quotes[round]
                guard seen.insert(quote).inserted else { continue }
                moments.append("On \(dayFormatter.string(from: entry.createdAt)), you wrote, \"\(quote)\"")
                guard let mood = entry.mood else { continue }
                if !MirrorTheme.negativeMoods.contains(mood) {
                    good.append(quote)
                } else if !groundedMonthlyGriefMoods.contains(mood) {
                    hard.append(quote)
                }
            }
        }
        guard !moments.isEmpty else { return (.unsuitable, []) }
        let all = Array(seen)
        let cap = groundedDigestMaxOptionsPerBucket
        let goodOptions = Array((good.isEmpty ? all : good).prefix(cap))
        let hardOptions = Array((hard.isEmpty ? all : hard).prefix(cap))
        let momentOptions = Array(moments.prefix(groundedMonthlyMaxMoments))
        let message = "This month's journal entries:\n\(formatEntries(entries, maxChars: 5_000))\n\n\(MONTHLY_REPORT_GEMMA_INSTRUCTIONS)"
        let grammar = groundedMonthlyGrammar(moments: momentOptions, good: goodOptions, hard: hardOptions)
        return (.grammarConstrained(userMessage: message, grammar: grammar), momentOptions + goodOptions + hardOptions)
    }

    static func groundedMonthlyGrammar(moments: [String], good: [String], hard: [String]) -> String {
        let labels = monthlyReportSectionLabels.map { $0["en"] ?? "" }
        let alt: ([String]) -> String = { $0.map(gbnfLiteral).joined(separator: " | ") }
        return """
        root ::= image "\\n" tension "\\n" moment "\\n" becoming "\\n" release "\\n" question
        image ::= "\(labels[0]): A " phrase "."
        tension ::= "\(labels[1]): You seem pulled between " phrase "."
        moment ::= "\(labels[2]): " momentq " " ("That might have " | "It seems to have ") words "."
        becoming ::= "\(labels[3]): You wrote, \\"" goodq "\\" You seem to be becoming someone who " words "."
        release ::= "\(labels[4]): You wrote, \\"" hardq "\\" Maybe it's time to let go of " words "."
        question ::= "\(labels[5]): " ("How can you " | "What would it take for you to " | "Where could you " | "What if you ") phrase "?"
        momentq ::= \(alt(moments))
        goodq ::= \(alt(good))
        hardq ::= \(alt(hard))
        words ::= w (","? " " w){3,16}
        phrase ::= w (","? " " w){2,14}
        w ::= "a" | [a-z0-9’'-]{2,20}
        """
    }

    /// Re-checks the monthly grammar's guarantees: six lines in label order with their fixed
    /// openers, every quote (moments include their date) exactly an option, the usual 15–350 char
    /// complete-sentence bodies, a question that ends in "?", and no first person outside quotes.
    static func validateGroundedMonthly(_ text: String, quoteOptions: [String]) throws -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let labels = monthlyReportSectionLabels.map { $0["en"] ?? "" }
        guard lines.count == labels.count else { throw InsightError.incompleteResponse }
        // Fixed text before the quote option, per quoted section. A MOMENT option already carries
        // its own "On 23 Sep, you wrote, \"…\"" wrapper, so its opener is empty and it closes on " ".
        let openers: [Int: String] = [2: "", 3: "You wrote, \"", 4: "You wrote, \""]
        for (index, line) in lines.enumerated() {
            let head = labels[index] + ": "
            guard line.hasPrefix(head) else { throw InsightError.incompleteResponse }
            let body = String(line.dropFirst(head.count))
            guard body.count >= 15, body.count <= 350, endsAsCompleteSentence(body) else { throw InsightError.incompleteResponse }
            if index == 5 { guard body.hasSuffix("?") else { throw InsightError.incompleteResponse } }
            var outsideQuote = body
            if let opener = openers[index] {
                guard body.hasPrefix(opener) else { throw InsightError.incompleteResponse }
                let afterOpener = body.dropFirst(opener.count)
                let closing = index == 2 ? " " : "\" "
                guard let quote = quoteOptions.first(where: { afterOpener.hasPrefix($0 + closing) }) else { throw InsightError.incompleteResponse }
                outsideQuote = opener + afterOpener.dropFirst(quote.count + closing.count)
            }
            guard !containsGroundedFirstPerson(outsideQuote) else { throw InsightError.incompleteResponse }
        }
        return lines.joined(separator: "\n")
    }

    /// Re-checks the digest grammar's guarantees: six lines in label order, every quote exactly one
    /// of the options, the validator's usual 20–400 char complete-sentence bodies, and no first
    /// person outside the quotes (inside them it's the writer's own words).
    static func validateGroundedDigest(_ text: String, quoteOptions: [String]) throws -> String {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let labels = weeklyDigestSectionLabels.map { $0["en"] ?? "" }
        guard lines.count == labels.count else { throw InsightError.incompleteResponse }
        let moodWords = (groundedDigestHardMoodWords + groundedDigestGoodMoodWords).joined(separator: "|")
        let quotePrefixes: [Int: String] = [1: "You seemed most (?:\(moodWords)) when you wrote, \"", 2: "You wrote, \"", 3: "You wrote, \""]
        for (index, line) in lines.enumerated() {
            let head = labels[index] + ": "
            guard line.hasPrefix(head) else { throw InsightError.incompleteResponse }
            let body = String(line.dropFirst(head.count))
            guard body.count >= 20, body.count <= 400, endsAsCompleteSentence(body) else { throw InsightError.incompleteResponse }
            var outsideQuote = body
            if let pattern = quotePrefixes[index] {
                guard let opener = body.range(of: "^" + pattern, options: .regularExpression) else { throw InsightError.incompleteResponse }
                let afterOpener = body[opener.upperBound...]
                guard let quote = quoteOptions.first(where: { afterOpener.hasPrefix($0 + "\" ") }) else { throw InsightError.incompleteResponse }
                outsideQuote = String(body[..<opener.upperBound]) + afterOpener.dropFirst(quote.count + 2)
            }
            guard !containsGroundedFirstPerson(outsideQuote) else { throw InsightError.incompleteResponse }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Grounded insights in other languages (Gemma)
//
// The English grammar path has the model write a short free line after the quote, kept to
// lowercase letters so no names can appear. That doesn't carry over: German capitalises every
// noun (the lowercase class mangled "unruhigen Abend" into "unruhigenabend"), and a Japanese
// grammar with a negated character class was silently dropped by the sampler. What did work in
// every language measured (de/es/ja/ru/zh on tools/llmrig, 2026-09-27) is the one thing the
// model is reliable at: picking which of the entry's own sentences matters, from a grammar of
// literal sentences only. So outside English, Gemma only picks the quote(s); everything around
// them is fixed, pre-translated text chosen by the entry's mood. Baseline for comparison — the
// shared prompt on Gemma in German/Spanish/Japanese invented scenes just like English ("Der Duft
// von frisch gemähtem Gras…", "El sol se filtraba…", "夕焼けが空を染めて…").
// Monthly reports in other languages still use the shared prompt (not yet measured).

enum GroundedMoodBucket: Hashable {
    case tired, stressed, sad, good, neutral

    init(mood: String?) {
        switch mood {
        case "Drained": self = .tired
        case "Anxious", "Overwhelmed", "Frustrated": self = .stressed
        case "Sad", "Numb": self = .sad
        case .some(let mood) where !MirrorTheme.negativeMoods.contains(mood): self = .good
        default: self = .neutral
        }
    }

    var isHard: Bool { self == .tired || self == .stressed || self == .sad }
}

/// Fixed text for one language. `pick*` are prompts (the model's only instructions); the rest
/// is shown to the user verbatim around the quotes the model picked. `neutral` keys double as
/// "mixed week" for the digest.
struct GroundedLocale {
    let open: String
    let close: String
    let joiner: String
    let youWrote: String
    let moodWord: [GroundedMoodBucket: String]
    let pickNudge: String
    let pickNeutral: String
    let pickDigest: String
    let pickAsk: String
    let entryLabel: String
    let weekLabel: String
    let entriesLabel: String
    let questionLabel: String
    let feel: [GroundedMoodBucket: [String]]
    let theme: [GroundedMoodBucket: String]
    let energyHard: String
    let energyGood: String
    let buildingSuffix: String
    let watchSuffix: String
    let boost: [GroundedMoodBucket: String]
    let nextWeek: [GroundedMoodBucket: String]
    let askPrefix: String
}

extension InsightService {
    static let groundedLocales: [String: GroundedLocale] = [
        "de": GroundedLocale(
            open: "„", close: "“", joiner: " ",
            youWrote: "Du hast geschrieben: ",
            moodWord: [.tired: "erschöpft", .stressed: "gestresst", .sad: "traurig", .good: "gut"],
            pickNudge: "Kopiere Wort für Wort den Satz aus dem Tagebucheintrag, der am besten erklärt, warum sich die Person {mood} fühlte. Gib nur diesen Satz aus.",
            pickNeutral: "Kopiere Wort für Wort den Satz aus dem Tagebucheintrag, der das Wichtigste des Tages zeigt. Gib nur diesen Satz aus.",
            pickDigest: "Kopiere drei Sätze Wort für Wort aus den Tagebucheinträgen, jeden in einer eigenen Zeile: zuerst den Satz, der zeigt, wann die Person am erschöpftesten wirkte, dann einen Satz über etwas Gutes, das wächst, dann einen Satz über etwas, das sie belasten könnte. Gib nur diese drei Sätze aus.",
            pickAsk: "Kopiere Wort für Wort den einen Satz (oder höchstens zwei Sätze) aus den Tagebucheinträgen, die die Frage am besten beantworten, jeden in einer eigenen Zeile. Gib nur diese Sätze aus.",
            entryLabel: "Tagebucheintrag:", weekLabel: "Tagebucheinträge dieser Woche:", entriesLabel: "Tagebucheinträge:", questionLabel: "Frage:",
            feel: [
                .tired: ["Das klingt nach einem Tag, der viel Kraft gekostet hat. Gönn dir heute Abend etwas Ruhe.", "Du wirkst ziemlich erschöpft. Ein ruhiger, langsamer Abend könnte guttun."],
                .stressed: ["Das klingt nach ziemlich viel auf einmal. Vielleicht hilft es, eine kleine Sache zuerst zu erledigen.", "Du wirkst unter Druck. Eine kurze Pause könnte dir helfen, durchzuatmen."],
                .sad: ["Das klingt schwer. Sei heute behutsam mit dir.", "Du wirkst niedergeschlagen. Es ist in Ordnung, es langsam angehen zu lassen."],
                .good: ["Das klingt nach einem guten Moment. Halte ihn fest.", "Du wirkst leichter. Vielleicht lohnt es sich zu merken, was dir gutgetan hat."],
                .neutral: ["Schön, dass du es aufgeschrieben hast.", "Das ist es wert, bemerkt zu werden."],
            ],
            theme: [.tired: "Eine Woche, die viel Kraft gekostet hat.", .stressed: "Eine Woche mit viel Druck.", .sad: "Eine schwere Woche.", .good: "Eine Woche mit guten Momenten.", .neutral: "Eine Woche mit Höhen und Tiefen."],
            energyHard: "Am schwersten wirkte es, als du schriebst: ",
            energyGood: "Am leichtesten wirkte es, als du schriebst: ",
            buildingSuffix: "Daran lässt sich anknüpfen.",
            watchSuffix: "Behalte das im Blick.",
            boost: [.tired: "Plane bewusst einen ruhigen Abend nur für dich ein.", .stressed: "Such dir eine kleine Aufgabe aus, die du heute abschließen kannst.", .sad: "Melde dich bei jemandem, dem du vertraust.", .good: "Mach mehr von dem, was dir diese Woche gutgetan hat.", .neutral: "Nimm dir fünf Minuten für etwas, das dir guttut."],
            nextWeek: [.tired: "Schütze deinen Schlaf und plane Pausen ein.", .stressed: "Nimm dir jeden Tag nur eine wichtige Sache vor.", .sad: "Sei geduldig mit dir und schreib weiter auf, wie es dir geht.", .good: "Halte fest, was funktioniert hat.", .neutral: "Achte darauf, was dir Energie gibt und was sie nimmt."],
            askPrefix: "Am nächsten kommt, was du geschrieben hast:"
        ),
        "es": GroundedLocale(
            open: "“", close: "”", joiner: " ",
            youWrote: "Escribiste: ",
            moodWord: [.tired: "agotada", .stressed: "estresada", .sad: "triste", .good: "bien"],
            pickNudge: "Copia palabra por palabra la frase de la entrada del diario que mejor explica por qué la persona se sintió {mood}. Escribe solo esa frase.",
            pickNeutral: "Copia palabra por palabra la frase de la entrada del diario que muestra lo más importante del día. Escribe solo esa frase.",
            pickDigest: "Copia palabra por palabra tres frases de las entradas del diario, cada una en su propia línea: primero la frase que muestra cuándo la persona parecía más agotada, luego una frase sobre algo bueno que está creciendo, y luego una frase sobre algo que podría estar pesándole. Escribe solo esas tres frases.",
            pickAsk: "Copia palabra por palabra la frase (o como máximo dos frases) de las entradas del diario que mejor responden a la pregunta, cada una en su propia línea. Escribe solo esas frases.",
            entryLabel: "Entrada del diario:", weekLabel: "Entradas del diario de esta semana:", entriesLabel: "Entradas del diario:", questionLabel: "Pregunta:",
            feel: [
                .tired: ["Suena a un día que te dejó sin energía. Esta noche date un respiro.", "Parece que fue agotador. Una tarde tranquila y sin prisas podría ayudarte."],
                .stressed: ["Suena a mucho a la vez. Quizás ayude empezar por una sola cosa pequeña.", "Parece que hay bastante presión. Una pausa corta podría ayudarte a respirar."],
                .sad: ["Suena duro. Trátate con cariño hoy.", "Parece un momento difícil. Está bien ir despacio."],
                .good: ["Suena a un buen momento. Vale la pena guardarlo.", "Parece que hubo algo de ligereza. Quizás valga la pena notar qué te ayudó."],
                .neutral: ["Gracias por escribirlo.", "Vale la pena fijarse en esto."],
            ],
            theme: [.tired: "Una semana que te pidió mucha energía.", .stressed: "Una semana con mucha presión.", .sad: "Una semana difícil.", .good: "Una semana con buenos momentos.", .neutral: "Una semana con altibajos."],
            energyHard: "Lo más pesado pareció cuando escribiste: ",
            energyGood: "Lo más ligero pareció cuando escribiste: ",
            buildingSuffix: "Ahí hay algo que puede crecer.",
            watchSuffix: "Vale la pena prestarle atención.",
            boost: [.tired: "Reserva una tarde tranquila solo para ti.", .stressed: "Elige una tarea pequeña que puedas terminar hoy.", .sad: "Escríbele a alguien de confianza.", .good: "Haz más de lo que te sentó bien esta semana.", .neutral: "Tómate cinco minutos para algo que te haga bien."],
            nextWeek: [.tired: "Cuida tu descanso y deja espacio para pausas.", .stressed: "Céntrate en una sola cosa importante cada día.", .sad: "Ten paciencia contigo y sigue escribiendo cómo estás.", .good: "Repite lo que funcionó.", .neutral: "Fíjate en qué te da energía y qué te la quita."],
            askPrefix: "Lo más cercano que has escrito:"
        ),
        "fr": GroundedLocale(
            open: "« ", close: " »", joiner: " ",
            youWrote: "Tu as écrit : ",
            moodWord: [.tired: "épuisée", .stressed: "stressée", .sad: "triste", .good: "bien"],
            pickNudge: "Recopie mot pour mot la phrase de l'entrée du journal qui explique le mieux pourquoi la personne s'est sentie {mood}. Écris seulement cette phrase.",
            pickNeutral: "Recopie mot pour mot la phrase de l'entrée du journal qui montre le plus important de la journée. Écris seulement cette phrase.",
            pickDigest: "Recopie mot pour mot trois phrases des entrées du journal, chacune sur sa propre ligne : d'abord la phrase qui montre quand la personne semblait le plus épuisée, puis une phrase sur quelque chose de bien qui grandit, puis une phrase sur quelque chose qui pourrait lui peser. Écris seulement ces trois phrases.",
            pickAsk: "Recopie mot pour mot la phrase (ou au plus deux phrases) des entrées du journal qui répondent le mieux à la question, chacune sur sa propre ligne. Écris seulement ces phrases.",
            entryLabel: "Entrée du journal :", weekLabel: "Entrées du journal de cette semaine :", entriesLabel: "Entrées du journal :", questionLabel: "Question :",
            feel: [
                .tired: ["On dirait une journée très fatigante. Accorde-toi un peu de repos ce soir.", "Ça a l'air d'avoir été épuisant. Une soirée calme pourrait te faire du bien."],
                .stressed: ["Ça fait beaucoup à la fois. Commencer par une seule petite chose pourrait aider.", "Tu sembles sous pression. Une courte pause pourrait t'aider à souffler."],
                .sad: ["Ça a l'air lourd. Prends soin de toi aujourd'hui.", "Ça semble difficile. C'est normal d'y aller doucement."],
                .good: ["Ça ressemble à un bon moment. Garde-le en tête.", "Ça semble plus léger. Note peut-être ce qui t'a fait du bien."],
                .neutral: ["Merci de l'avoir écrit.", "Ça vaut la peine de le remarquer."],
            ],
            theme: [.tired: "Une semaine qui t'a demandé beaucoup d'énergie.", .stressed: "Une semaine sous pression.", .sad: "Une semaine difficile.", .good: "Une semaine avec de bons moments.", .neutral: "Une semaine en dents de scie."],
            energyHard: "Le plus lourd semblait être quand tu as écrit : ",
            energyGood: "Le plus léger semblait être quand tu as écrit : ",
            buildingSuffix: "Il y a là quelque chose qui peut grandir.",
            watchSuffix: "Garde un œil là-dessus.",
            boost: [.tired: "Prévois une soirée calme rien que pour toi.", .stressed: "Choisis une petite tâche que tu peux terminer aujourd'hui.", .sad: "Écris à quelqu'un en qui tu as confiance.", .good: "Refais ce qui t'a fait du bien cette semaine.", .neutral: "Prends cinq minutes pour quelque chose qui te fait du bien."],
            nextWeek: [.tired: "Protège ton sommeil et prévois des pauses.", .stressed: "Concentre-toi sur une seule chose importante par jour.", .sad: "Prends ton temps et continue d'écrire comment tu vas.", .good: "Refais ce qui a marché.", .neutral: "Observe ce qui te donne de l'énergie et ce qui t'en prend."],
            askPrefix: "Ce que tu as écrit de plus proche :"
        ),
        "it": GroundedLocale(
            open: "“", close: "”", joiner: " ",
            youWrote: "Hai scritto: ",
            moodWord: [.tired: "esausta", .stressed: "stressata", .sad: "triste", .good: "bene"],
            pickNudge: "Copia parola per parola la frase della voce del diario che spiega meglio perché la persona si è sentita {mood}. Scrivi solo quella frase.",
            pickNeutral: "Copia parola per parola la frase della voce del diario che mostra la cosa più importante della giornata. Scrivi solo quella frase.",
            pickDigest: "Copia parola per parola tre frasi dalle voci del diario, ognuna su una riga: prima la frase che mostra quando la persona sembrava più esausta, poi una frase su qualcosa di buono che sta crescendo, poi una frase su qualcosa che potrebbe pesarle. Scrivi solo queste tre frasi.",
            pickAsk: "Copia parola per parola la frase (o al massimo due frasi) delle voci del diario che rispondono meglio alla domanda, ognuna su una riga. Scrivi solo quelle frasi.",
            entryLabel: "Voce del diario:", weekLabel: "Voci del diario di questa settimana:", entriesLabel: "Voci del diario:", questionLabel: "Domanda:",
            feel: [
                .tired: ["Sembra una giornata che ti ha tolto tante energie. Stasera concediti un po' di riposo.", "Sembra essere stato faticoso. Una serata tranquilla potrebbe farti bene."],
                .stressed: ["Sembra tanto tutto insieme. Forse aiuta iniziare da una sola piccola cosa.", "Sembra che ci sia parecchia pressione. Una breve pausa potrebbe aiutarti a respirare."],
                .sad: ["Sembra pesante. Oggi trattati con gentilezza.", "Sembra un momento difficile. Va bene prendersela con calma."],
                .good: ["Sembra un bel momento. Vale la pena tenerlo a mente.", "Sembra che ci sia stata un po' di leggerezza. Forse vale la pena notare cosa ti ha aiutato."],
                .neutral: ["Grazie per averlo scritto.", "Vale la pena notarlo."],
            ],
            theme: [.tired: "Una settimana che ti ha chiesto molte energie.", .stressed: "Una settimana con molta pressione.", .sad: "Una settimana difficile.", .good: "Una settimana con bei momenti.", .neutral: "Una settimana di alti e bassi."],
            energyHard: "Il momento più pesante sembrava quando hai scritto: ",
            energyGood: "Il momento più leggero sembrava quando hai scritto: ",
            buildingSuffix: "Qui c'è qualcosa che può crescere.",
            watchSuffix: "Vale la pena tenerlo d'occhio.",
            boost: [.tired: "Tieni libera una serata tranquilla solo per te.", .stressed: "Scegli un piccolo compito da finire oggi.", .sad: "Scrivi a qualcuno di cui ti fidi.", .good: "Fai di più di ciò che ti ha fatto bene questa settimana.", .neutral: "Prenditi cinque minuti per qualcosa che ti fa bene."],
            nextWeek: [.tired: "Proteggi il sonno e prevedi delle pause.", .stressed: "Concentrati su una sola cosa importante al giorno.", .sad: "Prenditi il tuo tempo e continua a scrivere come stai.", .good: "Ripeti ciò che ha funzionato.", .neutral: "Nota cosa ti dà energia e cosa te la toglie."],
            askPrefix: "Le cose più vicine che hai scritto:"
        ),
        "pt": GroundedLocale(
            open: "“", close: "”", joiner: " ",
            youWrote: "Você escreveu: ",
            moodWord: [.tired: "exausta", .stressed: "estressada", .sad: "triste", .good: "bem"],
            pickNudge: "Copie palavra por palavra a frase da entrada do diário que melhor explica por que a pessoa se sentiu {mood}. Escreva só essa frase.",
            pickNeutral: "Copie palavra por palavra a frase da entrada do diário que mostra o mais importante do dia. Escreva só essa frase.",
            pickDigest: "Copie palavra por palavra três frases das entradas do diário, cada uma em sua própria linha: primeiro a frase que mostra quando a pessoa parecia mais exausta, depois uma frase sobre algo bom que está crescendo, depois uma frase sobre algo que pode estar pesando. Escreva só essas três frases.",
            pickAsk: "Copie palavra por palavra a frase (ou no máximo duas frases) das entradas do diário que melhor respondem à pergunta, cada uma em sua própria linha. Escreva só essas frases.",
            entryLabel: "Entrada do diário:", weekLabel: "Entradas do diário desta semana:", entriesLabel: "Entradas do diário:", questionLabel: "Pergunta:",
            feel: [
                .tired: ["Parece um dia que tirou muita energia de você. Hoje à noite, se dê um descanso.", "Parece ter sido cansativo. Uma noite tranquila pode fazer bem."],
                .stressed: ["Parece muita coisa ao mesmo tempo. Talvez ajude começar por uma coisa pequena.", "Parece que há bastante pressão. Uma pausa curta pode ajudar você a respirar."],
                .sad: ["Parece pesado. Seja gentil com você hoje.", "Parece um momento difícil. Tudo bem ir devagar."],
                .good: ["Parece um bom momento. Vale a pena guardar.", "Parece que houve um pouco de leveza. Talvez valha notar o que ajudou."],
                .neutral: ["Obrigado por escrever isso.", "Vale a pena notar isso."],
            ],
            theme: [.tired: "Uma semana que pediu muita energia.", .stressed: "Uma semana com muita pressão.", .sad: "Uma semana difícil.", .good: "Uma semana com bons momentos.", .neutral: "Uma semana de altos e baixos."],
            energyHard: "O mais pesado pareceu quando você escreveu: ",
            energyGood: "O mais leve pareceu quando você escreveu: ",
            buildingSuffix: "Há algo aí que pode crescer.",
            watchSuffix: "Vale a pena ficar de olho nisso.",
            boost: [.tired: "Reserve uma noite tranquila só para você.", .stressed: "Escolha uma tarefa pequena para terminar hoje.", .sad: "Mande uma mensagem para alguém de confiança.", .good: "Faça mais do que te fez bem esta semana.", .neutral: "Tire cinco minutos para algo que te faça bem."],
            nextWeek: [.tired: "Proteja seu sono e reserve pausas.", .stressed: "Foque em uma só coisa importante por dia.", .sad: "Vá com calma e continue escrevendo como você está.", .good: "Repita o que funcionou.", .neutral: "Repare no que te dá energia e no que tira."],
            askPrefix: "O mais próximo que você escreveu:"
        ),
        "ru": GroundedLocale(
            open: "«", close: "»", joiner: " ",
            youWrote: "Ты написал(а): ",
            moodWord: [.tired: "измотанным", .stressed: "напряжённым", .sad: "грустным", .good: "хорошо"],
            pickNudge: "Перепиши слово в слово предложение из записи в дневнике, которое лучше всего объясняет, почему человек чувствовал себя {mood}. Выведи только это предложение.",
            pickNeutral: "Перепиши слово в слово предложение из записи в дневнике, которое показывает самое важное за день. Выведи только это предложение.",
            pickDigest: "Перепиши слово в слово три предложения из записей в дневнике, каждое на отдельной строке: сначала предложение, показывающее, когда человек казался самым измотанным, затем предложение о чём-то хорошем, что растёт, затем предложение о том, что может его тяготить. Выведи только эти три предложения.",
            pickAsk: "Перепиши слово в слово одно предложение (или не больше двух) из записей в дневнике, которые лучше всего отвечают на вопрос, каждое на отдельной строке. Выведи только эти предложения.",
            entryLabel: "Запись в дневнике:", weekLabel: "Записи в дневнике за эту неделю:", entriesLabel: "Записи в дневнике:", questionLabel: "Вопрос:",
            feel: [
                .tired: ["Похоже, этот день забрал много сил. Позволь себе вечером отдохнуть.", "Похоже, это было изматывающе. Спокойный вечер может помочь."],
                .stressed: ["Похоже, всего слишком много сразу. Возможно, стоит начать с одного небольшого дела.", "Похоже, давление немаленькое. Короткая пауза может помочь выдохнуть."],
                .sad: ["Похоже, это тяжело. Будь сегодня бережнее к себе.", "Похоже, сейчас непросто. Можно никуда не спешить."],
                .good: ["Похоже на хороший момент. Его стоит запомнить.", "Похоже, стало немного легче. Возможно, стоит заметить, что помогло."],
                .neutral: ["Спасибо, что записал(а) это.", "Это стоит заметить."],
            ],
            theme: [.tired: "Неделя, которая потребовала много сил.", .stressed: "Неделя под давлением.", .sad: "Тяжёлая неделя.", .good: "Неделя с хорошими моментами.", .neutral: "Неделя со взлётами и падениями."],
            energyHard: "Тяжелее всего, похоже, было, когда ты написал(а): ",
            energyGood: "Легче всего, похоже, было, когда ты написал(а): ",
            buildingSuffix: "Здесь есть то, что может вырасти.",
            watchSuffix: "За этим стоит последить.",
            boost: [.tired: "Выдели спокойный вечер только для себя.", .stressed: "Выбери одно небольшое дело, которое можно закончить сегодня.", .sad: "Напиши тому, кому доверяешь.", .good: "Делай больше того, что помогло на этой неделе.", .neutral: "Удели пять минут тому, что тебе приятно."],
            nextWeek: [.tired: "Береги сон и планируй паузы.", .stressed: "Одно важное дело в день.", .sad: "Не торопи себя и продолжай записывать, как ты.", .good: "Повтори то, что сработало.", .neutral: "Замечай, что даёт силы, а что их забирает."],
            askPrefix: "Самое близкое из того, что ты написал(а):"
        ),
        "ja": GroundedLocale(
            open: "「", close: "」", joiner: "",
            youWrote: "あなたはこう書きました：",
            moodWord: [.tired: "疲れ切っていた", .stressed: "ストレスを感じていた", .sad: "悲しかった", .good: "気分がよかった"],
            pickNudge: "次の日記から、その人がなぜ{mood}のかをいちばんよく表している一文を、そのまま書き写してください。その一文だけを出力してください。",
            pickNeutral: "次の日記から、その日いちばん大事なことを表す一文をそのまま書き写してください。その一文だけを出力してください。",
            pickDigest: "次の日記から、三つの文をそのまま書き写してください。それぞれ別の行に：まず、その人がいちばん疲れていたように見える文、次に、何かよいことが育っている文、最後に、その人の負担になっていそうな文。その三つの文だけを出力してください。",
            pickAsk: "次の日記から、質問にいちばんよく答えている文を一つ（多くても二つ）、そのまま書き写してください。一文ずつ別の行に。その文だけを出力してください。",
            entryLabel: "日記：", weekLabel: "今週の日記：", entriesLabel: "日記：", questionLabel: "質問：",
            feel: [
                .tired: ["とても疲れる一日だったようですね。今夜はゆっくり休んでください。", "かなり消耗しているように見えます。静かな夜を過ごすといいかもしれません。"],
                .stressed: ["いろいろなことが一度に重なっているようですね。まず小さなことを一つだけ片づけてみては。", "プレッシャーが大きそうです。少し休憩をとると楽になるかもしれません。"],
                .sad: ["つらい時間だったようですね。今日は自分にやさしくしてください。", "気持ちが沈んでいるようです。ゆっくりで大丈夫です。"],
                .good: ["いい時間だったようですね。その気持ちを大切に。", "少し心が軽くなったようですね。何が助けになったのか覚えておくといいかも。"],
                .neutral: ["書き留めてくれてありがとう。", "気づいておく価値のあることですね。"],
            ],
            theme: [.tired: "たくさんのエネルギーを使った一週間。", .stressed: "プレッシャーの多い一週間。", .sad: "つらい一週間。", .good: "いい時間があった一週間。", .neutral: "浮き沈みのあった一週間。"],
            energyHard: "いちばん大変そうだったのは、こう書いたときです：",
            energyGood: "いちばん軽やかだったのは、こう書いたときです：",
            buildingSuffix: "――ここから育っていくものがありそうです。",
            watchSuffix: "――ここは少し気にかけておきましょう。",
            boost: [.tired: "今夜は自分のための静かな時間をつくってみて。", .stressed: "今日終わらせられる小さなことを一つ選んでみて。", .sad: "信頼できる人に連絡してみて。", .good: "今週よかったことを、もう少し続けてみて。", .neutral: "自分をいたわる時間を五分とってみて。"],
            nextWeek: [.tired: "睡眠を守って、休憩を予定に入れましょう。", .stressed: "一日ひとつの大事なことに集中しましょう。", .sad: "無理せず、気持ちを書き続けましょう。", .good: "うまくいったことを繰り返しましょう。", .neutral: "何が元気をくれて、何が奪うのかに気づいてみましょう。"],
            askPrefix: "いちばん近いのは、あなたが書いたこの言葉です："
        ),
        "ko": GroundedLocale(
            open: "“", close: "”", joiner: " ",
            youWrote: "이렇게 썼어요: ",
            moodWord: [.tired: "지쳤는지", .stressed: "스트레스를 받았는지", .sad: "슬펐는지", .good: "기분이 좋았는지"],
            pickNudge: "아래 일기에서 이 사람이 왜 {mood}를 가장 잘 보여 주는 문장을 그대로 옮겨 적어 주세요. 그 문장만 출력하세요.",
            pickNeutral: "아래 일기에서 그날 가장 중요한 일을 보여 주는 문장을 그대로 옮겨 적어 주세요. 그 문장만 출력하세요.",
            pickDigest: "아래 일기에서 세 문장을 그대로 옮겨 적어 주세요. 각 문장은 한 줄씩: 먼저 이 사람이 가장 지쳐 보였던 문장, 다음으로 좋은 일이 자라고 있는 문장, 마지막으로 이 사람에게 부담이 될 수 있는 문장. 그 세 문장만 출력하세요.",
            pickAsk: "아래 일기에서 질문에 가장 잘 답하는 문장 하나(많아야 두 개)를 그대로 옮겨 적어 주세요. 한 줄에 한 문장씩. 그 문장만 출력하세요.",
            entryLabel: "일기:", weekLabel: "이번 주 일기:", entriesLabel: "일기:", questionLabel: "질문:",
            feel: [
                .tired: ["많이 지친 하루였던 것 같아요. 오늘 밤은 푹 쉬어요.", "꽤 힘들었던 것 같아요. 조용한 저녁이 도움이 될 수 있어요."],
                .stressed: ["한꺼번에 많은 일이 겹친 것 같아요. 작은 일 하나부터 시작해 보면 어떨까요.", "부담이 큰 것 같아요. 잠깐 쉬어 가면 숨 돌리는 데 도움이 될 거예요."],
                .sad: ["마음이 무거웠던 것 같아요. 오늘은 자신에게 다정하게 대해 주세요.", "힘든 때인 것 같아요. 천천히 가도 괜찮아요."],
                .good: ["좋은 순간이었던 것 같아요. 잘 간직해 두세요.", "마음이 조금 가벼워진 것 같아요. 무엇이 도움이 됐는지 기억해 두면 좋겠어요."],
                .neutral: ["적어 줘서 고마워요.", "눈여겨볼 만한 일이에요."],
            ],
            theme: [.tired: "힘을 많이 쓴 한 주.", .stressed: "부담이 많았던 한 주.", .sad: "힘든 한 주.", .good: "좋은 순간들이 있었던 한 주.", .neutral: "기복이 있었던 한 주."],
            energyHard: "가장 힘들어 보였던 건 이렇게 썼을 때예요: ",
            energyGood: "가장 가벼워 보였던 건 이렇게 썼을 때예요: ",
            buildingSuffix: "여기서 자라날 무언가가 있어 보여요.",
            watchSuffix: "이 부분은 조금 지켜봐 주세요.",
            boost: [.tired: "오늘 밤은 나만을 위한 조용한 시간을 가져 보세요.", .stressed: "오늘 끝낼 수 있는 작은 일 하나를 골라 보세요.", .sad: "믿을 수 있는 사람에게 연락해 보세요.", .good: "이번 주에 좋았던 일을 조금 더 해 보세요.", .neutral: "나를 위한 5분을 가져 보세요."],
            nextWeek: [.tired: "잠을 지키고 쉬는 시간을 계획해 보세요.", .stressed: "하루에 중요한 일 하나에만 집중해 보세요.", .sad: "서두르지 말고 마음을 계속 적어 보세요.", .good: "잘된 일을 다시 해 보세요.", .neutral: "무엇이 힘을 주고 무엇이 힘을 빼는지 살펴보세요."],
            askPrefix: "가장 가까운 건 이렇게 쓴 내용이에요:"
        ),
        "zh": GroundedLocale(
            open: "“", close: "”", joiner: "",
            youWrote: "你写道：",
            moodWord: [.tired: "精疲力尽", .stressed: "有压力", .sad: "难过", .good: "心情不错"],
            pickNudge: "请把下面日记中最能解释这个人为什么感到{mood}的那一句话原样抄写下来。只输出这一句话。",
            pickNeutral: "请把下面日记中最能体现这一天最重要的事的那一句话原样抄写下来。只输出这一句话。",
            pickDigest: "请从下面的日记中原样抄写三句话，每句一行：第一句是这个人看起来最累的时候，第二句是关于正在成长的好事，第三句是关于可能让他负担的事。只输出这三句话。",
            pickAsk: "请从下面的日记中原样抄写最能回答这个问题的一句话（最多两句），每句一行。只输出这些句子。",
            entryLabel: "日记：", weekLabel: "本周日记：", entriesLabel: "日记：", questionLabel: "问题：",
            feel: [
                .tired: ["听起来是很耗精力的一天。今晚好好休息一下吧。", "看起来真的很累。安静地过个晚上也许会有帮助。"],
                .stressed: ["听起来很多事情同时压过来。也许可以先从一件小事开始。", "看起来压力不小。短暂休息一下，也许能喘口气。"],
                .sad: ["听起来很沉重。今天对自己温柔一点。", "看起来这段时间不容易。慢慢来就好。"],
                .good: ["听起来是个美好的时刻。值得记住。", "看起来心情轻松了一些。也许可以留意一下是什么帮到了你。"],
                .neutral: ["谢谢你把它写下来。", "这值得留意。"],
            ],
            theme: [.tired: "耗费了很多精力的一周。", .stressed: "压力很大的一周。", .sad: "艰难的一周。", .good: "有美好时刻的一周。", .neutral: "有起有落的一周。"],
            energyHard: "最辛苦的时候，似乎是你写下这句话时：",
            energyGood: "最轻松的时候，似乎是你写下这句话时：",
            buildingSuffix: "这里有值得培养的东西。",
            watchSuffix: "这一点值得留意。",
            boost: [.tired: "今晚给自己留一段安静的时间。", .stressed: "选一件今天能完成的小事。", .sad: "联系一个你信任的人。", .good: "多做一些这周让你感觉好的事。", .neutral: "花五分钟做一件让自己舒服的事。"],
            nextWeek: [.tired: "保护好睡眠，安排一些休息。", .stressed: "每天只专注一件重要的事。", .sad: "别着急，继续写下自己的感受。", .good: "重复那些有效的做法。", .neutral: "留意什么给你能量，什么在消耗你。"],
            askPrefix: "和这个问题最接近的是你写的这些："
        ),
    ]

    /// A non-English grounded plan: the Gemma plan plus the validator that checks the model's
    /// picked quote(s) against the options and returns the fully composed, user-facing text.
    struct LocalizedGrounded {
        let plan: LocalLLMService.GemmaPlan
        let validator: ((String) throws -> String)?
    }

    private static func groundedLocaleCode(for entries: [Entry], extraText: String? = nil) -> String? {
        let target = responseLanguageTarget(from: entries, extraText: extraText) ?? responseLanguageTargetFromCurrentLocale()
        guard let code = target?.code, code != "en", groundedLocales[code] != nil else { return nil }
        return code
    }

    private static func quotableText(of entry: Entry) -> String {
        var texts = [entry.text]
        for note in entry.voiceNotes {
            if let transcript = note.transcript, !transcript.isEmpty, transcript != entry.text { texts.append(transcript) }
        }
        return texts.joined(separator: "\n")
    }

    private static func literalOnlyGrammar(_ rule: String, _ options: [String]) -> String {
        "\(rule) ::= " + options.map(gbnfLiteral).joined(separator: " | ")
    }

    /// Nudge outside English: Gemma copies one sentence (grammar of literals only), the app wraps
    /// it in `youWrote` + quote marks and adds a fixed line for the entry's mood. nil for English.
    static func localizedGroundedNudge(recent: [Entry], background: [Entry], recentNudges: [String]) -> LocalizedGrounded? {
        guard let code = groundedLocaleCode(for: recent + background), let loc = groundedLocales[code] else { return nil }
        let source = groundedNudgeSourceEntries(recent)
        var seen = Set<String>()
        let all = source.flatMap(groundedQuoteCandidates(of:)).filter { seen.insert($0).inserted }
        let fresh = all.filter { quote in !recentNudges.contains { $0.contains(loc.open + quote + loc.close) } }
        let options = Array((fresh.isEmpty ? all : fresh).prefix(groundedNudgeMaxQuoteOptions))
        guard !options.isEmpty else { return LocalizedGrounded(plan: .unsuitable, validator: nil) }

        let bucket = GroundedMoodBucket(mood: source.first?.mood)
        let pick = bucket == .neutral
            ? loc.pickNeutral
            : loc.pickNudge.replacingOccurrences(of: "{mood}", with: loc.moodWord[bucket] ?? "")
        let message = "\(pick)\n\n\(loc.entryLabel)\n" + source.map(quotableText(of:)).joined(separator: "\n---\n")
        let variant = (Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0) % 2
        let feel = loc.feel[bucket]?[variant] ?? loc.feel[.neutral]?[variant] ?? ""
        return LocalizedGrounded(
            plan: .grammarConstrained(userMessage: message, grammar: literalOnlyGrammar("root", options)),
            validator: { text in
                let quote = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard options.contains(quote) else { throw InsightError.incompleteResponse }
                return loc.youWrote + loc.open + quote + loc.close + loc.joiner + feel
            }
        )
    }

    /// Digest outside English: Gemma copies three sentences — hardest moment, something good
    /// growing, something to watch — one per line from mood-split literal lists; theme, boost and
    /// next week are fixed lines chosen by the week's dominant mood ("mixed" when neither side
    /// reaches 70%). Labels are the existing localized digest labels.
    static func localizedGroundedDigest(weekEntries: [Entry], languageSource: [Entry]) -> LocalizedGrounded? {
        guard let code = groundedLocaleCode(for: languageSource), let loc = groundedLocales[code] else { return nil }
        var all: [String] = [], good: [String] = [], hard: [String] = []
        var seen = Set<String>()
        var bucketCounts: [GroundedMoodBucket: Int] = [:]
        for entry in weekEntries {
            let bucket = GroundedMoodBucket(mood: entry.mood)
            bucketCounts[bucket, default: 0] += 1
            for quote in groundedQuoteCandidates(of: entry) where seen.insert(quote).inserted {
                all.append(quote)
                if bucket.isHard { hard.append(quote) } else if bucket == .good { good.append(quote) }
            }
        }
        guard !all.isEmpty else { return LocalizedGrounded(plan: .unsuitable, validator: nil) }
        let cap = groundedDigestMaxOptionsPerBucket
        let goodOptions = Array((good.isEmpty ? all : good).prefix(cap))
        let hardOptions = Array((hard.isEmpty ? all : hard).prefix(cap))
        let energyIsHard = !hard.isEmpty
        let energyOptions = energyIsHard ? hardOptions : goodOptions

        let hardCount = bucketCounts.filter { $0.key.isHard }.values.reduce(0, +)
        let goodCount = bucketCounts[.good] ?? 0
        let total = max(1, hardCount + goodCount)
        let dominant: GroundedMoodBucket
        if hardCount > 0, goodCount > 0, Double(max(hardCount, goodCount)) < 0.7 * Double(total) {
            dominant = .neutral
        } else if goodCount >= hardCount {
            dominant = goodCount > 0 ? .good : .neutral
        } else {
            dominant = [.tired, .stressed, .sad].max { (bucketCounts[$0] ?? 0) < (bucketCounts[$1] ?? 0) } ?? .neutral
        }

        let entriesText = weekEntries.map(quotableText(of:)).joined(separator: "\n---\n")
        let message = "\(loc.pickDigest)\n\n\(loc.weekLabel)\n\(entriesText)"
        let grammar = [
            #"root ::= energyq "\n" goodq "\n" hardq"#,
            literalOnlyGrammar("energyq", energyOptions),
            literalOnlyGrammar("goodq", goodOptions),
            literalOnlyGrammar("hardq", hardOptions),
        ].joined(separator: "\n")
        let labels = weeklyDigestSectionLabels.map { $0[code] ?? $0["en"] ?? "" }
        return LocalizedGrounded(
            plan: .grammarConstrained(userMessage: message, grammar: grammar),
            validator: { text in
                let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard lines.count == 3, energyOptions.contains(lines[0]), goodOptions.contains(lines[1]), hardOptions.contains(lines[2])
                else { throw InsightError.incompleteResponse }
                let watch = lines[2] == lines[0] ? (hardOptions.first { $0 != lines[0] } ?? lines[2]) : lines[2]
                let bodies = [
                    loc.theme[dominant] ?? "",
                    (energyIsHard ? loc.energyHard : loc.energyGood) + loc.open + lines[0] + loc.close,
                    loc.open + lines[1] + loc.close + loc.joiner + loc.buildingSuffix,
                    loc.open + watch + loc.close + loc.joiner + loc.watchSuffix,
                    loc.boost[dominant] ?? "",
                    loc.nextWeek[dominant] ?? "",
                ]
                return zip(labels, bodies).map { "\($0): \($1)" }.joined(separator: "\n")
            }
        )
    }

    /// Ask outside English: Gemma copies one or two sentences; the app lists them under a fixed
    /// heading with each one's entry date in the user's locale. No no-answer shortcut here — the
    /// relevance helpers (lean words, stop words, word embedding) are English-only.
    static func localizedGroundedAsk(question: String, pool: [Entry]) -> LocalizedGrounded? {
        guard let code = groundedLocaleCode(for: pool, extraText: question), let loc = groundedLocales[code] else { return nil }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: code)
        dayFormatter.setLocalizedDateFormatFromTemplate("d MMM")
        let perEntry = pool.map { ($0, groundedQuoteCandidates(of: $0)) }
        var options: [String] = []
        var dates: [String: String] = [:]
        for round in 0..<(perEntry.map(\.1.count).max() ?? 0) {
            for (entry, quotes) in perEntry where round < quotes.count && dates[quotes[round]] == nil {
                dates[quotes[round]] = dayFormatter.string(from: entry.createdAt)
                options.append(quotes[round])
            }
        }
        options = Array(options.prefix(groundedAskMaxOptions))
        guard !options.isEmpty else { return LocalizedGrounded(plan: .unsuitable, validator: nil) }
        let entriesText = pool.map(quotableText(of:)).joined(separator: "\n---\n")
        let message = "\(loc.pickAsk)\n\n\(loc.questionLabel) \(question)\n\n\(loc.entriesLabel)\n\(entriesText)"
        let grammar = #"root ::= q ("\n" q)?"# + "\n" + literalOnlyGrammar("q", options)
        return LocalizedGrounded(
            plan: .grammarConstrained(userMessage: message, grammar: grammar),
            validator: { text in
                var quotes: [String] = []
                for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                    guard options.contains(line) else { throw InsightError.incompleteResponse }
                    if !quotes.contains(line) { quotes.append(line) }
                }
                guard (1...2).contains(quotes.count) else { throw InsightError.incompleteResponse }
                return ([loc.askPrefix] + quotes.map { "\(dates[$0] ?? "") – \(loc.open)\($0)\(loc.close)" }).joined(separator: "\n")
            }
        )
    }
}

// MARK: - Source disclosure (Sentinel X-ray)

extension InsightService {
    /// The verbatim system prompt an insight of this type was generated from,
    /// plus a `file:line` label. Read live from the same constant the generator
    /// uses (CLAUDE.md: prompts live in `InsightService.swift` only) — the
    /// Sentinel press-hold X-ray shows this so the generation is inspectable,
    /// never a paraphrase that can drift.
    /// `content` picks the Gemma variant for a grounded daily nudge — the "You wrote, \"…" shape
    /// only the grammar path produces — so the sheet never shows a prompt that wasn't sent.
    static func systemPrompt(for type: InsightType, content: String? = nil) -> (ref: String, body: String) {
        switch type {
        case .dailyNudge:
            if let content, content.hasPrefix(groundedNudgePrefix) {
                return ("InsightService.swift · DAILY_NUDGE_GEMMA_INSTRUCTIONS", DAILY_NUDGE_GEMMA_INSTRUCTIONS)
            }
            if let content, let loc = groundedLocales.values.first(where: { content.hasPrefix($0.youWrote + $0.open) }) {
                return ("InsightService.swift · groundedLocales.pickNudge", loc.pickNudge)
            }
            return ("InsightService.swift:22 · DAILY_NUDGE_SYSTEM", DAILY_NUDGE_SYSTEM)
        case .weeklyDigest:
            if let content, content.contains("WHAT'S BUILDING: You wrote, \"") {
                return ("InsightService.swift · WEEKLY_DIGEST_GEMMA_INSTRUCTIONS", WEEKLY_DIGEST_GEMMA_INSTRUCTIONS)
            }
            if let content, let loc = groundedLocales.values.first(where: { content.contains($0.energyHard) || content.contains($0.energyGood) }) {
                return ("InsightService.swift · groundedLocales.pickDigest", loc.pickDigest)
            }
            return ("InsightService.swift:41 · WEEKLY_DIGEST_SYSTEM", WEEKLY_DIGEST_SYSTEM)
        case .monthlyReport:
            if let content, content.contains("WHAT YOU'RE BECOMING: You wrote, \"") {
                return ("InsightService.swift · MONTHLY_REPORT_GEMMA_INSTRUCTIONS", MONTHLY_REPORT_GEMMA_INSTRUCTIONS)
            }
            return ("InsightService.swift:84 · MONTHLY_REPORT_SYSTEM", MONTHLY_REPORT_SYSTEM)
        case .askResponse:
            if let content, content.hasPrefix(groundedAskPrefix) {
                return ("InsightService.swift · ASK_GEMMA_INSTRUCTIONS", ASK_GEMMA_INSTRUCTIONS)
            }
            if let content, let loc = groundedLocales.values.first(where: { content.hasPrefix($0.askPrefix) }) {
                return ("InsightService.swift · groundedLocales.pickAsk", loc.pickAsk)
            }
            return ("InsightService.swift:69 · ASK_SYSTEM", ASK_SYSTEM)
        }
    }
}
