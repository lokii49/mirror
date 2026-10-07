import SwiftUI

/// The archive search's words, so the reader can highlight them and step through
/// matches. Set by the entry list whenever its search changes; empty when there
/// is no word search. Memory only.
@MainActor @Observable
final class ReaderSearchHighlight {
    static let shared = ReaderSearchHighlight()
    /// Folded search values (see `EntrySearch.fold`), excluded words left out.
    var terms: [String] = []

    static func terms(for query: EntrySearchQuery) -> [String] {
        query.terms.compactMap { term in
            guard !term.excluded, case .text(let value) = term.condition else { return nil }
            return value
        }
    }
}

/// Where a search word appears in an entry, in reading order: body paragraphs
/// first, then voice-note transcripts and their English translations.
nonisolated enum ReaderMatches {
    struct Location: Hashable, Sendable {
        enum Place: Hashable, Sendable {
            /// Paragraph index in the entry text (one per newline-separated line).
            case line(Int)
            /// Voice note index (0-based); matched in its transcript or translation.
            case voiceNote(Int)
        }
        let place: Place
        /// UTF-16 range inside the paragraph; nil for voice notes.
        let range: NSRange?
    }

    static func lineID(_ index: Int) -> String { "reader.line.\(index)" }
    static func voiceNoteID(_ index: Int) -> String { "reader.voice.\(index)" }

    static func locate(terms: [String], text: String, transcripts: [[String]]) -> [Location] {
        guard !terms.isEmpty else { return [] }
        var result: [Location] = []
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            if inlinePhotoIndex(from: line.trimmingCharacters(in: .whitespaces)) != nil { continue }
            for range in ranges(of: terms, in: line) {
                result.append(Location(place: .line(index), range: range))
            }
        }
        for (index, texts) in transcripts.enumerated()
        where texts.contains(where: { !ranges(of: terms, in: $0).isEmpty }) {
            result.append(Location(place: .voiceNote(index), range: nil))
        }
        return result
    }

    /// Non-overlapping occurrences of any term, in order, in the original text's
    /// UTF-16 coordinates (whole composed characters, so accents stay intact).
    static func ranges(of terms: [String], in text: String) -> [NSRange] {
        guard !text.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let locale = Locale(identifier: "en_US_POSIX")
        let ns = text as NSString
        var found: [NSRange] = []
        for term in terms where !term.isEmpty {
            var cursor = text.startIndex
            while cursor < text.endIndex,
                  let range = text.range(of: term, options: options, range: cursor..<text.endIndex, locale: locale) {
                found.append(ns.rangeOfComposedCharacterSequences(for: NSRange(range, in: text)))
                cursor = range.upperBound
            }
        }
        found.sort { $0.location != $1.location ? $0.location < $1.location : $0.length > $1.length }
        var merged: [NSRange] = []
        for range in found {
            if let last = merged.last, range.location < NSMaxRange(last) { continue }
            merged.append(range)
        }
        return merged
    }
}

/// "2 of 5" with previous/next, pinned to the bottom of the reader.
struct ReaderMatchBar: View {
    let matches: [ReaderMatches.Location]
    @Binding var index: Int
    @Environment(\.appDisplayMode) private var displayMode

    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Match \(index + 1) of \(matches.count)")
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 13, weight: .semibold))
                    .monospacedDigit()
                if case .voiceNote(let note) = matches[index].place {
                    Text("In voice note \(note + 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reader.matchPosition")
            Spacer(minLength: 8)
            Button { step(-1) } label: {
                Image(systemName: "chevron.up").frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityLabel("Previous match")
            .accessibilityIdentifier("reader.previousMatch")
            Button { step(1) } label: {
                Image(systemName: "chevron.down").frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .keyboardShortcut("g", modifiers: .command)
            .accessibilityLabel("Next match")
            .accessibilityIdentifier("reader.nextMatch")
        }
        .buttonStyle(.plain)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 14, style: .continuous)
                .stroke(displayMode == .sentinel ? MirrorTheme.inkBorder : Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Wraps around at either end, like Find in other apps.
    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        index = (index + delta + matches.count) % matches.count
    }
}

/// Wraps the reader's ScrollView: shows the match bar and scrolls to the
/// current match whenever it changes (including the first one on open).
struct ReaderMatchScrolling: ViewModifier {
    let matches: [ReaderMatches.Location]
    @Binding var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: ReaderMatches.Location? {
        matches.indices.contains(index) ? matches[index] : nil
    }

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !matches.isEmpty {
                        ReaderMatchBar(matches: matches, index: $index)
                    }
                }
                #if DEBUG
                .onReceive(NotificationCenter.default.publisher(for: .mirrorDebugReaderNextMatch)) { _ in
                    guard !matches.isEmpty else { return }
                    index = (index + 1) % matches.count
                }
                #endif
                .onChange(of: current) { _, match in
                    guard let match else { return }
                    let id: String
                    switch match.place {
                    case .line(let line): id = ReaderMatches.lineID(line)
                    case .voiceNote(let note): id = ReaderMatches.voiceNoteID(note)
                    }
                    if reduceMotion {
                        proxy.scrollTo(id, anchor: .center)
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
        }
    }
}

#if DEBUG
extension Notification.Name {
    /// Harness only: step the open reader to its next search match.
    static let mirrorDebugReaderNextMatch = Notification.Name("mirror.debug.readerNextMatch")
}
#endif
