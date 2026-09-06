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
        case .emptyResponse: return String(localized: "Mirror didn't get a response. Try again in a moment.")
        case .incompleteResponse: return String(localized: "Mirror couldn't finish that reflection. Try again.")
        case .serviceUnavailable: return String(localized: "Something went wrong. Mirror will try again tonight while your phone charges.")
        }
    }
}

private let DAILY_NUDGE_SYSTEM = """
You are MirrorNotes, a private on-device journaling companion.
Read the user's local journal context and offer ONE specific, personal reflection in the voice of a close friend who knows them well.
Rules:
- Use the Long-term context to understand recurring themes, but ground the answer in Recent entries
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
- Be specific. Be warm. Be honest. Do not over-explain.
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
- Be specific. Be honest. Be warm. Do not over-explain.
"""

private let ASK_SYSTEM = """
You are MirrorNotes, a private journaling companion. Read the journal entries and answer the question based on what the person actually wrote.
Rules:
- Address the person as "you/your" only. Never use "I/me/my" as if you are the journal writer
- Reference specific things they wrote — say "you wrote..." or "you mentioned..."
- Look for related themes, emotions, and events — not just exact keyword matches. If someone asks about stress and entries mention feeling exhausted, overwhelmed, or under pressure, that is relevant
- No internet advice, no generic tips. Base your answer only on the entries
- Quote or closely paraphrase their own words when relevant
- 3-5 sentences maximum
- Sound human, warm, and direct
- Do not mention that you are an AI or model
- Avoid clinical phrases like "this suggests", "patterns indicate", or "the source mentions"
- Only if the entries truly contain nothing at all related to the question, use the exact no-answer fallback phrase specified below.
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
- Use the MONTH STATS block to ground observations in specifics
- No therapy language, no generic affirmations, no Markdown, no bullets
- Do not add any text outside these six sections
- Do not mention that you are an AI
- Be warm, specific, and honest
"""

private let EMOTION_DETECT_SYSTEM = """
You are MirrorNotes. Read this journal entry and identify the writer's primary emotional state.
Reply with EXACTLY one word from this list:
Joyful, Grateful, Peaceful, Content, Energized, Hopeful, Anxious, Overwhelmed, Frustrated, Drained, Sad, Numb
No explanation. No punctuation. One word only.
"""

enum InsightService {
    private static let dailyNudgePromptBudget = 4_600
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

    static func generateNudge(entries: [Entry], recentNudges: [String] = []) async throws -> (text: String, engine: LLMEngine) {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let withinWindow = sorted.filter { $0.createdAt >= cutoff }
        let recent = withinWindow.isEmpty ? Array(sorted.prefix(1)) : Array(withinWindow.prefix(3))
        let recentIDs = Set(recent.map(\.id))
        let background = Array(sorted.filter { !recentIDs.contains($0.id) }.prefix(20))
        let languageInstruction = responseLanguageInstruction(for: responseLanguageTarget(from: recent + background), task: .dailyNudge)

        var userMessage = buildUserMessage(
            title: "Daily reflection context",
            recentEntries: recent,
            backgroundEntries: background,
            maxChars: dailyNudgePromptBudget
        )
        let openings = priorNudgeOpenings(from: Array(recentNudges.prefix(4)))
        if !openings.isEmpty {
            userMessage += "\n\nYour recent reflections already opened with:\n"
                + openings.map { "- \"\($0)…\"" }.joined(separator: "\n")
                + "\nOpen today's reflection with a different first sentence built from a different concrete detail."
        }

        return try await localGenerate(
            systemPrompt: DAILY_NUDGE_SYSTEM,
            userMessage: userMessage,
            task: .dailyNudge,
            responseLanguageInstruction: languageInstruction
        )
    }

    /// Fewer than this many entries in the current week → not enough to find a
    /// week's theme; the call sites show the "write more this week" state instead
    /// of generating a thin digest.
    static let weeklyDigestMinimumWeekEntries = 3

