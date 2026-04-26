import Foundation
import Speech

#if os(iOS)
import AVFoundation
#endif

@Observable
final class VoiceInputManager: NSObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case error(String)
    }

    var state: State = .idle
    var transcript: String = ""

    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)

    #if os(iOS)
    private var audioEngine: AVAudioEngine?
    #endif

    // MARK: - Public API

    func start() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            startRecording()
        case .notDetermined:
            state = .requestingPermission
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        self?.startRecording()
                    } else {
                        self?.state = .error("Speech recognition not authorized.")
                    }
                }
            }
        case .denied, .restricted:
            state = .error("Speech recognition denied. Enable in Settings → Privacy.")
        @unknown default:
            state = .error("Speech recognition unavailable.")
        }
    }

    func stop(completion: @escaping (String) -> Void) {
        let result = transcript
        teardown()
        completion(result)
    }

    func cancel() {
        teardown()
    }

    // MARK: - Private

    private func teardown() {
        #if os(iOS)
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        #endif
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        transcript = ""
        state = .idle
    }

    private func startRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Speech recognizer unavailable.")
            return
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Audio session failed.")
            return
        }

        let engine = AVAudioEngine()
        audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    if self.state == .recording { self.state = .idle }
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            state = .recording
        } catch {
            state = .error("Could not start audio engine.")
            teardown()
        }
        #else
        state = .error("Voice input not available on this platform.")
        #endif
    }
}
