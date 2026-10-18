import Testing
import Foundation
@testable import mirror

// The iPhone reader drew entry text at fixed sizes, so Dynamic Type left it unchanged (backlog
// A19 follow-up). Its sizes now scale with the text-size setting and are unchanged at the default.
@Suite("Reader entry text sizes")
@MainActor
struct ReaderTextSizesTests {
    @Test func defaultTextSize_keepsTheEditorsSizes() {
        let sizes = ReaderTextSizes(scale: 1)
        #expect(sizes.body == 17)
        #expect(sizes.lineSpacing == 6)
        #expect(sizes.title == 30)
        #expect(sizes.heading == 22)
        #expect(sizes.monospaced == 16)
        #expect(sizes.marker == 24)
    }

    @Test func largerTextSize_scalesEveryLevelTogether() {
        let base = ReaderTextSizes(scale: 1)
        let large = ReaderTextSizes(scale: 1.5)
        #expect(large.body == base.body * 1.5)
        #expect(large.title == base.title * 1.5)
        #expect(large.heading == base.heading * 1.5)
        #expect(large.monospaced == base.monospaced * 1.5)
        #expect(large.lineSpacing == base.lineSpacing * 1.5)
        // The hierarchy stays: title > heading > body > monospaced.
        #expect(large.title > large.heading && large.heading > large.body && large.body > large.monospaced)
    }
}
