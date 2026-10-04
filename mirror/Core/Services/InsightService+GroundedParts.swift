import Foundation

/// Reading a saved grounded daily reflection back into its parts, for screens that show the
/// quoted sentence apart from the line after it. This uses the same openers and closers as
/// `nudgeTextForOutsideApp` (English openers plus every localized `youWrote + open`), so a
/// reflection saved by any version in any of the 10 languages is recognised the same way.
extension InsightService {
    struct GroundedNudgeParts: Equatable {
        /// The user's own sentence, copied word for word from an entry.
        var quote: String
        /// Everything after the closing quote.
        var rest: String
        /// "en" or the key of `groundedLocales`.
        var languageCode: String
        /// The quote marks the text uses around `quote` (a straight pair in English).
        var open: String
        var close: String
        /// A second sentence from the same entry the app added after the reflection
        /// (`You also wrote, "…"`, English only, since 3.0.9). Not part of `rest`.
        var alsoQuote: String? = nil
    }

    /// Marks the app-added second quote in an English reflection: `… You also wrote, "<sentence>"`.
    static let groundedAlsoMarker = " You also wrote, \""

    /// Splits off the app-added second quote. `main` is the reflection as it was before it was added
    /// (quote + line after it), `tail` is whatever follows the second quote (the fixed tip on hard days).
    /// The second quote never contains a double quote (`secondGroundedQuote` skips those sentences), so
    /// the first `"` after the marker closes it.
    static func splittingAlsoQuote(_ text: String) -> (main: String, also: String?, tail: String) {
        guard let marker = text.range(of: groundedAlsoMarker, options: .backwards) else { return (text, nil, "") }
        let after = text[marker.upperBound...]
        guard let close = after.firstIndex(of: "\"") else { return (text, nil, "") }
        let also = String(after[..<close])
        guard !also.isEmpty else { return (text, nil, "") }
        let tail = after[after.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (String(text[..<marker.lowerBound]), also, tail)
    }

    static func groundedNudgeParts(of text: String) -> GroundedNudgeParts? {
        let split = splittingAlsoQuote(text)
        if let also = split.also {
            let rejoined = split.tail.isEmpty ? split.main : split.main + " " + split.tail
            guard var parts = groundedNudgeParts(of: rejoined), parts.languageCode == "en" else { return nil }
            parts.alsoQuote = also
            return parts
        }
        var shapes: [(opening: String, closer: String, code: String, open: String, close: String)] =
            groundedNudgeOpeners.map { ($0, "\" ", "en", "\"", "\"") }
        shapes += groundedLocales.map { ($0.value.youWrote + $0.value.open, $0.value.close + $0.value.joiner, $0.key, $0.value.open, $0.value.close) }
        for shape in shapes where text.hasPrefix(shape.opening) {
            let start = text.index(text.startIndex, offsetBy: shape.opening.count)
            // The line after the quote never contains the closer, so the last one ends the quote.
            guard let close = text.range(of: shape.closer, options: .backwards), close.lowerBound >= start else { continue }
            let quote = String(text[start..<close.lowerBound])
            guard !quote.isEmpty else { continue }
            let rest = text[close.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return GroundedNudgeParts(quote: quote, rest: rest, languageCode: shape.code, open: shape.open, close: shape.close)
        }
        return nil
    }

    /// Who wrote the line after the quote. Mirrors the provenance note in `InsightSignalSource`.
    struct GroundedRestAuthorship: Equatable {
        /// The part the on-device model wrote, if any.
        var modelText: String?
        /// The part the app adds itself (a fixed line by mood, or a fixed tip on difficult days).
        var appText: String?
    }

    static func groundedRestAuthorship(_ parts: GroundedNudgeParts) -> GroundedRestAuthorship {
        // Outside English the whole line after the quote is the app's fixed text.
        if parts.languageCode != "en" {
            return GroundedRestAuthorship(modelText: nil, appText: parts.rest.isEmpty ? nil : parts.rest)
        }
        let tips = groundedNudgeTips.values.joined()
        var model = parts.rest
        var app: [String] = []
        if let tip = tips.first(where: { model.hasSuffix($0) }) {
            model = String(model.dropLast(tip.count)).trimmingCharacters(in: .whitespaces)
            app.append(tip)
        }
        // The fixed mood line the app composes when no model-written sentence passed the checks.
        if let line = groundedNudgeMoodLines.values.first(where: { model == $0 }) {
            model = ""
            app.insert(line, at: 0)
        }
        return GroundedRestAuthorship(modelText: model.isEmpty ? nil : model, appText: app.isEmpty ? nil : app.joined(separator: " "))
    }

    /// The follow-up question the app composes around a part of the entry the reflection quoted
    /// that is not the quote itself, in the quote's own language. No model call. nil when the
    /// entry has nothing else quotable.
    static func followUpQuestion(for parts: GroundedNudgeParts, sourceText: String) -> String? {
        let quoted = [parts.quote] + (parts.alsoQuote.map { [$0] } ?? [])
        let others = followUpPhraseCandidates(in: sourceText).filter { phrase in
            quoted.allSatisfy { !phrase.contains($0) && !$0.contains(phrase) }
        }
        guard let phrase = others.last else { return nil }
        if parts.languageCode == "en" {
            return composedFollowUpQuestion(phrase: phrase, templates: FOLLOW_UP_GEMMA_QUESTIONS, open: "\u{201C}", close: "\u{201D}")
        }
        guard let loc = groundedLocales[parts.languageCode] else { return nil }
        return composedFollowUpQuestion(phrase: phrase, templates: loc.followUpQuestion, open: loc.open, close: loc.close)
    }
}
