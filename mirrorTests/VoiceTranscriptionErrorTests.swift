import Testing
@testable import mirror

/// Covers `VoiceTranscriptionError.classify(_:)` (audit 2.4) — the mapping
/// that keeps a raw system error (an opaque `NSError` from
/// `SFSpeechRecognizer`, a `CancellationError`, anything not written for a
/// user to read) from ever reaching the voice-note attachment row.
struct VoiceTranscriptionErrorTests {
    private struct SomeOtherError: Error {}

    @Test func classifyPassesThroughAKnownCase() {
        #expect(VoiceTranscriptionError.classify(VoiceTranscriptionError.noOfflineModelAvailable) == .noOfflineModelAvailable)
        #expect(VoiceTranscriptionError.classify(VoiceTranscriptionError.timedOut) == .timedOut)
        #expect(VoiceTranscriptionError.classify(VoiceTranscriptionError.permissionDenied) == .permissionDenied)
    }

    @Test func classifyCollapsesAnyUnknownErrorToRecognitionFailed() {
        #expect(VoiceTranscriptionError.classify(SomeOtherError()) == .recognitionFailed)
        #expect(VoiceTranscriptionError.classify(CancellationError()) == .recognitionFailed)
    }

    @Test func everyCaseHasADistinctNonEmptyDescription() {
        let cases: [VoiceTranscriptionError] = [.permissionDenied, .noOfflineModelAvailable, .timedOut, .recognitionFailed]
        let descriptions = cases.map { $0.errorDescription ?? "" }
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(Set(descriptions).count == cases.count, "Two failure kinds share the same copy — the attachment row wouldn't actually distinguish them")
    }
}
