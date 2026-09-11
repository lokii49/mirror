import Foundation
import NaturalLanguage
@preconcurrency import Speech

struct VoiceTranscription: Codable {
    let transcript: String
    let languageCode: String
    let languageName: String
    let englishTranslation: String
}

/// Distinguishes *why* a transcription failed (audit 2.4) — previously every
/// failure threw `InsightError.serviceUnavailable(String)`, but
/// `InsightError.errorDescription` ignores that associated string and always
/// returns its own generic, Insight-flavored copy ("...Mirror will try again
/// tonight while your phone charges" — meaningless for voice), and nothing
/// downstream ever unwrapped the enum to read the string directly either. So
/// every distinct failure reason was already being discarded twice over
/// before this: once by `InsightError`'s fixed copy, once more by
/// `WriteView+VoiceNotes.swift`'s catch block, which only ever set a `Bool`.
enum VoiceTranscriptionError: LocalizedError, Equatable {
    case permissionDenied
    /// No candidate locale both had a downloaded on-device model and passed
    /// the NL-language re-validation — as distinct from a model being present
    /// and recognition actually failing on it.
    case noOfflineModelAvailable
    case timedOut
    /// Catch-all: a real recognition attempt failed for a reason not worth
    /// distinguishing further (garbled audio, silence, decoder error, a
    /// cancellation that isn't the timeout case). Also what any error *not*
    /// one of this enum's cases collapses to via `classify(_:)` — this app
    /// never surfaces a raw system error string to the user.
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "Speech recognition permission is required for local transcription.")
        case .noOfflineModelAvailable:
            return String(localized: "This language isn't available for offline transcription on this device.")
        case .timedOut:
            return String(localized: "Transcription took too long and was stopped.")
        case .recognitionFailed:
            return String(localized: "Transcription failed.")
        }
    }

    /// Maps any thrown error to a display-safe reason — used at the UI
    /// boundary so a raw `NSError` from `SFSpeechRecognizer` (opaque codes,
    /// not written for a user to read) never reaches the attachment row.
    static func classify(_ error: Error) -> VoiceTranscriptionError {
        (error as? VoiceTranscriptionError) ?? .recognitionFailed
    }
}

/// Minimal async semaphore — serializes speech recognition (see `gate` below).
private actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { permits = value }

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            permits += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum VoiceTranscriptionService {
    /// One recognition at a time. `SFSpeechRecognizer` on-device recognition is
    /// effectively single-slot — two concurrent requests (e.g. recording two
    /// voice notes back to back) make one fail. Callers queue behind this.
    private static let gate = AsyncSemaphore(value: 1)

    /// Caps how many locales actually get a recognition pass per call — see
    /// the comment at the call site (audit 2.4).
    private static let maxLocalesAttempted = 6

    /// - Parameter preferredLocaleId: locale identifier from user settings (e.g. "te-IN"). nil = auto-detect order.
    static func transcribe(audioData: Data, preferredLocaleId: String? = nil) async throws -> VoiceTranscription {
        await gate.wait()
        defer { Task { await gate.signal() } }

        let authStatus = await requestAuthorization()
        guard authStatus == .authorized else {
            throw VoiceTranscriptionError.permissionDenied
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
        var attemptedPasses = 0
        // A locale that decoded fine but got rejected by the NL re-validation
        // below means the model that ran wasn't the right language — tracked
        // separately from lastError because it isn't a caught exception, and
        // because it's the more accurate classification than whatever
        // (possibly stale, possibly unrelated) error an earlier locale threw.
        var nlRejectedAny = false
        let supported = SFSpeechRecognizer.supportedLocales()

        for locale in localeList(preferred: preferred) where supported.contains(locale) {
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { continue }

            guard recognizer.supportsOnDeviceRecognition else { continue }
            // Bounds worst-case latency. localeList() can offer ~28 candidates,
            // but only ones with a downloaded on-device model reach this point
            // (`supportsOnDeviceRecognition`) — in practice a device carries a
            // handful, so this was already bounded, just not by anything
            // explicit. Six passes (~4.5min worst case at the 45s/pass timeout)
            // is a real, stated ceiling instead of "whatever the device happens
            // to have downloaded."
            guard attemptedPasses < Self.maxLocalesAttempted else { break }
            attemptedPasses += 1
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false

            do {
                let transcript = try await withTimeout(seconds: 45) {
                    try await recognize(request: request, recognizer: recognizer)
                }

                // Skip NL validation when the user explicitly chose this locale.
                let isUserPreferred = preferred.map { $0.identifier == locale.identifier } ?? false
                if !isUserPreferred && transcript.count >= 20 {
                    let nlDetected = detectLanguage(in: transcript)
                    let localeLanguage = locale.language.languageCode?.identifier ?? ""
                    if !localeLanguage.isEmpty, let detected = nlDetected, detected != localeLanguage {
                        nlRejectedAny = true
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
                    throw VoiceTranscriptionError.classify(error)
                }
                if error is CancellationError { throw error }
                lastError = error
                continue
            }
        }

        // Prefer "no offline model" over whatever lastError happens to hold:
        // if every attempted pass either decoded-but-got-language-rejected or
        // was skipped for no downloaded model, "recognition failed" would be
        // actively misleading — recognition didn't fail, the right language
        // model just wasn't available. This also avoids surfacing a stale
        // lastError from an earlier locale that timed out when a later one
        // actually finished (just in the wrong language).
        if nlRejectedAny {
            throw VoiceTranscriptionError.noOfflineModelAvailable
        }
        if let lastError {
            throw VoiceTranscriptionError.classify(lastError)
        }
        // Every candidate locale was skipped (no downloaded on-device model, or
        // not `.isAvailable`) — no recognition pass ever ran, as distinct from
        // one running and failing.
        throw attemptedPasses > 0 ? VoiceTranscriptionError.recognitionFailed : VoiceTranscriptionError.noOfflineModelAvailable
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

    /// Guards the continuation against the recognition callback firing more than
    /// once (error then a late final result, etc.) and holds the task so a
    /// cancellation or timeout can stop it.
    private final class RecognitionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        nonisolated(unsafe) var task: SFSpeechRecognitionTask?

        /// Returns true exactly once — the caller that gets true owns the resume.
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if resumed { return false }
            resumed = true
            return true
        }
    }

    private static func recognize(
        request: SFSpeechURLRecognitionRequest,
        recognizer: SFSpeechRecognizer
    ) async throws -> String {
        let box = RecognitionBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        if box.claim() {
                            box.task?.cancel()
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let result, result.isFinal else { return }
                    let transcript = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if box.claim() {
                        box.task?.finish()
                        if transcript.isEmpty {
                            continuation.resume(throwing: InsightError.emptyResponse)
                        } else {
                            continuation.resume(returning: transcript)
                        }
                    }
                }
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// Bounds a recognition pass. Without this, a wedged SFSpeechRecognitionTask
    /// that never delivers a final result or an error hangs the continuation
    /// forever — and the Write screen's save button stays disabled the whole
    /// time (`isTranscribingVoiceNotes`). On timeout the loop moves to the next
    /// locale, or the call surfaces as a failed transcription with a Retry.
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw VoiceTranscriptionError.timedOut
            }
            guard let result = try await group.next() else {
                throw VoiceTranscriptionError.timedOut
            }
            group.cancelAll()
            return result
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
