import Foundation
import Testing
@testable import mirror

/// What Writing Tools must leave alone in the editors. Synthetic text only.
@Suite("Writing Tools guard")
struct WritingToolsGuardTests {
    private func strings(_ text: String, _ ranges: [NSRange]) -> [String] {
        ranges.map { (text as NSString).substring(with: $0) }
    }

    @Test func listMarkersAndPhotosAreIgnored() {
        let text = "Plan\n○  Buy milk\n✓  Call home\n•  Walk\n12.\tStretch\nA photo \u{fffc} here"
        let ranges = WritingToolsGuard.ignoredRanges(in: text, enclosing: NSRange(location: 0, length: (text as NSString).length))
        #expect(strings(text, ranges) == ["○  ", "✓  ", "•  ", "12.\t", "\u{fffc}"])
    }

    @Test func onlyInsideTheEnclosingRange() {
        let text = "○  One\n○  Two\n○  Three"
        let ns = text as NSString
        let second = ns.range(of: "○  Two")
        let ranges = WritingToolsGuard.ignoredRanges(in: text, enclosing: second)
        #expect(strings(text, ranges) == ["○  "])
        #expect(ranges.first?.location == second.location)
        // A selection starting mid-marker keeps only the part inside it.
        let mid = NSRange(location: second.location + 1, length: 4)
        #expect(WritingToolsGuard.ignoredRanges(in: text, enclosing: mid).allSatisfy { NSIntersectionRange($0, mid) == $0 })
    }

    @Test func legacyNumberedMarkersAndPlainText() {
        #expect(WritingToolsGuard.markerLength(of: "3.  Legacy") == 4)
        #expect(WritingToolsGuard.markerLength(of: "3. Not a marker") == 0)
        #expect(WritingToolsGuard.markerLength(of: "Just words") == 0)
        #expect(WritingToolsGuard.ignoredRanges(in: "", enclosing: NSRange(location: 0, length: 5)).isEmpty)
        #expect(WritingToolsGuard.ignoredRanges(in: "Plain words only.", enclosing: NSRange(location: 0, length: 17)).isEmpty)
    }
}
