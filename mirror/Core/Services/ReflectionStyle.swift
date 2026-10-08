import Foundation

/// How a daily reflection reads in the app. Every style keeps the verified quote
/// exactly as saved; only the fixed wording after it changes, so nothing here is
/// model-written and nothing can invent. Chosen per device (no schema, no sync).
///
/// Display-time only, like the second quote (`InsightService.reflectionWithAlsoQuote`):
/// `Insight.content` always stays in the Gentle shape that 3.0.9 / Mac 1.0.2 and
/// earlier parse, and the widget, lock screen and notifications keep showing it.
enum ReflectionStyle: String, CaseIterable, Identifiable, Sendable {
    /// Today's shape: the quote, then a line about how it sounds (and a tip on hard days).
    case gentle
    /// The quote alone.
    case quiet
    /// The quote, then a question the app builds around another part of the entry.
    case curious

    var id: String { rawValue }

    static let storageKey = "reflectionStyle"

    init(storedValue: String?) {
        self = storedValue.flatMap(ReflectionStyle.init(rawValue:)) ?? .gentle
    }

    static var current: ReflectionStyle {
        ReflectionStyle(storedValue: UserDefaults.standard.string(forKey: storageKey))
    }
}

extension InsightService {
    /// `reflectionWithAlsoQuote`, then the chosen style. Falls back to the Gentle
    /// shape whenever the style can't be built (not a grounded reflection, or no
    /// other part of the entry to ask about).
    static func reflectionForDisplay(_ content: String, entries: [Entry], generatedAt: Date,
                                     style: ReflectionStyle) -> (text: String, parts: GroundedNudgeParts?) {
        let base = reflectionWithAlsoQuote(content, entries: entries, generatedAt: generatedAt)
        guard style != .gentle, var parts = base.parts,
              let quoted = content.range(of: parts.open + parts.quote + parts.close) else { return base }
        let head = String(content[..<quoted.upperBound])
        let tail: String
        switch style {
        case .gentle:
            return base
        case .quiet:
            tail = parts.alsoQuote.map { " You also wrote, \"" + $0 + "\"" } ?? ""
        case .curious:
            let window = entries.filter { $0.createdAt <= generatedAt && $0.createdAt >= generatedAt.addingTimeInterval(-14 * 86_400) }
            guard let source = entryQuoting(parts.quote, in: window),
                  let question = followUpQuestion(for: parts, sourceText: source.text) else { return base }
            tail = " " + question
        }
        let text = head + tail
        parts.rest = String(text.dropFirst(head.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, parts)
    }
}
