import Foundation
import SwiftUI
import Testing
@testable import mirror

/// Synthetic text only.
@Suite("Reader match navigation")
struct ReaderMatchesTests {
    @Test func rangesKeepOriginalCoordinatesAndSkipOverlaps() {
        let text = "Café first, then CAFE again; cafés later."
        let ranges = ReaderMatches.ranges(of: [EntrySearch.fold("cafe"), EntrySearch.fold("cafes")], in: text)
        let ns = text as NSString
        #expect(ranges.map { ns.substring(with: $0) } == ["Café", "CAFE", "cafés"])
    }

    @Test func locateOrdersBodyLinesThenVoiceNotesAndSkipsPhotoTokens() {
        let text = "River walk.\n\(NoteEditorCodec.appendingPhotoTokens(to: "", count: 1).trimmingCharacters(in: .whitespacesAndNewlines))\nBack by the river."
        let matches = ReaderMatches.locate(terms: ["river"], text: text, transcripts: [["Nothing here"], ["The river was loud"]])
        #expect(matches.map(\.place) == [.line(0), .line(2), .voiceNote(1)])
        #expect(ReaderMatches.locate(terms: [], text: text, transcripts: []).isEmpty)
    }

    @Test @MainActor func excludedWordsAreNotHighlighted() {
        #expect(ReaderSearchHighlight.terms(for: .parse("river -coffee tag:work")) == ["river"])
    }

    @Test func markedTranscriptMarksExactlyTheMatchedText() {
        // Accents, CJK and a multi-scalar emoji before the match: the UTF-16 ranges must land on the right characters.
        let text = "👩‍👩‍👧 Café 東京の川を歩いた。The river was loud."
        let marked = ReaderMatches.marked(text, terms: [EntrySearch.fold("cafe"), EntrySearch.fold("東京"), "river"], mark: .yellow)
        let pieces = marked.runs.compactMap { run -> String? in
            marked[run.range].backgroundColor == nil ? nil : String(marked[run.range].characters)
        }
        #expect(pieces == ["Café", "東京", "river"])
        #expect(String(marked.characters) == text)
        #expect(ReaderMatches.marked("Nothing to mark", terms: ["river"], mark: .yellow).runs.count == 1)
    }
}
