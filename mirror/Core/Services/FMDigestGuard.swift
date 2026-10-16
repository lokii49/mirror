import Foundation

/// Checks on the weekly digest that Foundation Models writes as a structured draft (see
/// `FoundationModelEngine.generateWeeklyDigest`), in the shape of the Gemma digest: three sections
/// built on a sentence the person wrote this week, word for word, each followed by one model-written
/// line. Pure text logic, no app types, so tools/llmrig/fm/fmrig.swift compiles this same file.
///
/// Each quote must be found in this week's entries (shown in the entry's own words) and the three
/// quotes must differ. Every model-written line goes through `FMDailyGuard.cleanSentences`, checked
/// against the whole week. `merge` takes each section from the first draft in which it passes, so
/// one bad line costs a retry of that section, not the whole digest. Measured in
/// tools/llmrig/fm/RUBRIC_FM.md (round 15).
nonisolated enum FMDigestGuard {

    struct Draft {
        var theme: String
        var energyQuote: String
        var energyRead: String
        var buildingQuote: String
        var buildingRead: String
        var watchQuote: String
        var watchRead: String
        var boost: String
        var nextWeek: String
    }

    /// The six section bodies, in the digest's order, without their labels.
    struct Verified: Equatable {
        let theme: String
        let energy: String
        let building: String
        let watch: String
        let boost: String
        let nextWeek: String

        var sections: [String] { [theme, energy, building, watch, boost, nextWeek] }
    }

    enum Section: String, CaseIterable {
        case theme, energy, building, watch, boost, nextWeek
    }

    static let hardMoods: Set<String> = ["anxious", "overwhelmed", "frustrated", "drained", "sad", "numb"]

    /// The digest built from `drafts`, each section from the first draft where it passes; nil while
    /// any section has no passing draft yet.
    static func merge(_ drafts: [Draft], sources: [FMDailyGuard.Source]) -> Verified? {
        let filled = sections(from: drafts, sources: sources)
        guard let theme = filled[.theme], let energy = filled[.energy], let building = filled[.building],
              let watch = filled[.watch], let boost = filled[.boost], let nextWeek = filled[.nextWeek] else { return nil }
        return Verified(theme: theme.text, energy: energy.text, building: building.text, watch: watch.text, boost: boost.text, nextWeek: nextWeek.text)
    }

    /// The sections `drafts` fill so far (for the rig: which ones are still missing).
    static func sections(from drafts: [Draft], sources: [FMDailyGuard.Source]) -> [Section: (text: String, quote: String?)] {
        var filled: [Section: (text: String, quote: String?)] = [:]
        let texts = sources.map(\.text)
        let goodExists = sources.contains { !isHard($0.mood) }
        func line(_ text: String) -> String? {
            FMDailyGuard.cleanSentences(of: text, sources: sources, maxSentences: 1)?.text
        }
        func distinct(_ quote: String) -> Bool {
            let key = quote.lowercased()
            return !filled.values.contains { taken in
                guard let other = taken.quote?.lowercased() else { return false }
                return other.contains(key) || key.contains(other)
            }
        }
        for draft in drafts {
            if filled[.theme] == nil {
                let words = draft.theme.trimmingCharacters(in: CharacterSet(charactersIn: " .")).replacingOccurrences(
                    of: "^a week of ", with: "", options: [.regularExpression, .caseInsensitive])
                if let theme = line("A week of \(lowercasedStart(words)).") { filled[.theme] = (theme, nil) }
            }
            let quoted: [(Section, String, String)] = [
                (.energy, draft.energyQuote, draft.energyRead),
                (.building, draft.buildingQuote, draft.buildingRead),
                (.watch, draft.watchQuote, draft.watchRead),
            ]
            for (section, quoteText, read) in quoted where filled[section] == nil {
                guard let found = FMDailyGuard.locate(quote: quoteText, in: texts), distinct(found.quote),
                      let readLine = line(read) else { continue }
                let mood = sources[found.index].mood
                // Something growing comes from a day that wasn't hard, when the week has one (the Gemma
                // digest's rule: a hopeful section quoting a grief entry reads wrong).
                if section == .building, goodExists, isHard(mood) { continue }
                let opener = section == .energy ? energyOpener(mood: mood) : "You wrote,"
                filled[section] = ("\(opener) \"\(found.quote)\" \(readLine)", found.quote)
            }
            if filled[.boost] == nil, let boost = line(draft.boost) { filled[.boost] = (boost, nil) }
            if filled[.nextWeek] == nil, let next = line(draft.nextWeek) { filled[.nextWeek] = (next, nil) }
        }
        return filled
    }

    /// "You seemed most drained when you wrote," with the mood the person chose for that entry.
    static func energyOpener(mood: String?) -> String {
        guard let mood = mood?.lowercased(), !mood.isEmpty else { return "This week you wrote," }
        let word = mood == "peaceful" ? "at peace" : mood
        return "You seemed most \(word) when you wrote,"
    }

    private static func isHard(_ mood: String?) -> Bool {
        guard let mood else { return false }
        return hardMoods.contains(mood.lowercased())
    }

    /// "Settling in" -> "settling in", but a word with a capital past its first letter keeps it.
    private static func lowercasedStart(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let firstWord = text.split(separator: " ").first.map(String.init) ?? text
        if firstWord.count > 1, firstWord.dropFirst().contains(where: \.isUppercase) { return text }
        return first.lowercased() + text.dropFirst()
    }
}
