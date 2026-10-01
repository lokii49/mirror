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
    }

    static func groundedNudgeParts(of text: String) -> GroundedNudgeParts? {
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
        if let tip = tips.first(where: { parts.rest.hasSuffix($0) }) {
            let model = String(parts.rest.dropLast(tip.count)).trimmingCharacters(in: .whitespaces)
            return GroundedRestAuthorship(modelText: model.isEmpty ? nil : model, appText: tip)
        }
        return GroundedRestAuthorship(modelText: parts.rest.isEmpty ? nil : parts.rest, appText: nil)
    }

    /// The follow-up question the app composes around a part of the entry the reflection quoted
    /// that is not the quote itself, in the quote's own language. No model call. nil when the
    /// entry has nothing else quotable.
    static func followUpQuestion(for parts: GroundedNudgeParts, sourceText: String) -> String? {
        let others = followUpPhraseCandidates(in: sourceText).filter { phrase in
            !phrase.contains(parts.quote) && !parts.quote.contains(phrase)
        }
        guard let phrase = others.last else { return nil }
        if parts.languageCode == "en" {
            return composedFollowUpQuestion(phrase: phrase, templates: FOLLOW_UP_GEMMA_QUESTIONS, open: "\u{201C}", close: "\u{201D}")
        }
        guard let loc = groundedLocales[parts.languageCode] else { return nil }
        return composedFollowUpQuestion(phrase: phrase, templates: loc.followUpQuestion, open: loc.open, close: loc.close)
    }
}
