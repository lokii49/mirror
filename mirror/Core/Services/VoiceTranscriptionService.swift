import Foundation
import Speech

struct VoiceTranscription: Codable {
    let transcript: String
    let languageCode: String
    let languageName: String
    let englishTranslation: String
}

enum VoiceTranscriptionService {
    static func transcribe(audioData: Data, token: String) async throws -> VoiceTranscription {
        let authStatus = await requestAuthorization()
        guard authStatus == .authorized else {
            throw InsightError.localModelUnavailable("Speech recognition permission is required for local transcription.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            throw InsightError.localModelUnavailable("On-device speech recognition is not available for the current locale.")
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw InsightError.localModelUnavailable("This device or language does not support offline speech recognition.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try audioData.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let transcript = try await recognize(request: request, recognizer: recognizer)
        return VoiceTranscription(
            transcript: transcript,
            languageCode: Locale.current.language.languageCode?.identifier ?? "und",
            languageName: Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "Current language",
            englishTranslation: transcript
        )
    }

    private static func recognize(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    didResume = true
                    task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal, !didResume else { return }
                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didResume = true
                task?.finish()
                if transcript.isEmpty {
                    continuation.resume(throwing: InsightError.emptyResponse)
                } else {
                    continuation.resume(returning: transcript)
                }
            }
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
