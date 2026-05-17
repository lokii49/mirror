import Foundation

enum InsightError: LocalizedError {
    case unauthorized
    case subscriptionRequired
    case serverError(Int, String)
    case emptyResponse
    case incompleteResponse
    case serviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Sign in to generate insights."
        case .subscriptionRequired: return "Core subscription required."
        case .serverError(let code, let detail):
            return detail.isEmpty ? "Server error (\(code))." : "[\(code)] \(detail)"
        case .emptyResponse: return "No insight returned."
        case .incompleteResponse: return "Mirror could not finish that reflection. Try again."
        case .serviceUnavailable(let detail): return detail
        }
    }
}

private let DAILY_NUDGE_SYSTEM = """
You are MirrorNotes, a private on-device journaling companion.
Read the user's local journal context and offer ONE specific, personal reflection in the voice of a close friend who knows them well.
Rules:
- Use the Long-term context to understand recurring themes, but ground the answer in Recent entries
- Reference actual words, moods, dates, or concrete events, not generic advice
- Start with "I noticed..." or "Something I see..." — here "I" is Mirror's voice, not the journal writer's
- You may use "I" only as Mirror speaking (e.g., "I noticed", "I see"). Never use "I/me/my" as if you are the journal writer
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

THIS WEEK'S THEME: [one sentence]
YOUR ENERGY: [one sentence about when you seemed most alive or most drained]
WHAT'S BUILDING: [one sentence about one real thing growing in you or your life]
WATCH OUT FOR: [one gentle honest sentence about something that may be costing you]
MOOD BOOST: [one specific, small action tied to something they wrote that could help their mood next week]
NEXT WEEK: [one practical, kind sentence for next week]

Rules:
- Replace the bracketed placeholders with final prose. Never include [ or ] in the answer
- Do not use Markdown headings, bullets, ###, or extra titles
- Each section must be a complete, natural sentence, not a label or fragment
- Each sentence must be under 35 words. Be concise.
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
You are MirrorNotes, a private journaling companion. Someone is asking a question about their own journal.
Answer using ONLY the entries provided. Speak directly to them as "you/your".
Rules:
- Write entirely in second person. Address the user as "you/your". Never write in first person ("I", "me", "my") as if you are the journal writer
- Reference specific things the user wrote — say "you wrote..." or "you mentioned..." not "they wrote"
- If the answer is not in their entries, say "You haven't written about this yet."
- No internet advice, no generic tips
- Use older context only to connect patterns; do not invent facts beyond the entries
- Quote or closely paraphrase their own words when relevant
- 3-5 sentences maximum
- Write directly to "you", not "the person" or "the user"
- Do not mention that you are an AI or model
- Sound human, warm, and direct — like a close friend who read their journal
- Avoid clinical phrases like "this suggests", "patterns indicate", "significant", or "the source mentions"
"""

private let MONTHLY_REPORT_SYSTEM = """
You are MirrorNotes. Read this person's full month of journal entries and their month statistics. Write a deep monthly reflection that operates at the identity level — not what happened this week, but who this person is becoming, what tensions are shaping them, what they might not have noticed themselves.

You have access to a MONTH STATS block. Use it to ground observations in specifics.

Output EXACTLY this format with no extra sections:

YOUR MONTH IN ONE IMAGE: [one vivid metaphor expressed as a complete sentence starting with "This month felt like" or "It was as if" — capture the sensation of the month, not a summary of events]
THE TENSION AT THE CENTER: [one sentence naming the core conflict, pull, or recurring friction that ran through their entries — be specific about what is actually in tension, not a vague label]
A MOMENT THAT SHIFTED SOMETHING: [one sentence referencing a specific entry, event, or phrase they wrote that changed something, even subtly — mention the date or their actual words if possible]
WHAT YOU'RE BECOMING: [one sentence observing who they seem to be growing into — what is different about them now versus the start of this month, based on what they actually wrote]
WHAT WANTS TO BE RELEASED: [one sentence naming one thing from this month worth consciously letting go of — not generic, tied directly to something they wrote]
YOUR QUESTION FOR NEXT MONTH: [a genuine open question for them to sit with — not advice, not a task, a question that opens something. Must end with a question mark.]

Rules:
- Replace the bracketed placeholders with final prose. Never include [ or ] in the answer
- Do not use Markdown headings, bullets, ###, or extra titles
- Each section must be a complete sentence ending with punctuation
- YOUR MONTH IN ONE IMAGE must start with "This month felt like" or "It was as if"
- YOUR QUESTION FOR NEXT MONTH must end with a question mark and be a real question, not a statement
- Each section must be under 45 words
- Write entirely in second person. Address the user as "you/your" throughout
- Never write in first person as if you are the journal writer
- Reference actual words, moods, dates, or specific phrases from their entries — the more specific, the better
- Use the stats block to inform depth — reference entry count, mood arc, or writing patterns where it adds weight
- No therapy language, no generic affirmations
- Do not mention that you are an AI or model
- Sound human, perceptive, and honest — like someone who read every word and noticed what the person themselves missed
- Be specific. Be honest. Be warm. Do not over-explain.
"""

