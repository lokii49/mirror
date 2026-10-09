#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Renders the Aa formatting panel (light, dark, Sentinel; plain and with styles active) as test
/// attachments for design review. Export with `xcresulttool export attachments`.
@MainActor
final class FormattingPanelRenderHarness: XCTestCase {
    func test_renderFormattingPanel() throws {
        let modes: [(String, UIUserInterfaceStyle, DisplayMode)] = [("light", .light, .classic), ("dark", .dark, .classic), ("sentinel", .dark, .sentinel)]
        for (name, style, mode) in modes {
            for active in [false, true] {
                let state = FormattingPanelState()
                if active {
                    state.activeParagraphStyle = .checklistUnchecked
                    state.activeInlineStyles = InlineStyleSet(bold: true, italic: true)
                    state.activeHighlightIndex = 1
                    state.activeTextColorIndex = 3
                    state.activeFontChoice = .serif
                    state.activeLinkURL = "https://example.com"
                }
                let view = AnyView(VStack(spacing: 0) {
                    Spacer()
                    FormattingPanelView(state: state, presentation: .sheet, onClose: {})
                        .frame(height: 360)
                }.background(MirrorTheme.bgBase))
                let image = try render(view, mode: mode, style: style, height: 520)
                let attachment = XCTAttachment(image: image)
                attachment.name = "panel-\(name)-\(active ? "active" : "plain")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func render(_ view: AnyView, mode: DisplayMode, style: UIUserInterfaceStyle, height: CGFloat) throws -> UIImage {
        let host = UIHostingController(rootView: view.environment(\.appDisplayMode, mode))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: height)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }
}
#endif
