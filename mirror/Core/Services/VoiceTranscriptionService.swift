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
            throw InsightError.serviceUnavailable("Speech recognition permission is required for local transcription.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try audioData.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        var lastError: Error?
        let supported = SFSpeechRecognizer.supportedLocales()
        for locale in recognitionLocales where supported.contains(locale) {
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { continue }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.shouldReportPartialResults = false

            do {
                let transcript = try await recognize(request: request, recognizer: recognizer)
                return VoiceTranscription(
                    transcript: transcript,
                    languageCode: locale.identifier,
                    languageName: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier,
                    englishTranslation: transcript
                )
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? InsightError.serviceUnavailable("Speech recognition is not available for the configured languages on this device.")
    }

    private static var recognitionLocales: [Locale] {
        let identifiers = [
            Locale.current.identifier,
            "en-US", "en-IN", "hi-IN", "te-IN", "ta-IN", "bn-IN", "mr-IN", "gu-IN", "kn-IN", "ml-IN",
            "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR", "ru-RU", "ja-JP", "ko-KR", "zh-Hans",
            "ar-SA", "id-ID", "tr-TR", "vi-VN", "th-TH", "nl-NL"
        ]
        var seen = Set<String>()
        return identifiers
            .map(Locale.init(identifier:))
            .filter { seen.insert($0.identifier).inserted }
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
