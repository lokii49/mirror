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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    player.toggle(data: data)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 38, height: 38)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    waveformBars
                        .frame(height: 22)
                    HStack(spacing: 5) {
                        Text(formatDuration(duration))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let languageName, !languageName.isEmpty {
                            Text("·").foregroundStyle(.quaternary)
                            Text(languageName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if isTranscribing {
                            Text("·").foregroundStyle(.quaternary)
                            Text("Transcribing...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onDelete {
                    Button {
                        player.stop()
                        onDelete()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete voice note")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().padding(.horizontal, 14)
                Text(transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                }
        }
        .onDisappear { player.stop() }
    }

    private var waveformBars: some View {
        let seed = abs(data.count)
        let heights: [CGFloat] = [0.4, 0.85, 0.55, 1.0, 0.65, 0.45, 0.9, 0.6, 0.75, 0.35, 0.8, 0.5]
        let count = 22
        return HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<count, id: \.self) { i in
                let h = heights[(i * 5 + seed) % heights.count]
                Capsule()
                    .fill(Color.accentColor.opacity(0.4 + h * 0.45))
                    .frame(width: 2, height: 22 * h + 3)
            }
        }
    }
}

struct VoiceInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (Data, TimeInterval) -> Void

    @State private var manager = VoiceInputManager()
    @State private var permissionDenied = false
    @State private var waveformTick = 0
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    private let waveHeights: [CGFloat] = [0.35, 0.7, 1.0, 0.55, 0.85, 0.45, 0.75, 0.6, 0.9, 0.4, 0.65, 0.8]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 48)

                ZStack {
                    if manager.isRecording {
                        liveWaveform
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(.quaternary)
                    }
                }
                .frame(height: 52)
                .animation(.spring(duration: 0.3), value: manager.isRecording)

                Spacer(minLength: 20)

                Text(formatDuration(manager.isRecording ? manager.elapsed : manager.duration))
                    .font(.system(size: 56, weight: .thin, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(
                        manager.isRecording ? .primary
                            : manager.hasRecording ? Color.primary.opacity(0.75)
                            : Color(.quaternaryLabel)
                    )
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: manager.elapsed)

                Spacer(minLength: 36)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if manager.isRecording {
                        manager.stopRecording()
                    } else if manager.hasRecording {
                        manager.discardRecording()
                        manager.startRecording()
                    } else {
                        manager.startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(manager.isRecording ? Color.red.opacity(0.2) : Color.clear, lineWidth: 16)
                            .frame(width: 104, height: 104)
                            .scaleEffect(manager.isRecording ? 1.1 : 1)
                            .animation(
                                manager.isRecording
                                    ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
                                    : .spring(duration: 0.3),
                                value: manager.isRecording
                            )

                        Circle()
                            .fill(manager.isRecording ? Color.red : Color(.secondarySystemBackground))
                            .frame(width: 80, height: 80)
                            .shadow(color: manager.isRecording ? .red.opacity(0.28) : .clear, radius: 14, y: 5)

                        if manager.isRecording {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(permissionDenied)

                Text(statusLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)

                Spacer(minLength: 28)

                if let data = manager.recordingData, !manager.isRecording {
                    VStack(spacing: 12) {
                        VoiceNoteAttachmentView(data: data, duration: manager.duration)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            manager.discardRecording()
                        } label: {
                            Label("Discard", systemImage: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let err = manager.error {
                    Text(err)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if permissionDenied {
                    VStack(spacing: 10) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(.red.opacity(0.6))
                        Text("Microphone access required.\nGo to Settings → Privacy → Microphone.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                }

                Spacer(minLength: 36)
            }
            .animation(.spring(duration: 0.4), value: manager.hasRecording)
            .animation(.spring(duration: 0.35), value: manager.isRecording)
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
                        if manager.isRecording { manager.stopRecording() }
                        if let data = manager.recordingData {
                            onComplete(data, manager.duration)
                        }
                        dismiss()
                    }
                    .disabled(!manager.hasRecording && !manager.isRecording)
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .task {
            let granted = await manager.requestPermission()
            if !granted { permissionDenied = true }
        }
        .onReceive(timer) { _ in
            manager.refreshElapsed()
            if manager.isRecording { waveformTick += 1 }
        }
        .onDisappear {
            if manager.isRecording { manager.stopRecording() }
        }
    }

    private var statusLabel: String {
        if permissionDenied { return "No microphone access" }
        if manager.isRecording { return "Tap to stop" }
        if manager.hasRecording { return "Tap to re-record" }
        return "Tap to record"
    }

    private var liveWaveform: some View {
        let count = 13
        return HStack(alignment: .center, spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                let h = waveHeights[(i + waveformTick) % waveHeights.count]
                Capsule()
                    .fill(Color.red.opacity(0.55 + h * 0.35))
                    .frame(width: 3, height: 52 * h + 6)
                    .animation(.easeInOut(duration: 0.15), value: waveformTick)
            }
        }
    }
}

func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
