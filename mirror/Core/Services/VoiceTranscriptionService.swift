import Foundation
import NaturalLanguage
import Speech

struct VoiceTranscription: Codable {
    let transcript: String
    let languageCode: String
    let languageName: String
    let englishTranslation: String
}

enum VoiceTranscriptionService {
    /// - Parameter preferredLocaleId: locale identifier from user settings (e.g. "te-IN"). nil = auto-detect order.
    static func transcribe(audioData: Data, preferredLocaleId: String? = nil) async throws -> VoiceTranscription {
        let authStatus = await requestAuthorization()
        guard authStatus == .authorized else {
            throw InsightError.serviceUnavailable("Speech recognition permission is required for local transcription.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try audioData.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let preferred: Locale? = preferredLocaleId.flatMap {
            $0.isEmpty ? nil : Locale(identifier: $0)
        }

        var lastError: Error?
        let supported = SFSpeechRecognizer.supportedLocales()

        for locale in localeList(preferred: preferred) where supported.contains(locale) {
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { continue }

            guard recognizer.supportsOnDeviceRecognition else { continue }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false

            do {
                let transcript = try await recognize(request: request, recognizer: recognizer)

                // Skip NL validation when the user explicitly chose this locale.
                let isUserPreferred = preferred.map { $0.identifier == locale.identifier } ?? false
                if !isUserPreferred && transcript.count >= 20 {
                    let nlDetected = detectLanguage(in: transcript)
                    let localeLanguage = locale.language.languageCode?.identifier ?? ""
                    if !localeLanguage.isEmpty, let detected = nlDetected, detected != localeLanguage {
                        continue
                    }
                }

                let langName = Locale.current.localizedString(forIdentifier: locale.identifier)
                    ?? locale.localizedString(forIdentifier: locale.identifier)
                    ?? locale.identifier
                return VoiceTranscription(
                    transcript: transcript,
                    languageCode: locale.identifier,
                    languageName: langName,
                    englishTranslation: transcript
                )
            } catch {
                // User explicitly picked this locale — don't silently fall back to another language.
                if let preferred, preferred.identifier == locale.identifier {
                    throw error
                }
                lastError = error
                continue
            }
        }

        throw lastError ?? InsightError.serviceUnavailable("Speech recognition is not available for the configured languages on this device.")
    }

    private static func detectLanguage(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    // If user picked a language, it goes first; indic block precedes English to prevent
    // en-US recognizer from winning on Indian-script audio via Latin phonetics.
    private static func localeList(preferred: Locale?) -> [Locale] {
        let indic = ["hi-IN", "te-IN", "ta-IN", "bn-IN", "mr-IN", "gu-IN", "kn-IN", "ml-IN"]
        let rest = [
            "en-IN", "en-US",
            "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR", "ru-RU",
            "ja-JP", "ko-KR", "zh-Hans", "ar-SA", "id-ID", "tr-TR", "vi-VN", "th-TH", "nl-NL"
        ]
        let identifiers = Locale.preferredLanguages + indic + rest
        var seen = Set<String>()
        var locales = identifiers
            .map(Locale.init(identifier:))
            .filter { seen.insert($0.identifier).inserted }

        if let preferred {
            locales.removeAll { $0.identifier == preferred.identifier }
            locales.insert(preferred, at: 0)
        }
        return locales
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

    // MARK: - Supported languages for the Settings picker

    struct SupportedLanguage: Identifiable {
        let id: String        // locale identifier, "" = automatic

        // System-provided, in the app's current UI language — correct for free,
        // no translation upkeep needed for 25 language names across 10 locales.
        var displayName: String {
            id.isEmpty ? String(localized: "Automatic") : (Locale.current.localizedString(forIdentifier: id) ?? id)
        }
    }

    static let pickerLanguages: [SupportedLanguage] = {
        let ids = [
            "", "te-IN", "hi-IN", "ta-IN", "kn-IN", "ml-IN", "mr-IN", "gu-IN", "bn-IN",
            "en-IN", "en-US", "es-ES", "es-MX", "fr-FR", "de-DE", "it-IT", "pt-BR",
            "ru-RU", "ja-JP", "ko-KR", "zh-Hans", "ar-SA", "id-ID", "tr-TR", "vi-VN", "nl-NL",
        ]
        return ids.map { SupportedLanguage(id: $0) }
    }()
}
