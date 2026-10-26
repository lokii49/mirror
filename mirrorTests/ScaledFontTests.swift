import Testing
import SwiftUI
@testable import mirror

// Interface text follows the person's text size through `scaledFont` (UI pass 2026-10-24): the
// size at the default setting is unchanged, and it grows with the system text style nearest it.
// The mapping is the one place to argue about how a given size grows.
@Suite("Scaled interface fonts")
struct ScaledFontTests {
    @Test func eachSystemTextStyleSizeMapsToItsOwnStyle() {
        let expected: [(CGFloat, Font.TextStyle)] = [
            (11, .caption2), (12, .caption), (13, .footnote), (15, .subheadline), (16, .callout),
            (17, .body), (20, .title3), (22, .title2), (28, .title), (34, .largeTitle),
        ]
        for (size, style) in expected {
            #expect(MirrorTheme.textStyle(near: size) == style, "size \(size)")
        }
    }

    @Test func inBetweenSizesGoToTheNearestStyle() {
        #expect(MirrorTheme.textStyle(near: 9) == .caption2)
        #expect(MirrorTheme.textStyle(near: 12.5) == .footnote)
        #expect(MirrorTheme.textStyle(near: 14) == .subheadline)
        #expect(MirrorTheme.textStyle(near: 18) == .body)
        #expect(MirrorTheme.textStyle(near: 26) == .title)
        #expect(MirrorTheme.textStyle(near: 44) == .largeTitle)
    }
}
