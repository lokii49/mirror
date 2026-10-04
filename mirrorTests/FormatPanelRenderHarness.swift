#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Renders the iPhone Format panel to PNG (light, dark, Sentinel) for design review. Skipped unless
/// HARNESS_DUMP_DIR is set.
@MainActor
final class FormatPanelRenderHarness: XCTestCase {
    func test_renderFormatPanel() throws {
        guard let dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else { throw XCTSkip("Set HARNESS_DUMP_DIR") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cases: [(String, UIUserInterfaceStyle, DisplayMode)] = [("light", .light, .classic), ("dark", .dark, .classic), ("sentinel", .dark, .sentinel)]
        for (name, style, mode) in cases {
            let state = FormattingPanelState()
            state.activeParagraphStyle = .heading
            state.activeInlineStyles.bold = true
            state.activeHighlightIndex = 1
            let view = FormattingPanelView(state: state, presentation: .sheet, onClose: {})
                .environment(\.appDisplayMode, mode)
            let host = UIHostingController(rootView: view)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 360)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/format-panel-\(name).png"))
        }
    }
}
#endif
