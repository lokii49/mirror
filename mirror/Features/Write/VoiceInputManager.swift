import AVFoundation
import Combine
import Foundation
import SwiftUI

@Observable
final class VoiceInputManager: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var elapsed: TimeInterval = 0
    var recordingData: Data?
    var duration: TimeInterval = 0
    var error: String?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?

    var hasRecording: Bool {
        recordingData != nil
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() {
        guard !isRecording else { return }
        error = nil
        recordingData = nil
        duration = 0
        elapsed = 0

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()

            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            isRecording = true
        } catch {
            self.error = error.localizedDescription
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func refreshElapsed() {
        guard isRecording, let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    func stopRecording() {
        guard isRecording else { return }
        recorder?.stop()
        finishRecording()
    }

    func discardRecording() {
        if isRecording {
            recorder?.stop()
        }
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recorder = nil
        recordingURL = nil
        recordingData = nil
        duration = 0
        elapsed = 0
        startedAt = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishRecording() {
        isRecording = false
        duration = max(elapsed, recorder?.currentTime ?? 0)
        recorder = nil
        startedAt = nil

        if let recordingURL {
            do {
                recordingData = try Data(contentsOf: recordingURL)
            } catch {
                self.error = error.localizedDescription
            }
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@Observable
final class VoiceNotePlayer {
    var isPlaying = false
    var error: String?

    private var player: AVAudioPlayer?

    func toggle(data: Data) {
        isPlaying ? stop() : play(data: data)
    }

    func play(data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data)
            player?.play()
            isPlaying = true
        } catch {
            self.error = error.localizedDescription
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct VoiceNoteAttachmentView: View {
    let data: Data
    let duration: TimeInterval
    var title: String = "Voice note"
    var transcript: String? = nil
    var languageName: String? = nil
    var isTranscribing: Bool = false
    var onDelete: (() -> Void)? = nil

    @State private var player = VoiceNotePlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    player.toggle(data: data)
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 6) {
                        Text(formatDuration(duration))
                        if let languageName, !languageName.isEmpty {
                            Text("·")
                            Text(languageName)
                        }
                        if isTranscribing {
                            Text("·")
                            Text("Transcribing")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let onDelete {
                    Button {
                        player.stop()
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete voice note")
                }
            }

            if let transcript,
               !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .futureSurface(cornerRadius: 14)
        .onDisappear { player.stop() }
    }
}

struct VoiceInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (Data, TimeInterval) -> Void

    @State private var manager = VoiceInputManager()
    @State private var permissionDenied = false
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(manager.isRecording ? Color.red.opacity(0.14) : Color(.secondarySystemBackground))
                        .frame(width: 132, height: 132)

                    Circle()
                        .stroke(manager.isRecording ? Color.red.opacity(0.35) : Color.clear, lineWidth: 10)
                        .frame(width: 132, height: 132)
                        .scaleEffect(manager.isRecording ? 1.08 : 1)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: manager.isRecording)

                    Image(systemName: manager.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(manager.isRecording ? .red : .secondary)
                }

                VStack(spacing: 6) {
                    Text(manager.isRecording ? "Recording" : manager.hasRecording ? "Voice note ready" : "Tap to record")
                        .font(.system(size: 18, weight: .semibold))

                    Text(formatDuration(manager.isRecording ? manager.elapsed : manager.duration))
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if let data = manager.recordingData {
                    VoiceNoteAttachmentView(data: data, duration: manager.duration)
                        .padding(.horizontal, 32)
                }

                if let err = manager.error {
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if permissionDenied {
                    Text("Microphone permission is required to record a voice note.")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    if manager.isRecording {
                        manager.stopRecording()
                    } else {
                        manager.startRecording()
                    }
                } label: {
                    Text(manager.isRecording ? "Stop Recording" : manager.hasRecording ? "Record Again" : "Start Recording")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.isRecording ? .red : .accentColor)
                .padding(.horizontal, 32)
                .disabled(permissionDenied)

                Spacer()
            }
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        manager.discardRecording()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        manager.stopRecording()
                        if let data = manager.recordingData {
                            onComplete(data, manager.duration)
                        }
                        dismiss()
                    }
                    .disabled(manager.recordingData == nil)
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .task {
            let granted = await manager.requestPermission()
            if !granted { permissionDenied = true }
        }
        .onReceive(timer) { _ in manager.refreshElapsed() }
        .onDisappear {
            if manager.isRecording {
                manager.stopRecording()
            }
        }
    }
}

func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
