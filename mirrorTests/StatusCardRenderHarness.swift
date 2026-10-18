#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Renders the Insights status cards (loading, upgrade, couldn't-confirm, error) in Classic light,
/// Classic dark and Sentinel to PNGs for design review (backlog A18). Skipped unless
/// HARNESS_DUMP_DIR is set; "tmp" writes to the app's tmp/status-cards (pull it with
/// `devicectl device copy from --domain-type appDataContainer`).
@MainActor
final class StatusCardRenderHarness: XCTestCase {
    func test_renderStatusCards() throws {
        guard let setting = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else { throw XCTSkip("Set HARNESS_DUMP_DIR") }
        let dir = setting == "tmp" ? NSTemporaryDirectory() + "status-cards" : setting
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cases: [(String, UIUserInterfaceStyle, DisplayMode)] = [("light", .light, .classic), ("dark", .dark, .classic), ("sentinel", .dark, .sentinel)]
        for (name, style, mode) in cases {
            let view = ScrollView {
                VStack(spacing: 14) {
                    LoadingInsightCard(label: "Reflecting on your entries", sublabel: "This runs on your device.", icon: "sparkles")
                    UpgradePromptCard(title: "Daily reflection", subtitle: "Core unlocks a reflection every day.", onUpgrade: {})
                    GroundingFallbackCard(title: "Couldn't confirm this reflection", message: "A synthetic message for the card.", onRetry: {})
                    ErrorCard(message: "A synthetic error message.", onRetry: {})
                }
                .padding(16)
            }
            .background(MirrorTheme.bgBase)
            .environment(\.appDisplayMode, mode)
            let host = UIHostingController(rootView: view)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 760)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/status-cards-\(name).png"))
        }
    }
}
#endif
