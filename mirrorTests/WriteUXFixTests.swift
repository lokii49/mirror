import Testing
import Foundation
@testable import mirror

// Write view UX audit fixes (2026-10-09, `.claude/3.1.0-write-view-ux-audit.md`). Synthetic text only.
@MainActor
struct WriteUXFixTests {

    @Test func hashtagIsDroppedSoChipsDontShowTwo() {
        #expect(WriteView.normalizedTags(from: "#work") == ["work"])
        #expect(WriteView.normalizedTags(from: "##Work") == ["work"])
        #expect(WriteView.normalizedTags(from: "＃仕事") == ["仕事"])
    }

    @Test func commasAndSemicolonsMakeSeveralTags() {
        #expect(WriteView.normalizedTags(from: "work, sleep;#run") == ["work", "sleep", "run"])
        #expect(WriteView.normalizedTags(from: "仕事、睡眠") == ["仕事", "睡眠"])
    }

    @Test func spacesInsideATagStillBecomeDashes() {
        #expect(WriteView.normalizedTags(from: "  Deep   Work ") == ["deep-work"])
    }

    @Test func emptyPiecesAndDuplicatesAreSkipped() {
        #expect(WriteView.normalizedTags(from: " , ;# ,") == [])
        #expect(WriteView.normalizedTags(from: "work, Work, #work") == ["work"])
    }

    @Test func draftsWithoutAFontStillDecode() throws {
        let old = #"{"version":1,"text":"Synthetic draft.","tags":["walk"]}"#
        let payload = try JSONDecoder().decode(WriteDraftStore.Payload.self, from: Data(old.utf8))
        #expect(payload.fontChoice == nil)
        #expect(payload.entryDate == nil)
        #expect(payload.text == "Synthetic draft.")
    }

    @Test func pickedDateAndFontRoundTripInANewEntryDraft() throws {
        var payload = WriteDraftStore.Payload()
        payload.text = "Synthetic draft."
        payload.entryDate = Date(timeIntervalSince1970: 1_790_000_000)
        payload.fontChoice = WritingFontChoice.serif.rawValue
        let decoded = try JSONDecoder().decode(WriteDraftStore.Payload.self, from: JSONEncoder().encode(payload))
        #expect(decoded == payload)
    }

    @Test func aFontOnlyChangeIsADraftChange() {
        let date = Date(timeIntervalSince1970: 0)
        let a = WriteView.DraftChangeKey(textStyleData: nil, inlineStyleData: nil, tags: [], entryDate: date, fontChoice: WritingFontChoice.system.rawValue)
        let b = WriteView.DraftChangeKey(textStyleData: nil, inlineStyleData: nil, tags: [], entryDate: date, fontChoice: WritingFontChoice.serif.rawValue)
        #expect(a != b)
    }
}
