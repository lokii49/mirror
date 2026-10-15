import Testing
import SwiftUI
import UIKit
@testable import mirror

/// Measures the formatting panel's content height at the default and a large accessibility
/// Dynamic Type size (audit 2.5). On iPhone the panel is the text view's `inputView`, sized to
/// its content and capped at `FormattingPanelView.maximumInputHeight`; past the cap the card's
/// own ScrollView takes over. Width 375 matches iPhone SE, the narrowest supported phone.
struct FormattingPanelSizingTests {
    private let seWidth: CGFloat = 375

    private func measuredHeight(dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(rootView: AnyView(
            FormattingPanelView(state: FormattingPanelState(), presentation: .sheet)
                .dynamicTypeSize(dynamicTypeSize)
                .environment(\.appDisplayMode, .classic)
        ))
        host.view.frame = CGRect(x: 0, y: 0, width: seWidth, height: 2000)
        let size = host.sizeThatFits(in: CGSize(width: seWidth, height: CGFloat.greatestFiniteMagnitude))
        return size.height
    }

    @Test @MainActor func contentFitsUnderTheCapAtDefaultTypeSize() {
        let height = measuredHeight(dynamicTypeSize: .large)
        // The common case shows the whole card with nothing scrolled away.
        #expect(height <= FormattingPanelView.maximumInputHeight, "Default-size panel content (\(height)pt) exceeds the \(FormattingPanelView.maximumInputHeight)pt cap")
        // Notes' card is about 260pt tall; much shorter means a row stopped rendering.
        #expect(height > 220, "Default-size panel content (\(height)pt) is shorter than its header, style row and two button rows")
    }

    @Test @MainActor func contentGrowsButStaysBoundedAtAccessibility3() {
        let height = measuredHeight(dynamicTypeSize: .accessibility3)
        // Past the cap the card scrolls, which is fine. The upper bound catches a row that stopped
        // scaling with typeScale and grew without limit.
        #expect(height > measuredHeight(dynamicTypeSize: .large), "accessibility3 content (\(height)pt) should grow with the type size")
        #expect(height < 900, "accessibility3 panel content (\(height)pt) is unexpectedly tall")
    }
}