private let EMOTION_DETECT_SYSTEM = """
You are MirrorNotes. Read this journal entry and identify the writer's primary emotional state.
Reply with EXACTLY one word from this list:
Joyful, Grateful, Peaceful, Content, Energized, Hopeful, Anxious, Overwhelmed, Frustrated, Drained, Sad, Numb
No explanation. No punctuation. One word only.
"""

enum InsightService {
    static func generateNudge(entries: [Entry], token: String) async throws -> String {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        return try await localGenerate(
            systemPrompt: DAILY_NUDGE_SYSTEM,
            userMessage: buildUserMessage(
                title: "Daily reflection context",
                recentEntries: Array(sorted.prefix(7)),
                backgroundEntries: Array(sorted.dropFirst(7).prefix(16)),
                maxChars: 5600
            ),
            task: .dailyNudge
        )
    }

    static func generateWeeklyDigest(entries: [Entry], token: String) async throws -> String {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        return try await localGenerate(
            systemPrompt: WEEKLY_DIGEST_SYSTEM,
            userMessage: buildUserMessage(
                title: "Weekly digest context",
                recentEntries: Array(sorted.prefix(10)),
                backgroundEntries: Array(sorted.dropFirst(10).prefix(14)),
                maxChars: 5600
            ),
            task: .weeklyDigest
        ).cleanedDigestOutput()
    }

    static func generateMonthlyReport(monthEntries: [Entry], allEntries: [Entry], token: String) async throws -> String {
        return try await localGenerate(
            systemPrompt: MONTHLY_REPORT_SYSTEM,
            userMessage: buildMonthlyReportMessage(monthEntries: monthEntries, allEntries: allEntries),
            task: .monthlyReport
        ).cleanedMonthlyReportOutput()
    }

    static func ask(question: String, entries: [Entry], token: String) async throws -> String {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        let relevant = SearchService.search(query: question, in: sorted, limit: 6)
        let relevantIDs = Set(relevant.map(\.id))
        let background = sorted.filter { !relevantIDs.contains($0.id) }.prefix(12)
        return try await localGenerate(
            systemPrompt: ASK_SYSTEM,
            userMessage: buildAskMessage(
                entries: relevant,
                backgroundEntries: Array(background),
                question: question
            ),
            task: .ask
        ).cleanedInsightOutput()
    }

    static func detectEmotion(text: String, token: String) async throws -> String {
        let trimmed = String(text.prefix(3000))
        let response = try await localGenerate(
            systemPrompt: EMOTION_DETECT_SYSTEM,
            userMessage: trimmed,
            task: .emotion
        )
        return normalizeEmotion(response)
    }

