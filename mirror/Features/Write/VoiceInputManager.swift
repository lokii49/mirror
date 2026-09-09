import AVFoundation
import Combine
import Foundation
import SwiftUI

@Observable
@MainActor
final class VoiceInputManager: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var elapsed: TimeInterval = 0
    var recordingData: Data?
    var duration: TimeInterval = 0
    var error: String?

    /// Hard cap. A forgotten recording otherwise grows the temp file unbounded
    /// (44.1kHz mono AAC ≈ 0.5 MB/min).
    let maxDuration: TimeInterval = 600

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var observing = false

    var hasRecording: Bool {
        recordingData != nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        guard hasEnoughDiskSpace(for: url) else {
            error = String(localized: "Not enough storage to record.")
            return
        }

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
            recorder.record(forDuration: maxDuration)

            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            isRecording = true
            startObservingSession()
        } catch {
            self.error = error.localizedDescription
            isRecording = false
            deactivateSession()
        }
    }

    func refreshElapsed() {
        guard isRecording, let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= maxDuration { stopRecording() }
    }

    func stopRecording() {
        guard isRecording else { return }
        finishRecording()
    }

    func discardRecording() {
        recorder?.stop()
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
        stopObservingSession()
        deactivateSession()
    }

    private func finishRecording() {
        // currentTime is the length of audio actually captured — read it before
        // stop(), after which it reads 0. Falls back to wall-clock elapsed.
        let recordedTime = recorder?.currentTime ?? 0
        recorder?.stop()
        isRecording = false
        duration = recordedTime > 0 ? recordedTime : elapsed
        recorder = nil
        startedAt = nil
        stopObservingSession()

        if let recordingURL {
            do {
                recordingData = try Data(contentsOf: recordingURL)
            } catch {
                self.error = error.localizedDescription
            }
        }

        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func hasEnoughDiskSpace(for url: URL) -> Bool {
        guard let values = try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true
        }
        return available > 20_000_000 // ~20 MB headroom
    }

    // MARK: - Session interruptions

    private func startObservingSession() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
    }

    private func stopObservingSession() {
        guard observing else { return }
        observing = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor in
            guard self.isRecording else { return }
            self.finishRecording()
            self.error = String(localized: "Recording stopped — interrupted by another app or a call.")
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        Task { @MainActor in
            guard self.isRecording else { return }
            self.finishRecording()
        }
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            // Fired by the maxDuration cap, or an OS stop we didn't initiate.
            if self.isRecording { self.finishRecording() }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.error = error?.localizedDescription ?? String(localized: "Recording failed.")
            self.discardRecording()
        }
    }
}

@Observable
final class VoiceNotePlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var error: String?

    private var player: AVAudioPlayer?

    /// Only one voice note plays at a time. Each attachment row owns its own
    /// player, so without this two could play at once and one's stop() would
    /// deactivate the shared AVAudioSession under the other. weak so a dismissed
    /// view's player isn't retained.
    private static weak var active: VoiceNotePlayer?

    func toggle(data: Data) {
        isPlaying ? stop() : play(data: data)
    }

    func play(data: Data) {
        Self.active?.stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.delegate = self
            player = newPlayer
            newPlayer.play()
            isPlaying = true
            Self.active = self
        } catch {
            self.error = error.localizedDescription
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        if Self.active === self { Self.active = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Without a delegate, isPlaying never returns to false at end of playback and
    // the row's button stays stuck showing "pause".
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.error = error?.localizedDescription
            self.stop()
        }
    }
}

struct VoiceNoteAttachmentView: View {
    let data: Data
    let duration: TimeInterval
    var title: String = String(localized: "Voice note")
    var transcript: String? = nil
    var languageName: String? = nil
    var isTranscribing: Bool = false
    var transcriptionFailed: Bool = false
    var onDelete: (() -> Void)? = nil
    var onRetryTranscription: (() -> Void)? = nil

    @State private var player = VoiceNotePlayer()
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    player.toggle(data: data)
                } label: {
                    ZStack {
                        if displayMode == .sentinel {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(accent)
                                .frame(width: 36, height: 36)
                        } else {
                            Circle()
                                .fill(accent)
                                .frame(width: 38, height: 38)
                        }
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
                            .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .semibold) : .system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let languageName, !languageName.isEmpty {
                            Text("·").foregroundStyle(.quaternary)
                            Group {
                                if displayMode == .sentinel {
                                    Text(languageName.uppercased()).font(MirrorTheme.mono(10, weight: .medium))
                                } else {
                                    Text(languageName).font(.system(size: 11, weight: .medium))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        if isTranscribing {
                            Text("·").foregroundStyle(.quaternary)
                            Group {
                                if displayMode == .sentinel {
                                    Text("DECODING…").font(MirrorTheme.mono(10, weight: .medium))
                                } else {
                                    Text("Transcribing...").font(.system(size: 11, weight: .medium))
                                }
                            }
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
                            .background(
                                Color(.tertiarySystemFill),
                                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) : AnyShape(Circle())
                            )
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
            } else if transcriptionFailed {
                Divider().padding(.horizontal, 14)
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                    Group {
                        if displayMode == .sentinel {
                            Text("DECODE FAILED — AI WON'T READ THIS NOTE.").font(MirrorTheme.mono(10.5, weight: .medium))
                        } else {
                            Text("Transcription failed — AI won't reflect on this note.").font(.system(size: 12))
                        }
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    if let onRetryTranscription {
                        Button(action: onRetryTranscription) {
                            if displayMode == .sentinel {
                                Text("RETRY").font(MirrorTheme.mono(11, weight: .semibold))
                            } else {
                                Text("Retry").font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundStyle(accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: displayMode == .sentinel ? 8 : 16, style: .continuous)
                .fill(accent.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: displayMode == .sentinel ? 8 : 16, style: .continuous)
                        .strokeBorder(accent.opacity(displayMode == .sentinel ? 0.30 : 0.15), lineWidth: 1)
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
                    .fill(accent.opacity(0.4 + h * 0.45))
                    .frame(width: 2, height: 22 * h + 3)
            }
        }
    }
}

/// Live recording state, shown inline where the finished voice note will land —
/// the editor keeps its keyboard and caret the whole time (no modal sheet).
struct InlineRecordingRow: View {
    var elapsed: TimeInterval
    var onStop: () -> Void
    var onCancel: () -> Void

    @Environment(\.appDisplayMode) private var displayMode
    private let waveHeights: [CGFloat] = [0.35, 0.7, 1.0, 0.55, 0.85, 0.45, 0.75, 0.6, 0.9, 0.4, 0.65, 0.8]
    private var corner: CGFloat { displayMode == .sentinel ? 8 : 16 }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel recording")

            TimelineView(.animation) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 8)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<14, id: \.self) { i in
                        let h = waveHeights[(i + tick) % waveHeights.count]
                        Capsule()
                            .fill(Color.red.opacity(0.5 + h * 0.4))
                            .frame(width: 2.5, height: 6 + h * 20)
                    }
                }
            }
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)

            Text(formatDuration(elapsed))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.red)

            Button(action: onStop) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 12, height: 12)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop and add recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.red.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.22), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording")
        .accessibilityValue(formatDuration(elapsed))
    }
}

struct MicPermissionNotice: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
            Text("Microphone access is off — turn it on in Settings › Privacy › Microphone.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func formatDuration(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
