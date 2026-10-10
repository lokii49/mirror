#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Renders a weekly digest at the default text size and at an accessibility size, to check that
/// reading text follows Dynamic Type (backlog A19). Skipped unless HARNESS_DUMP_DIR is set;
/// "tmp" writes to the app's tmp/reading-text.
@MainActor
final class ReadingTextRenderHarness: XCTestCase {
    func test_renderReadingTextSizes() throws {
        guard let setting = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else { throw XCTSkip("Set HARNESS_DUMP_DIR") }
        let dir = setting == "tmp" ? NSTemporaryDirectory() + "reading-text" : setting
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let insight = Insight(
            type: .weeklyDigest,
            content: "THIS WEEK'S THEME: A synthetic week of walks and deadlines.\nYOUR ENERGY: Steadier by Friday.",
            periodIdentifier: "2026-W41"
        )
        for (name, size) in [("default", DynamicTypeSize.large), ("ax3", DynamicTypeSize.accessibility3)] {
            let view = ScrollView { WeeklyDigestView(insight: insight).padding(16) }
                .background(MirrorTheme.bgBase)
                .environment(\.dynamicTypeSize, size)
            let host = UIHostingController(rootView: view)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 900)
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/digest-\(name).png"))
        }
    }
}
#endif
