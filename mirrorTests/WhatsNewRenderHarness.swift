#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Renders each What's New walkthrough page (light, Sentinel; en, de, ja; demo at its last frame) as
/// test attachments for review. Export with `xcresulttool export attachments`.
@MainActor
final class WhatsNewRenderHarness: XCTestCase {
    func test_renderWalkthroughPages() throws {
        let cards = FeatureCardRegistry.all.filter { $0.sinceVersion == "3.1.0" }
        let ordered = cards.filter { !WhatsNewWalkthrough.demoIDs.contains($0.id) } + cards.filter { WhatsNewWalkthrough.demoIDs.contains($0.id) }
        WhatsNewWalkthrough.snapshotPhase = 3
        defer { WhatsNewWalkthrough.snapshotPhase = nil }
        let looks: [(String, UIUserInterfaceStyle, DisplayMode, String)] = [("light-en", .light, .classic, "en"), ("sentinel-en", .dark, .sentinel, "en"),
                                                                             ("dark-de", .dark, .classic, "de"), ("light-ja", .light, .classic, "ja")]
        // Warm-up: the first window rendered in a run came out cut short, so it is thrown away.
        _ = try render(AnyView(WhatsNewWalkthrough(cards: ordered) {}), mode: .classic, style: .light)
        for (name, style, mode, locale) in looks {
            for i in ordered.indices {
                let view = AnyView(WhatsNewWalkthrough(cards: ordered, startIndex: i) {}
                    .environment(\.locale, Locale(identifier: locale)))
                let image = try render(view, mode: mode, style: style)
                let attachment = XCTAttachment(image: image)
                attachment.name = "wn-\(name)-\(i)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func render(_ view: AnyView, mode: DisplayMode, style: UIUserInterfaceStyle) throws -> UIImage {
        let host = UIHostingController(rootView: view.environment(\.appDisplayMode, mode))
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
        return image
    }
}
#endif
