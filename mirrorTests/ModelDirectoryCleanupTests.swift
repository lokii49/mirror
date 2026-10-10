import Testing
import Foundation
@testable import mirror

/// The model directory holds both Gemma and Ask's search model; cleaning up an old Gemma file
/// must never delete the search model (3.1.0 did, on every launch).
struct ModelDirectoryCleanupTests {
    @Test func cleanupKeepsGemmaAndTheSearchModelAndRemovesTheRest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("model-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gemma = "current-gemma.gguf"
        for name in [gemma, SemanticSearchService.modelFileName, "old-gemma.gguf"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }

        ModelDownloadManager.removeStaleModelFiles(keeping: gemma, in: directory)

        let left = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(left == [gemma, SemanticSearchService.modelFileName])
    }
}
