#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import mirror

/// Real download of the search model from models.mirrornotes.org (Wi-Fi, about 334 MB): progress must
/// rise while it runs, and Settings > Smarter Ask search must show it. Skipped unless
/// RUN_SEARCH_MODEL_DOWNLOAD is set, since it removes and re-downloads the model.
@MainActor
final class SearchModelDownloadProgressTests: XCTestCase {
    func test_downloadReportsRisingProgress() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SEARCH_MODEL_DOWNLOAD"] != nil else {
            throw XCTSkip("Set RUN_SEARCH_MODEL_DOWNLOAD to run the real download")
        }
        let service = SemanticSearchService.shared
        let savedConsent = SemanticSearchService.consent
        defer { SemanticSearchService.consent = savedConsent }
        await service.removeModel()
        SemanticSearchService.consent = .accepted
        await service.ensureModelDownloadStarted()

        var samples: [Int64] = []
        var rendered = false
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            let state = await service.modelState
            if state != .downloading { break }
            let bytes = await service.downloadedBytes
            samples.append(bytes)
            if !rendered, bytes > 20_000_000 {
                rendered = true
                try attachScreen(named: "settings-downloading")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        let finalState = await service.modelState
        let rising = samples.filter { $0 > 0 }
        let line = "samples \(samples.count), nonzero \(rising.count), first \(rising.first ?? 0), last \(rising.last ?? 0), final \(finalState)"
        print("DOWNLOAD_PROGRESS " + line)
        let note = XCTAttachment(string: line)
        note.lifetime = .keepAlways
        add(note)
        XCTAssertEqual(finalState, .installed)
        XCTAssertGreaterThan(rising.count, 3, "progress should be readable several times during the download")
        XCTAssertEqual(rising, rising.sorted(), "bytes received must never go down")
        XCTAssertTrue(rendered, "the downloading screen should have been captured")
    }

    private func attachScreen(named name: String) throws {
        let host = UIHostingController(rootView: NavigationStack { SmartSearchSettingsView() }.environment(\.appDisplayMode, .classic))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
