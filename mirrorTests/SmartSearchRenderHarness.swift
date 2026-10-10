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
            let total = SemanticSearchService.modelByteCount
            let states: [(ModelDownloadState, String)] = [
                (.downloading(progress: 141_000_000 / Double(total), bytesWritten: 141_000_000, bytesExpected: total), "downloading"),
                (.paused(resumable: true, bytesWritten: 141_000_000, bytesExpected: total), "paused"),
                (.downloading(progress: 0, bytesWritten: 0, bytesExpected: total), "starting"),
                (.verifying, "verifying"),
                (.failed("x"), "failed"),
                (.installed, "ready"),
                (.notStarted, "off"),
            ]
            // Gemma's Download Model button, as on the reflection / weekly digest card.
            try render(AnyView(VStack(spacing: 16) {
                ModelDownloadButton(title: mode == .sentinel ? "DOWNLOAD MODEL" : "Download Model", byteCount: ModelDownloadSpec.gemma.estimatedByteCount) {}
                ModelDownloadButton(title: mode == .sentinel ? "TRY AGAIN" : "Try Again", systemImage: "arrow.clockwise") {}
            }.frame(maxWidth: 320).padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(MirrorTheme.bgBase)),
                       mode: mode, style: style, height: 180, to: "\(dir)/gemma-button-\(name).png")
            for (state, label) in states {
                try render(AnyView(SmartSearchOfferCard(previewState: state).padding(16)
                                    .frame(maxHeight: .infinity, alignment: .top).background(MirrorTheme.bgBase)),
                           mode: mode, style: style, height: 200, to: "\(dir)/smart-search-offer-\(label)-\(name).png")
                try render(AnyView(NavigationStack { SmartSearchSettingsView(previewState: state) }),
                           mode: mode, style: style, height: 760, to: "\(dir)/smart-search-settings-\(label)-\(name).png")
                // Gemma's card on the reflection / weekly digest / monthly report.
                try render(AnyView(ModelDownloadProgressPanel(state: state, onPause: {}, onResume: {}).padding(20)
                                    .frame(maxHeight: .infinity, alignment: .top).background(MirrorTheme.bgBase)),
                           mode: mode, style: style, height: 160, to: "\(dir)/gemma-panel-\(label)-\(name).png")
            }
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
