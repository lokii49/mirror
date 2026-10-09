#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Renders Ask's search-model offer card and Settings > Smarter Ask search to PNG (light, dark,
/// Sentinel) for design review. Skipped unless HARNESS_DUMP_DIR is set.
@MainActor
final class SmartSearchRenderHarness: XCTestCase {
    func test_renderOfferCardAndSettings() throws {
        guard var dir = ProcessInfo.processInfo.environment["HARNESS_DUMP_DIR"] else { throw XCTSkip("Set HARNESS_DUMP_DIR") }
        // On a device the host's paths aren't writable: "attachments" keeps the images in the result bundle.
        if dir == "attachments" { dir = NSTemporaryDirectory() + "smart-search-render" }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cases: [(String, UIUserInterfaceStyle, DisplayMode)] = [("light", .light, .classic), ("dark", .dark, .classic), ("sentinel", .dark, .sentinel)]
        for (name, style, mode) in cases {
            try render(AnyView(SmartSearchOfferCard(onAnswer: { _ in }).padding(16).frame(maxHeight: .infinity, alignment: .top).background(MirrorTheme.bgBase)),
                       mode: mode, style: style, height: 200, to: "\(dir)/smart-search-offer-\(name).png")
            try render(AnyView(NavigationStack { SmartSearchSettingsView() }),
                       mode: mode, style: style, height: 760, to: "\(dir)/smart-search-settings-\(name).png")
            for (state, bytes, label) in [(SemanticSearchService.ModelState.downloading, Int64(141_000_000), "downloading"),
                                          (.downloading, 0, "waiting"), (.installed, 0, "ready")] {
                try render(AnyView(SmartSearchOfferCard(previewState: state, downloadedBytes: bytes).padding(16)
                                    .frame(maxHeight: .infinity, alignment: .top).background(MirrorTheme.bgBase)),
                           mode: mode, style: style, height: 200, to: "\(dir)/smart-search-offer-\(label)-\(name).png")
            }
            try render(AnyView(NavigationStack { SmartSearchSettingsView(previewState: .downloading, downloadedBytes: 141_000_000) }),
                       mode: mode, style: style, height: 760, to: "\(dir)/smart-search-downloading-\(name).png")
            try render(AnyView(NavigationStack { SmartSearchSettingsView(previewState: .downloading, downloadedBytes: 0) }),
                       mode: mode, style: style, height: 760, to: "\(dir)/smart-search-starting-\(name).png")
        }
    }

    private func render(_ view: AnyView, mode: DisplayMode, style: UIUserInterfaceStyle, height: CGFloat, to path: String) throws {
        let host = UIHostingController(rootView: view.environment(\.appDisplayMode, mode))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: height)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: path))
        let attachment = XCTAttachment(image: image)
        attachment.name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
