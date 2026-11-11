import AVFoundation
import Foundation

/// Records one voice note on the watch, the same format as the iPhone's recorder (AAC, 44.1 kHz,
/// mono) so the phone stores and transcribes it like its own. The audio stays in the watch's
/// temporary folder until it's sent (then `WatchSender` owns it) or thrown away.
@MainActor
@Observable
final class WatchRecorder: NSObject {
    enum State: Equatable {
        case idle
        case recording
        case recorded
        case playing
        case denied
        case failed
    }

    /// The longest note: a wrist isn't where long recordings happen, and the transfer stays small.
    static let maxDuration: TimeInterval = 300

    private(set) var state: State = .idle
    /// The clock on screen: recording time, then playback position while playing.
    private(set) var elapsed: TimeInterval = 0
    /// The finished note's length (what's sent).
    private(set) var duration: TimeInterval = 0
    /// Recent input levels, 0…1, newest last (the live bars).
    private(set) var levels: [Double] = Array(repeating: 0, count: 12)
    private(set) var fileURL: URL?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var interruptionObserver: NSObjectProtocol?

    /// Asks for the microphone if needed, then records into a fresh temporary file.
    func start() async {
        guard state == .idle || state == .failed else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-note-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true, options: [])
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record(forDuration: Self.maxDuration) else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            fileURL = url
            elapsed = 0
            state = .recording
            startTicker()
            observeInterruptions()
        } catch {
            try? FileManager.default.removeItem(at: url)
            state = .failed
        }
    }

    /// Ends the recording; the note is kept for review.
    func stop() {
        guard state == .recording, let recorder else { return }
        elapsed = recorder.currentTime
        recorder.stop()
        finishRecording()
    }

    func togglePlayback() {
        if state == .playing {
            player?.stop()
            player = nil
            stopTicker()
            elapsed = duration
            state = .recorded
            return
        }
        guard state == .recorded, let fileURL, let player = try? AVAudioPlayer(contentsOf: fileURL) else { return }
        player.delegate = self
        player.play()
        self.player = player
        state = .playing
        startTicker()
    }

    /// The recorded file and its length, handed over for sending (the caller now owns the file).
    func takeRecording() -> (url: URL, duration: TimeInterval)? {
        player?.stop()
        player = nil
        stopTicker()
        guard state == .recorded || state == .playing, let fileURL else { return nil }
        self.fileURL = nil
        state = .idle
        deactivateSession()
        return (fileURL, duration)
    }

    /// Stops anything running and deletes the audio (✕, or leaving the screen without sending).
    func discard() {
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        stopTicker()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        elapsed = 0
        duration = 0
        levels = Array(repeating: 0, count: levels.count)
        state = .idle
        deactivateSession()
    }

    // MARK: - Private

    /// A call, an alarm or Siri takes the microphone: the recording pauses and wouldn't resume,
    /// so it ends there and what was recorded is kept for review, as if Stop were tapped.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.state == .recording { self.stop() }
                else if self.state == .playing { self.togglePlayback() }
            }
        }
    }

    private func stopObservingInterruptions() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
    }

    private func finishRecording() {
        recorder = nil
        stopTicker()
        levels = Array(repeating: 0, count: levels.count)
        // A tap that stopped before any audio was written leaves nothing worth sending.
        if elapsed < 0.5 {
            discard()
        } else {
            duration = elapsed
            state = .recorded
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        if let recorder, state == .recording {
            recorder.updateMeters()
            elapsed = recorder.currentTime
            // -50 dB and below reads as silence; 0 dB is the top of the bar.
            let level = max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 50) / 50))
            levels.removeFirst()
            levels.append(level)
        } else if let player, state == .playing {
            elapsed = player.currentTime
        }
    }

    private func deactivateSession() {
        stopObservingInterruptions()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension WatchRecorder: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    /// The 5-minute limit (or an interruption) ended the recording on its own.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let duration = recorder.currentTime
        Task { @MainActor in
            guard self.state == .recording else { return }
            if duration > 0 { self.elapsed = duration }
            if flag { self.finishRecording() } else { self.discard(); self.state = .failed }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.state == .playing else { return }
            self.player = nil
            self.stopTicker()
            self.elapsed = self.duration
            self.state = .recorded
        }
    }
}
