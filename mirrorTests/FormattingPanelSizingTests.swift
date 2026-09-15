import Testing
import SwiftUI
import UIKit
@testable import mirror

/// Measures the formatting panel's actual content height and horizontal-row
/// reachability at large Dynamic Type sizes (audit 2.5) — the panel is
/// presented as `textView.inputView` on iPhone with a fixed 360pt frame
/// (`NoteEditorTextView.swift`), but its `.sheet` presentation wraps
/// `panelRows` in a `ScrollView`, so the fixed frame only needs to stay a
/// *usable viewing height*, not fit every row. This pins that down with a
/// number instead of a guess — it's what caught the 346 literal clipping the
/// default-size, checklist-active panel by 1pt before 360 replaced it.
///
/// Width 375 matches iPhone SE, the device the audit item names for
/// clipping. Row 3b (checklist bulk ops) only renders with a checklist
/// paragraph active, so it's the tallest configuration and the one measured
/// here — a `FormattingPanelState()` default (`.body`) would silently skip it.
struct FormattingPanelSizingTests {
    private let seWidth: CGFloat = 375

    private func measuredHeight(dynamicTypeSize: DynamicTypeSize, includeChecklistBulkOpsRow: Bool) -> CGFloat {
        let state = FormattingPanelState()
        if includeChecklistBulkOpsRow { state.activeParagraphStyle = .checklistUnchecked }
        let host = UIHostingController(rootView: AnyView(
            FormattingPanelView(state: state, presentation: .sheet)
                .dynamicTypeSize(dynamicTypeSize)
                .environment(\.appDisplayMode, .classic)
        ))
        host.view.frame = CGRect(x: 0, y: 0, width: seWidth, height: 2000)
        let size = host.sizeThatFits(in: CGSize(width: seWidth, height: CGFloat.greatestFiniteMagnitude))
        return size.height
    }

    @Test @MainActor func contentFitsWithinFixedInputViewHeightAtDefaultTypeSize() {
        let height = measuredHeight(dynamicTypeSize: .large, includeChecklistBulkOpsRow: true)
        // At the system default, the panel — including the checklist bulk-ops
        // row, its tallest configuration — should need no more than its fixed
        // 360pt input-view frame — scrolling shouldn't be necessary for the
        // common case.
        #expect(height <= 360, "Default-size panel content (\(height)pt) now exceeds the fixed 360pt input view — was 360 chosen to fit this, or does it need raising?")
    }

    @Test @MainActor func contentGrowsButStaysBoundedAtAccessibility3() {
        let height = measuredHeight(dynamicTypeSize: .accessibility3, includeChecklistBulkOpsRow: true)
        // Growing past the fixed frame at a large accessibility size is
        // expected and fine — panelRows scrolls inside the .sheet
        // presentation. The lower bound here is a sanity check tied to the
        // *current* 360pt literal (raising that literal legitimately, e.g. to
        // give the panel more breathing room, would fail this for a reason
        // that isn't a regression — update it alongside the literal). The
        // upper bound is the one carrying real signal: if it trips, a row's
        // height stopped scaling with typeScale and instead grew without
        // limit, or a new row was added with no horizontal scroll to relieve
        // it — see the audit 2.5 STATUS block.
        #expect(height > 360, "Expected accessibility3 content to exceed the fixed 360pt frame (confirming the .sheet ScrollView is actually doing something) — got \(height)pt")
        #expect(height < 900, "accessibility3 panel content (\(height)pt) is unexpectedly tall — check for a row that isn't scaling with typeScale or scrolling horizontally")
    }
}
