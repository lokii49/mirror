import Testing
import SwiftUI
import UIKit
@testable import mirror

// Track C of the 2.1.0 design plan (.claude/2.1.0-design-plan.md): WidgetTheme holds a frozen
// copy of the dark variant of the MirrorTheme tokens the widgets need — the widget extension
// can't import MirrorTheme. These tests pin each WidgetTheme value to its MirrorTheme
// counterpart, resolved in dark mode, so a later change to MirrorTheme that doesn't also touch
// WidgetTheme fails here instead of shipping a widget whose chrome no longer matches the app.

@Suite("Widget theme tokens")
struct WidgetThemeTokenTests {
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    /// RGB components of a SwiftUI Color, resolved for the given traits.
    private func rgb(_ color: Color, _ traits: UITraitCollection) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func expectSameColor(
        _ widget: Color, _ appToken: Color,
        _ label: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let w = rgb(widget, dark)
        let a = rgb(appToken, dark)
        let tol: CGFloat = 1.0 / 255.0 + 0.001
        #expect(abs(w.r - a.r) <= tol && abs(w.g - a.g) <= tol && abs(w.b - a.b) <= tol,
                "\(label): widget \(w) vs MirrorTheme \(a)", sourceLocation: sourceLocation)
    }

    @Test func bgTop_matchesInkRaised() { expectSameColor(WidgetTheme.bgTop, MirrorTheme.inkRaised, "bgTop / inkRaised") }
    @Test func bgBottom_matchesInkMid() { expectSameColor(WidgetTheme.bgBottom, MirrorTheme.inkMid, "bgBottom / inkMid") }
    @Test func violet_matchesViolet() { expectSameColor(WidgetTheme.violet, MirrorTheme.violet, "violet") }
    @Test func violetLight_matchesVioletLight() { expectSameColor(WidgetTheme.violetLight, MirrorTheme.violetLight, "violetLight") }
    @Test func ember_matchesEmber() { expectSameColor(WidgetTheme.ember, MirrorTheme.ember, "ember") }

    @Test func sentinelBg_isTheFrozenWidgetOnlyValue() {
        // No MirrorTheme counterpart — lock the literal so it's a deliberate change if touched.
        let c = rgb(WidgetTheme.sentinelBg, dark)
        #expect(abs(c.r - 0x0B / 255.0) < 0.002)
        #expect(abs(c.g - 0x0B / 255.0) < 0.002)
        #expect(abs(c.b - 0x0E / 255.0) < 0.002)
    }

    @Test func appGroupID_isStable() {
        #expect(WidgetShared.appGroupID == "group.com.lokesh.mirror")
    }
}
