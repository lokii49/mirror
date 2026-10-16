import Foundation

/// Checks on the monthly report that Foundation Models writes as a structured draft (see
/// `FoundationModelEngine.generateMonthlyReport`), in the shape of the Gemma report. Pure text logic, no
/// app types, so tools/llmrig/fm/fmrig.swift compiles this same file. Same approach as `FMDigestGuard`:
/// quotes found in the month and shown in the entry's own words, every model line through
/// `FMDailyGuard.cleanSentences`, each section from the first draft where it passes, and the app filling
/// whatever is still missing. Measured in tools/llmrig/fm/RUBRIC_FM.md (round 19).
nonisolated enum FMMonthlyGuard {

    struct Source {
        let text: String
        let mood: String?
        /// How the entry's day is shown ("12 Oct").
        let day: String
    }

    struct Draft {
        var image: String
        var tensionA: String
        var tensionB: String
        var momentQuote: String
        var momentRead: String
        var becomingQuote: String
        var becomingRest: String
        var releaseQuote: String
        var releaseRest: String
        var question: String
    }

    enum Section: String, CaseIterable {
        case image, tension, moment, becoming, release, question
    }

    struct Assembled: Equatable {
        /// The six section bodies, in the report's order, without their labels.
        let sections: [String]
        /// The sections the app filled with a fixed line (and, for quote sections, maybe its own quote).
        let fixed: [Section]
    }

    static let hardMoods: Set<String> = ["anxious", "overwhelmed", "frustrated", "drained", "sad", "numb"]
    /// Never quoted under "let go of" (the Gemma report's rule).
    static let griefMoods: Set<String> = ["sad", "numb"]

    static let fixedImage = "A month told in your own words."
    static let fixedTension = "This month held more than one thing at once."
    static let fixedMomentRead = "That moment seems to have stayed with you."
    static let fixedBecoming = "Something in you seems to be growing."
    static let fixedRelease = "Maybe some of that can be set down."
    static let fixedQuestion = "What from this month do you want to carry into the next?"

    /// Each section from the first draft where it passes; nil while any is missing.
    static func merge(_ drafts: [Draft], sources: [Source]) -> [String]? {
        let filled = sections(from: drafts, sources: sources)
        let ordered = Section.allCases.compactMap { filled[$0]?.text }
        return ordered.count == Section.allCases.count ? ordered : nil
    }

    static func sections(from drafts: [Draft], sources: [Source]) -> [Section: (text: String, quote: String?)] {
        var filled: [Section: (text: String, quote: String?)] = [:]
        let guardSources = sources.map { FMDailyGuard.Source(text: $0.text, mood: $0.mood) }
        let texts = sources.map(\.text)
        func line(_ text: String) -> String? {
            FMDailyGuard.cleanSentences(of: text, sources: guardSources, maxSentences: 1)?.text
        }
        func distinct(_ quote: String) -> Bool {
            let key = quote.lowercased()
            return !filled.values.contains { taken in
                guard let other = taken.quote?.lowercased() else { return false }
                return other.contains(key) || key.contains(other)
            }
        }
        for draft in drafts {
            if filled[.image] == nil {
                let words = trimmed(draft.image).replacingOccurrences(of: "^an? ", with: "", options: [.regularExpression, .caseInsensitive])
                if !words.isEmpty, let image = line("A \(lowercasedStart(words)).") { filled[.image] = (image, nil) }
            }
            if filled[.tension] == nil {
                let a = lowercasedStart(trimmed(draft.tensionA)), b = lowercasedStart(trimmed(draft.tensionB))
                if !a.isEmpty, !b.isEmpty, a.lowercased() != b.lowercased(),
                   let tension = line("You seem pulled between \(a) and \(b).") {
                    filled[.tension] = (tension, nil)
                }
            }
            if filled[.moment] == nil, let found = FMDailyGuard.locate(quote: draft.momentQuote, in: texts), distinct(found.quote),
               let read = line(draft.momentRead) {
                filled[.moment] = ("On \(sources[found.index].day), you wrote, \"\(found.quote)\" \(read)", found.quote)
            }
            if filled[.becoming] == nil, let found = FMDailyGuard.locate(quote: draft.becomingQuote, in: texts), distinct(found.quote),
               fits(.becoming, mood: sources[found.index].mood, sources: sources),
               let rest = line("You seem to be becoming someone who \(continuation(draft.becomingRest, after: "someone who")).") {
                filled[.becoming] = ("You wrote, \"\(found.quote)\" \(rest)", found.quote)
            }
            if filled[.release] == nil, let found = FMDailyGuard.locate(quote: draft.releaseQuote, in: texts), distinct(found.quote),
               fits(.release, mood: sources[found.index].mood, sources: sources),
               let rest = line("Maybe it's time to let go of \(continuation(draft.releaseRest, after: "let go of")).") {
                filled[.release] = ("You wrote, \"\(found.quote)\" \(rest)", found.quote)
            }
            if filled[.question] == nil {
                let q = trimmed(draft.question)
                if q.hasSuffix("?"), let clean = line(q), clean.hasSuffix("?") { filled[.question] = (clean, nil) }
            }
        }
        return filled
    }

    /// `merge`, then every section still empty filled by the app. nil only when the month has nothing to quote.
    static func assemble(_ drafts: [Draft], sources: [Source]) -> Assembled? {
        var filled = sections(from: drafts, sources: sources)
        var fixed: [Section] = []
        let texts = sources.map(\.text)
        func distinct(_ quote: String) -> Bool {
            let key = quote.lowercased()
            return !filled.values.contains { taken in
                guard let other = taken.quote?.lowercased() else { return false }
                return other.contains(key) || key.contains(other)
            }
        }
        for section in [Section.moment, .becoming, .release] where filled[section] == nil {
            var picked: (quote: String, index: Int)?
            // A quote the model got right, even though its line didn't pass.
            for draft in drafts {
                let text = section == .moment ? draft.momentQuote : section == .becoming ? draft.becomingQuote : draft.releaseQuote
                if let found = FMDailyGuard.locate(quote: text, in: texts), distinct(found.quote),
                   fits(section, mood: sources[found.index].mood, sources: sources) {
                    picked = found
                    break
                }
            }
            if picked == nil {
                for (index, source) in sources.enumerated() where fits(section, mood: source.mood, sources: sources) {
                    if let quote = FMDigestGuard.quotableSentences(of: source.text).first(where: distinct) {
                        picked = (quote, index)
                        break
                    }
                }
            }
            if section == .release, picked == nil {
                // No hard day that may be let go of: the Gemma report's plain line.
                filled[.release] = (fixedRelease, nil)
                fixed.append(.release)
                continue
            }
            guard let picked else { return nil }
            let body: String
            switch section {
            case .moment: body = "On \(sources[picked.index].day), you wrote, \"\(picked.quote)\" \(fixedMomentRead)"
            case .becoming: body = "You wrote, \"\(picked.quote)\" \(fixedBecoming)"
            default: body = "You wrote, \"\(picked.quote)\" \(fixedRelease)"
            }
            filled[section] = (body, picked.quote)
            fixed.append(section)
        }
        if filled[.image] == nil { filled[.image] = (fixedImage, nil); fixed.append(.image) }
        if filled[.tension] == nil { filled[.tension] = (fixedTension, nil); fixed.append(.tension) }
        if filled[.question] == nil { filled[.question] = (fixedQuestion, nil); fixed.append(.question) }
        let ordered = Section.allCases.compactMap { filled[$0]?.text }
        guard ordered.count == Section.allCases.count else { return nil }
        return Assembled(sections: ordered, fixed: fixed)
    }

    /// Becoming: a day that wasn't hard, when the month has one. Release: a hard day that isn't grief.
    private static func fits(_ section: Section, mood: String?, sources: [Source]) -> Bool {
        let key = mood?.lowercased() ?? ""
        switch section {
        case .becoming:
            let goodExists = sources.contains { !hardMoods.contains($0.mood?.lowercased() ?? "") }
            return !(goodExists && hardMoods.contains(key))
        case .release:
            return hardMoods.contains(key) && !griefMoods.contains(key)
        default:
            return true
        }
    }

    /// The model's continuation without a repeated opener or end mark ("someone who listens" -> "listens").
    private static func continuation(_ text: String, after opener: String) -> String {
        var t = trimmed(text)
        if let range = t.range(of: opener, options: .caseInsensitive), t.distance(from: t.startIndex, to: range.lowerBound) < 40 {
            t = String(t[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return lowercasedStart(t)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " .\n"))
    }

    private static func lowercasedStart(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let firstWord = text.split(separator: " ").first.map(String.init) ?? text
        if firstWord.count > 1, firstWord.dropFirst().contains(where: \.isUppercase) { return text }
        return first.lowercased() + text.dropFirst()
    }
}