    private static func localGenerate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        do {
            do {
                let first = try await queuedGenerate(systemPrompt: systemPrompt, userMessage: userMessage, task: task)
                return try validate(first, for: task)
            } catch InsightError.emptyResponse, InsightError.incompleteResponse, LocalLLMError.emptyResponse {
                let retryMessage = retryUserMessage(original: userMessage, task: task)
                let second = try await queuedGenerate(systemPrompt: systemPrompt, userMessage: retryMessage, task: task)
                return try validate(second, for: task)
            }
        } catch let error as InsightError {
            throw error
        } catch {
            throw InsightError.serviceUnavailable(error.localizedDescription)
        }
    }

    private static func queuedGenerate(systemPrompt: String, userMessage: String, task: LocalLLMTask) async throws -> String {
        let raw = try await LLMGenerationQueue.shared.run {
            try await LocalLLMService.shared.generate(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                task: task
            )
        }

        switch task {
        case .weeklyDigest:
            return raw.cleanedDigestOutput()
        case .monthlyReport:
            return raw.cleanedMonthlyReportOutput()
        case .dailyNudge, .ask, .emotion:
            return raw.cleanedInsightOutput()
        }
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
            return "Return exactly the required six labeled lines. Every section must have a complete sentence after the colon."
        case .monthlyReport:
            return "Return exactly six labeled sections: YOUR MONTH IN ONE IMAGE, THE TENSION AT THE CENTER, A MOMENT THAT SHIFTED SOMETHING, WHAT YOU'RE BECOMING, WHAT WANTS TO BE RELEASED, YOUR QUESTION FOR NEXT MONTH. YOUR MONTH IN ONE IMAGE must start with \"This month felt like\" or \"It was as if\". YOUR QUESTION FOR NEXT MONTH must end with a question mark. Every other section must end with a complete sentence."
        case .ask:
            return "Return only 3-5 complete sentences, or exactly: You haven't written about this yet."
        case .emotion:
            return "Return exactly one allowed mood word and nothing else."
        }
    }

    private static func validate(_ text: String, for task: LocalLLMTask) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InsightError.emptyResponse }

        switch task {
        case .dailyNudge:
            return try validateCompleteProse(
                trimmed,
                minimumCharacters: 45,
                maximumWords: 120,
                allowedSentenceRange: 1...4,
                rejectsFirstPerson: false
            )
        case .ask:
            if trimmed == "You haven't written about this yet." {
                return trimmed
            }
            return try validateCompleteProse(
                trimmed,
                minimumCharacters: 35,
                maximumWords: 140,
                allowedSentenceRange: 1...6,
                rejectsFirstPerson: false
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

    private static func validateCompleteProse(
        _ text: String,
        minimumCharacters: Int,
        maximumWords: Int,
        allowedSentenceRange: ClosedRange<Int>,
        rejectsFirstPerson: Bool
    ) throws -> String {
        guard text.count >= minimumCharacters else { throw InsightError.incompleteResponse }
        guard endsAsCompleteSentence(text) else { throw InsightError.incompleteResponse }
        guard !hasDanglingEnding(text) else { throw InsightError.incompleteResponse }
        if rejectsFirstPerson {
            guard !containsJournalWriterFirstPerson(text) else { throw InsightError.incompleteResponse }
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
        let requiredHeaders = [
            "THIS WEEK'S THEME",
            "YOUR ENERGY",
            "WHAT'S BUILDING",
            "WATCH OUT FOR",
            "MOOD BOOST",
            "NEXT WEEK"
        ]

        for (index, header) in requiredHeaders.enumerated() {
            guard let body = digestBody(for: header, at: index, in: normalizedText, headers: requiredHeaders) else {
                throw InsightError.incompleteResponse
            }
            guard body.count >= 20,
                  body.count <= 200,
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
        let requiredHeaders = [
            "YOUR MONTH IN ONE IMAGE",
            "THE TENSION AT THE CENTER",
            "A MOMENT THAT SHIFTED SOMETHING",
            "WHAT YOU'RE BECOMING",
            "WHAT WANTS TO BE RELEASED",
            "YOUR QUESTION FOR NEXT MONTH"
        ]

        for (index, header) in requiredHeaders.enumerated() {
            guard let body = digestBody(for: header, at: index, in: normalizedText, headers: requiredHeaders) else {
                throw InsightError.incompleteResponse
            }
            let endsCorrectly = header == "YOUR QUESTION FOR NEXT MONTH"
                ? body.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
                : endsAsCompleteSentence(body)
            guard body.count >= 20,
                  body.count <= 300,
                  endsCorrectly,
                  !hasDanglingEnding(body),
                  !containsJournalWriterFirstPerson(body) else {
                throw InsightError.incompleteResponse
            }
            if header == "YOUR MONTH IN ONE IMAGE" {
                let lower = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard lower.hasPrefix("this month felt like") || lower.hasPrefix("it was as if") else {
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

    private static func containsJournalWriterFirstPerson(_ text: String) -> Bool {
        let blockedPatterns = [
            #"\bI\s+(am|seem|feel|felt|think|thought|work|try|tried|need|needed|want|wanted|notice|noticed|sound|sounds|plan|planned|can|could|will|would|should|have|had|was|were)\b"#,
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

    private static func digestBody(for header: String, at index: Int, in text: String, headers: [String]) -> String? {
        guard let headerRange = text.range(of: "\(header):", options: [.caseInsensitive]) else { return nil }
        let afterHeader = String(text[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var bodyEnd = afterHeader.endIndex

        for nextHeader in headers.dropFirst(index + 1) {
            if let nextRange = afterHeader.range(of: "\(nextHeader):", options: [.caseInsensitive]) {
                bodyEnd = nextRange.lowerBound
                break
            }
        }

        return String(afterHeader[..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
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

        let recentBlock = formatEntries(sortedMonth, maxChars: 3200)
        let backgroundBlock = buildMemoryBrief(from: backgroundEntries, maxChars: 700)

        let today = Date().formatted(date: .abbreviated, time: .omitted)
        return """
        Monthly deep report context

        Today: \(today)

        \(statsBlock)

        Older context (before this month):
        \(backgroundBlock)

        This month's entries (newest first):
        \(recentBlock)
        """
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
        let backgroundBlock = buildMemoryBrief(from: backgroundEntries, maxChars: 1800)
        let entryBlock = formatEntries(entries, maxChars: 6500)
        return """
        Long-term context:
        \(backgroundBlock)

        Most relevant entries:
        \(entryBlock)

        Question: \(question)
        """
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
        let dated = entries.compactMap(\.createdAt).sorted()
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
        let excerpts = entries
            .prefix(5)
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

private extension String {
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
            .replacingOccurrences(of: "I’ve been", with: "you've been", options: .caseInsensitive)
            .replacingOccurrences(of: "I've been", with: "you've been", options: .caseInsensitive)
            .replacingOccurrences(of: "I'm trying", with: "you're trying", options: .caseInsensitive)
            .replacingOccurrences(of: "I am trying", with: "you're trying", options: .caseInsensitive)
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
            .replacingOccurrences(of: "their", with: "your", options: .caseInsensitive)
            .replacingOccurrences(of: "they", with: "you", options: .caseInsensitive)
            .replacingOccurrences(of: "the source mentions", with: "you wrote", options: .caseInsensitive)
            .replacingOccurrences(of: "this suggests that you are", with: "it sounds like you're", options: .caseInsensitive)
            .replacingOccurrences(of: "this suggests you are", with: "it sounds like you're", options: .caseInsensitive)
            .replacingOccurrences(of: "this suggests", with: "it sounds like", options: .caseInsensitive)
            .replacingOccurrences(of: "emotional weariness", with: "tiredness", options: .caseInsensitive)
            .replacingOccurrences(of: "mental health", with: "well-being", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanedMonthlyReportOutput() -> String {
        var result = cleanedInsightOutput()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let headers = ["YOUR MONTH IN ONE IMAGE", "THE TENSION AT THE CENTER", "A MOMENT THAT SHIFTED SOMETHING", "WHAT YOU'RE BECOMING", "WHAT WANTS TO BE RELEASED", "YOUR QUESTION FOR NEXT MONTH"]

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
        let headers = ["THIS WEEK'S THEME", "YOUR ENERGY", "WHAT'S BUILDING", "WATCH OUT FOR", "MOOD BOOST", "NEXT WEEK"]

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
