import Foundation
import Testing
@testable import mirror

/// Which photos the editor and reader draw as square tiles (Suggestions option A, 2026-11-07).
/// The stored text keeps one token per line; this is display only.
@Suite("Photo runs")
struct PhotoRunsTests {
    private func tiles(_ text: String, landscape: Set<Int> = []) -> Set<Int> {
        let ns = text as NSString
        let ranges = allPhotoTokens(in: text).map { NSRange($0.range, in: text) }.sorted { $0.location < $1.location }
        let byLocation = Dictionary(uniqueKeysWithValues: ranges.enumerated().map { ($1.location, $0) })
        return PhotoRuns.tileMatches(ranges, in: ns) { landscape.contains(byLocation[$0.location]!) }
    }

    @Test func aMapLeadsAndTheRestAreTiles() {
        let text = "Dinner\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n[[mirror-photo-2]]\n"
        #expect(tiles(text, landscape: [0]) == [1, 2])
    }

    @Test func squareArtworkIsAllTiles() {
        let text = "Songs\n🎵 A · B\n[[mirror-photo-0]]\n[[mirror-photo-1]]\n[[mirror-photo-2]]\n"
        #expect(tiles(text) == [0, 1, 2])
    }

    @Test func aSinglePhotoIsNeverATile() {
        #expect(tiles("Walk\n[[mirror-photo-0]]\nThen tea.") .isEmpty)
        #expect(tiles("[[mirror-photo-0]]\ntext\n[[mirror-photo-1]]").isEmpty, "text between photos breaks the run")
    }

    @Test func aPhotoSharingItsLineWithTextStaysFullWidth() {
        #expect(tiles("look [[mirror-photo-0]]\n[[mirror-photo-1]]").isEmpty)
    }

    @Test func linesFormMatchTheEditorRule() {
        let lines = ["Dinner", "P", "P", "P", "text", "P"]
        let result = PhotoRuns.tileLines(count: lines.count, photoLine: { lines[$0] == "P" }, isLandscape: { $0 == 1 })
        #expect(result == [2, 3])
    }
}
