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
        merge(from: sections(from: drafts, sources: sources))
    }

    /// The sections `drafts` fill so far (for the rig: which ones are still missing).
    static func sections(from drafts: [Draft], sources: [FMDailyGuard.Source]) -> [Section: (text: String, quote: String?)] {
        var filled: [Section: (text: String, quote: String?)] = [:]
        let texts = sources.map(\.text)
        let goodExists = sources.contains { !isHard($0.mood) }
        func line(_ text: String) -> String? {
            guard let clean = FMDailyGuard.cleanSentences(of: text, sources: sources, maxSentences: 1)?.text,
                  !speaksAboutThem(clean) else { return nil }
            return clean
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

    /// A digest whose sections the model could not fill are filled by the app (round 16).
    struct Assembled: Equatable {
        let verified: Verified
        /// The sections the app filled with a fixed line (and, for quote sections, maybe its own quote).
        let fixed: [Section]
    }

    static let fixedTheme = "A week of putting things into words."
    static let fixedReads: [Section: String] = [
        .energy: "That moment seems to have stayed with you.",
        .building: "That sounds like something worth holding on to.",
        .watch: "That may be worth keeping an eye on.",
    ]
    static let fixedHardBuildingRead = "That stood out this week."
    static let fixedBoost = "Pick one sentence from this week and write a little more about it."
    static let fixedNextWeek = "Next week, notice which of these comes up again."

    /// `merge`, then every section still empty after the model's attempts filled by the app: a quote
    /// section keeps a quote the model got right (else the app picks one from the week) with a fixed
    /// line; theme, boost and next week get fixed lines. nil only when the week has nothing to quote.
    static func assemble(_ drafts: [Draft], sources: [FMDailyGuard.Source]) -> Assembled? {
        var filled = sections(from: drafts, sources: sources)
        var fixed: [Section] = []
        let texts = sources.map(\.text)
        let goodExists = sources.contains { !isHard($0.mood) }
        let hardExists = sources.contains { isHard($0.mood) }
        func distinct(_ quote: String) -> Bool {
            let key = quote.lowercased()
            return !filled.values.contains { taken in
                guard let other = taken.quote?.lowercased() else { return false }
                return other.contains(key) || key.contains(other)
            }
        }
        func fits(_ section: Section, mood: String?) -> Bool {
            switch section {
            case .building: return !(goodExists && isHard(mood))
            case .watch: return !(hardExists && !isHard(mood))
            default: return true
            }
        }
        for section in [Section.energy, .building, .watch] where filled[section] == nil {
            var picked: (quote: String, mood: String?)?
            for draft in drafts {
                let text = section == .energy ? draft.energyQuote : section == .building ? draft.buildingQuote : draft.watchQuote
                guard let found = FMDailyGuard.locate(quote: text, in: texts), distinct(found.quote),
                      section != .building || fits(.building, mood: sources[found.index].mood) else { continue }
                picked = (found.quote, sources[found.index].mood)
                break
            }
            if picked == nil {
                let candidates = sources.flatMap { source in quotableSentences(of: source.text).map { ($0, source.mood) } }
                picked = candidates.first { distinct($0.0) && fits(section, mood: $0.1) } ?? candidates.first { distinct($0.0) }
            }
            guard let picked else { return nil }
            let opener = section == .energy ? energyOpener(mood: picked.mood) : "You wrote,"
            // A week with no other good day can leave WHAT'S BUILDING only a hard sentence ("Woke up with
            // a fever and chills."); "worth holding on to" after that reads wrong, so it gets a plain line.
            let read = section == .building && isHard(picked.mood) ? fixedHardBuildingRead : (fixedReads[section] ?? "")
            filled[section] = ("\(opener) \"\(picked.quote)\" \(read)", picked.quote)
            fixed.append(section)
        }
        if filled[.theme] == nil { filled[.theme] = (fixedTheme, nil); fixed.append(.theme) }
        if filled[.boost] == nil { filled[.boost] = (fixedBoost, nil); fixed.append(.boost) }
        if filled[.nextWeek] == nil { filled[.nextWeek] = (fixedNextWeek, nil); fixed.append(.nextWeek) }
        guard let verified = merge(from: filled) else { return nil }
        return Assembled(verified: verified, fixed: fixed)
    }

    private static func merge(from filled: [Section: (text: String, quote: String?)]) -> Verified? {
        guard let theme = filled[.theme], let energy = filled[.energy], let building = filled[.building],
              let watch = filled[.watch], let boost = filled[.boost], let nextWeek = filled[.nextWeek] else { return nil }
        return Verified(theme: theme.text, energy: energy.text, building: building.text, watch: watch.text, boost: boost.text, nextWeek: nextWeek.text)
    }

    /// Whole sentences of 4 to 25 words, ending in . ! ? or …, without quote marks: what the app may
    /// quote on its own.
    static func quotableSentences(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let characters = Array(text)
        for (i, ch) in characters.enumerated() {
            if ch.isNewline {
                current = ""
                continue
            }
            current.append(ch)
            let ends = ".!?…".contains(ch) && (i + 1 == characters.count || characters[i + 1].isWhitespace)
            guard ends else { continue }
            let sentence = current.trimmingCharacters(in: .whitespaces)
            current = ""
            let count = sentence.split(separator: " ").count
            if (4...25).contains(count), !sentence.contains(where: { "\"“”".contains($0) }) { out.append(sentence) }
        }
        return out
    }

    /// "That moment seems to show they need space": the line talks about the person instead of to them (round 23).
    static func speaksAboutThem(_ line: String) -> Bool {
        let tokens = Set(FMDailyGuard.words(line))
        let third: Set<String> = ["they", "them", "their", "themselves", "they're", "they've"]
        return !tokens.isDisjoint(with: third) && tokens.isDisjoint(with: ["you", "your", "you're", "you've", "yourself"])
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
