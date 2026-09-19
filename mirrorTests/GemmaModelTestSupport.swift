import Foundation
@testable import mirror

/// The Gemma weights aren't bundled in the app — ModelDownloadManager fetches them on demand
/// to keep the IPA small (see its own doc comment: "cut the App Store download size by roughly
/// 800MB") — and a fresh simulator has never run a real download, so
/// LocalLLMService.isGemmaModelAvailable is false out of the box. Without this, any test that
/// calls the real generation pipeline silently no-ops on its own "model not available" guard
/// instead of actually exercising anything — a false green, not a skip anyone would notice.
///
/// Copies the same .gguf checked into the repo for local dev (mirror/LocalModels/) into the
/// exact Application Support path LocalLLMService.modelDirectory() expects. The iOS Simulator
/// shares the host Mac's filesystem (unlike a real device's sandbox), so reading a
/// source-relative path here is safe and portable across machines that have this repo checked
/// out. Real weights, not a mock.
enum GemmaModelTestSupport {
    @discardableResult
    static func ensureModelInstalled(sourceFile: StaticString = #filePath) -> Bool {
        if LocalLLMService.isGemmaModelAvailable { return true }

        let thisFile = URL(fileURLWithPath: "\(sourceFile)")
        // mirror/mirrorTests/GemmaModelTestSupport.swift -> mirror/ (project root)
        let projectRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
        let devModel = projectRoot
            .appendingPathComponent("mirror", isDirectory: true)
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent(LocalLLMService.modelFileName)
            .appendingPathExtension(LocalLLMService.modelExtension)

        guard FileManager.default.fileExists(atPath: devModel.path),
              let destination = try? LocalLLMService.preferredModelURL()
        else { return false }

        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.copyItem(at: devModel, to: destination)
        }
        return LocalLLMService.isGemmaModelAvailable
    }
}
