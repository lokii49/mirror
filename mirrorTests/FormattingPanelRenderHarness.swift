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
                try snap("panel-\(name)-\(active ? "active" : "plain")", active: active, mode: mode, style: style)
            }
        }
    }

    /// Long translations, the narrowest popover, and a large accessibility size: where equal-width
    /// cells could squeeze a label. Checklist row showing (the tallest, tightest case).
    func test_renderFormattingPanelStress() throws {
        for code in ["de", "ru", "fr", "ja", "pt-BR"] {
            try snap("stress-\(code)-375", active: true, mode: .classic, style: .light, locale: code, width: 375)
            try snap("stress-\(code)-sentinel", active: true, mode: .sentinel, style: .dark, locale: code, width: 375)
        }
        try snap("stress-en-popover320", active: true, mode: .classic, style: .light, width: 320, presentation: .popover)
        try snap("stress-de-popover320", active: true, mode: .classic, style: .light, locale: "de", width: 320, presentation: .popover)
        try snap("stress-en-ax3", active: true, mode: .classic, style: .light, width: 375, typeSize: .accessibility3, height: 900)
    }

    private func snap(_ name: String, active: Bool, mode: DisplayMode, style: UIUserInterfaceStyle, locale: String = "en",
                      width: CGFloat = 393, presentation: FormattingPanelView.Presentation = .sheet,
                      typeSize: DynamicTypeSize = .large, height: CGFloat = 520) throws {
        let state = FormattingPanelState()
        if active {
            state.activeParagraphStyle = .checklistUnchecked
            state.activeInlineStyles = InlineStyleSet(bold: true, italic: true)
            state.activeHighlightIndex = 1
            state.activeTextColorIndex = 3
            state.activeFontChoice = .serif
            state.activeLinkURL = "https://example.com"
        }
        let panel = FormattingPanelView(state: state, presentation: presentation, onClose: presentation == .sheet ? {} : nil)
        let view = AnyView(VStack(spacing: 0) {
            Spacer()
            if presentation == .sheet { panel.frame(height: typeSize == .large ? 360 : nil) } else { panel }
        }
        .background(MirrorTheme.bgBase)
        .environment(\.locale, Locale(identifier: locale))
        .dynamicTypeSize(typeSize))
        let image = try render(view, mode: mode, style: style, width: width, height: height)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func render(_ view: AnyView, mode: DisplayMode, style: UIUserInterfaceStyle, width: CGFloat, height: CGFloat) throws -> UIImage {
        let host = UIHostingController(rootView: view.environment(\.appDisplayMode, mode))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
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