    /// The digest is explicitly "this week" — `WeeklyDigestView`, the C1 widget,
    /// and the `THIS WEEK'S THEME` section header all say so. `weekEntries` is the
    /// current ISO week only and is the sole source of the theme; `allEntries`
    /// (which includes them) is passed as long-term background for continuity in
    /// `WHAT'S BUILDING` / `NEXT WEEK`, never as digest material.
    static func generateWeeklyDigest(weekEntries: [Entry], allEntries: [Entry]) async throws -> (text: String, engine: LLMEngine) {
        let thisWeek = weekEntries.sorted { $0.createdAt > $1.createdAt }
        let weekIDs = Set(weekEntries.map(\.id))
        let priorWeeks = allEntries
            .filter { !weekIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        let languageSource = thisWeek.isEmpty ? priorWeeks : thisWeek
        let languageInstruction = responseLanguageInstruction(for: responseLanguageTarget(from: languageSource), task: .weeklyDigest)
        return try await localGenerate(
            systemPrompt: WEEKLY_DIGEST_SYSTEM,
            userMessage: buildUserMessage(
                title: "Weekly digest context",
                recentEntries: Array(thisWeek.prefix(12)),
                backgroundEntries: Array(priorWeeks.prefix(14)),
                maxChars: weeklyDigestPromptBudget
            ),
            task: .weeklyDigest,
            responseLanguageInstruction: languageInstruction
        )
    }

    static func generateMonthlyReport(monthEntries: [Entry], allEntries: [Entry]) async throws -> (text: String, engine: LLMEngine) {
        let languageInstruction = responseLanguageInstruction(for: responseLanguageTarget(from: monthEntries), task: .monthlyReport)
        return try await localGenerate(
            systemPrompt: MONTHLY_REPORT_SYSTEM,
            userMessage: buildMonthlyReportMessage(monthEntries: monthEntries, allEntries: allEntries),
            task: .monthlyReport,
            responseLanguageInstruction: languageInstruction
        )
    }

    static func ask(question: String, entries: [Entry]) async throws -> (text: String, engine: LLMEngine) {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let relevant = SearchService.search(query: question, in: sorted, limit: 10)
        let relevantIDs = Set(relevant.map(\.id))
        let background = sorted.filter { !relevantIDs.contains($0.id) }.prefix(8)
        let target = responseLanguageTarget(from: relevant + Array(background), extraText: question) ?? responseLanguageTargetFromCurrentLocale()
        let languageInstruction = responseLanguageInstruction(for: target, task: .ask)
        return try await localGenerate(
            systemPrompt: ASK_SYSTEM,
            userMessage: buildAskMessage(
                entries: relevant,
                backgroundEntries: Array(background),
                question: question
            ),
            task: .ask,
            responseLanguageInstruction: languageInstruction,
            askNoAnswerPhrase: askNoAnswerPhrase(for: target)
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

    // Gemma's system prompts are English, so without an explicit directive it tends
    // to answer in English even when the journal content is not. Emotion detection
    // is intentionally skipped because it must return the persisted English mood key.
    private static func responseLanguageInstruction(for target: ResponseLanguageTarget?, task: LocalLLMTask) -> String? {
        guard task != .emotion else { return nil }
        guard let target = target ?? responseLanguageTargetFromCurrentLocale() else { return nil }

        switch task {
        case .weeklyDigest, .monthlyReport:
            let labels = localizedSectionLabels(for: task, languageCode: target.code)
            return """
            Use exactly these section labels instead of any English labels listed above:
            \(labels.joined(separator: "\n"))

            Write all reflection prose after each label only in \(target.name). Do not use English in the prose unless quoting the user's own words.
            """
        case .dailyNudge, .ask:
            return "Respond only in \(target.name). Do not use English unless quoting the user's own words."
        case .emotion:
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
        case .dailyNudge, .ask, .emotion:
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

    private static func localGenerate(
        systemPrompt basePrompt: String,
        userMessage: String,
        task: LocalLLMTask,
        responseLanguageInstruction: String?,
        askNoAnswerPhrase: String? = nil
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
        do {
            do {
                let first = try await queuedGenerate(systemPrompt: finalSystemPrompt, userMessage: userMessage, task: task)
                let validated = try validate(first.text, for: task, askNoAnswerPhrase: askNoAnswerPhrase)
                return (validated, first.engine)
            } catch InsightError.emptyResponse, InsightError.incompleteResponse, LocalLLMError.emptyResponse {
                let retryMessage = retryUserMessage(original: userMessage, task: task)
                let second = try await queuedGenerate(systemPrompt: finalSystemPrompt, userMessage: retryMessage, task: task)
                let validated = try validate(second.text, for: task, askNoAnswerPhrase: askNoAnswerPhrase)
                return (validated, second.engine)
            } catch LocalLLMError.contextExhausted {
                await LocalLLMService.shared.resetContext()
                let second = try await queuedGenerate(systemPrompt: finalSystemPrompt, userMessage: userMessage, task: task)
                let validated = try validate(second.text, for: task, askNoAnswerPhrase: askNoAnswerPhrase)
                return (validated, second.engine)
            }
        } catch let error as InsightError {
            throw error
        } catch {
            throw InsightError.serviceUnavailable(error.localizedDescription)
        }
    }

    private static func queuedGenerate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> (text: String, engine: LLMEngine) {
        let raw = try await LLMGenerationQueue.shared.run {
            try await LocalLLMService.shared.generate(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                task: task
            )
        }

        let cleaned: String
        switch task {
        case .weeklyDigest:
            cleaned = raw.text.cleanedDigestOutput()
        case .monthlyReport:
            cleaned = raw.text.cleanedMonthlyReportOutput()
        case .dailyNudge, .ask, .emotion:
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
        }
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

    private static func buildUserMessage(
        title: String,
        recentEntries: [Entry],
        backgroundEntries: [Entry],
        maxChars: Int
    ) -> String {
        let recentBlock = formatEntries(recentEntries, maxChars: Int(Double(maxChars) * 0.72))
        let backgroundBlock = buildMemoryBrief(from: backgroundEntries, maxChars: Int(Double(maxChars) * 0.28))

        let today = Date().formatted(date: .abbreviated, time: .omitted)
        return """
        \(title)

        Today: \(today)

        Long-term context:
        \(backgroundBlock)

        Recent entries:
        \(recentBlock)
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

    private static func buildMemoryBrief(from entries: [Entry], maxChars: Int) -> String {
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
        let excerpts = selectRepresentativeExcerpts(from: entries, limit: 5)
            .map { entry in
                let date = entry.createdAt.formatted(date: .abbreviated, time: .omitted)
                return "- \(date): \(clipped(entry.insightContext, maxChars: 220))"
            }
            .joined(separator: "\n")

        let brief = """
        Older entries reviewed: \(total) (\(dateRange)).
        Common moods: \(moodCounts.isEmpty ? "not enough mood labels" : moodCounts).
        Recurring words/themes: \(recurringTerms.isEmpty ? "not enough repeated terms" : recurringTerms.joined(separator: ", ")).
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

}

// Not private (see InsightService.validate above for why): InsightValidationTests exercises
// the full repair-then-validate pipeline these production call sites use, not validate() in
// isolation, so cleanedInsightOutput/cleanedDigestOutput/cleanedMonthlyReportOutput need the
// same testable-internal seam. softenDigestFragments stays private — it's an internal helper
// of cleanedDigestOutput, not a pipeline stage tests need to call directly.
extension String {
    func cleanedInsightOutput() -> String {
        replacingOccurrences(of: "###", with: "")
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
