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
        /// The second sentence from the same entry shown after the reflection (3.0.9). Never stored in
        /// `Insight.content`: set by `reflectionWithAlsoQuote` where this version renders it, so older
        /// app versions reading a synced reflection see the 3.0.8 shape.
        var alsoQuote: String? = nil
    }

    /// 3.0.9: the reflection as this version shows it in the app: an English grounded reflection gets
    /// `You also wrote, "<sentence>"` with another sentence from the same day's entry, before the
    /// hard-day tip. Built at display time, never saved: reflections sync, and 3.0.8 / Mac 1.0.1 would
    /// read a stored second quote with their old parsers (leaking it to the widget and lock screen).
    /// `parts.alsoQuote` is set when a line was added. `entries` should cover the reflected day.
    static func reflectionWithAlsoQuote(_ content: String, entries: [Entry], generatedAt: Date) -> (text: String, parts: GroundedNudgeParts?) {
        guard var parts = groundedNudgeParts(of: content) else { return (content, nil) }
        guard parts.languageCode == "en" else { return (content, parts) }
        let earliest = generatedAt.addingTimeInterval(-14 * 86_400)
        let window = entries.filter { $0.createdAt <= generatedAt && $0.createdAt >= earliest }
        guard let source = entryQuoting(parts.quote, in: window) else { return (content, parts) }
        let sameDay = window.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: source.createdAt) }
        guard let also = secondGroundedQuote(excluding: parts.quote, source: sameDay) else { return (content, parts) }
        parts.alsoQuote = also
        let line = "You also wrote, \"" + also + "\""
        if let tip = groundedNudgeTips.values.joined().first(where: { content.hasSuffix($0) }) {
            let head = String(content.dropLast(tip.count)).trimmingCharacters(in: .whitespaces)
            return (head + " " + line + " " + tip, parts)
        }
        return (content + " " + line, parts)
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
