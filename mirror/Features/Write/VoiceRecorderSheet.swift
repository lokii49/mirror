#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// Records a voice note in segments, so it can pause, play back what it has so far, and resume, as
/// the recorder Notes opens from Record Audio does. AAC files can't be read until their recorder
/// stops, so each pause stops the current segment and merges everything recorded into one file;
/// playback and the final note use that file.
@Observable
@MainActor
final class SegmentedVoiceRecorder: NSObject {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle
    /// Seconds recorded across every segment, including the one in progress.
    private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, 0...1, one per `levelInterval`, newest last.
    private(set) var levels: [CGFloat] = []
    private(set) var isPlaying = false
    private(set) var playbackTime: TimeInterval = 0
    private(set) var isMerging = false
    var error: String?

    let levelInterval: TimeInterval = 0.05
    /// Same cap as the inline recorder: a forgotten recording otherwise grows without limit.
    let maxDuration: TimeInterval = SegmentedVoiceRecorder.configuredMaxDuration

    /// 600 seconds. Debug builds take `--voiceMaxSeconds=N` as a launch argument, so the cap's
    /// auto-stop can be tried on a device without recording for ten minutes.
    private static var configuredMaxDuration: TimeInterval {
        #if DEBUG
        let prefix = "--voiceMaxSeconds="
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
           let seconds = TimeInterval(argument.dropFirst(prefix.count)), seconds > 0 {
            return seconds
        }
        #endif
        return 600
    }

    private var recorder: AVAudioRecorder?
    private var segmentURL: URL?
    /// Everything recorded before the current segment, merged into one file.
    private var mergedURL: URL?
    private var mergedDuration: TimeInterval = 0
    /// The current segment's length as last read while it was recording. `currentTime` reads 0
    /// once the recorder stops, which it does by itself at the cap (`record(forDuration:)`) or on
    /// an interruption; the segment is still on disk then and is kept.
    private var segmentElapsed: TimeInterval = 0
    /// Set by `discard()`, so a merge still running then throws its file away.
    private var isDiscarded = false
    private var player: AVAudioPlayer?
    private var timer: Timer?

    var hasAudio: Bool { mergedURL != nil || state == .recording }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func record() {
        guard state != .recording else { return }
        stopPlayback()
        // Less than a second left: the cap's auto-stop lands a hair short of it, so this would
        // otherwise start a segment that stops again at once.
        guard maxDuration - mergedDuration >= 1 else { return }
        if state == .idle { isDiscarded = false }
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
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record(forDuration: maxDuration - mergedDuration) else {
                self.error = String(localized: "Recording failed.")
                try? FileManager.default.removeItem(at: url)
                return
            }
            error = nil
            self.recorder = recorder
            segmentURL = url
            segmentElapsed = 0
            state = .recording
            startTimer()
            NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)),
                                                   name: AVAudioSession.interruptionNotification, object: nil)
        } catch {
            self.error = error.localizedDescription
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Stops the current segment and merges it in, so it can be played back.
    func pause() async {
        guard state == .recording, let recorder, let segmentURL else { return }
        let segmentDuration = recorder.isRecording ? max(recorder.currentTime, segmentElapsed) : segmentElapsed
        recorder.stop()
        self.recorder = nil
        self.segmentURL = nil
        segmentElapsed = 0
        stopTimer()
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        state = .paused
        guard segmentDuration > 0 else {
            try? FileManager.default.removeItem(at: segmentURL)
            elapsed = mergedDuration
            return
        }
        isMerging = true
        defer { isMerging = false }
        if let previous = mergedURL {
            do {
                let merged = try await Self.concatenate([previous, segmentURL])
                // Deleted while merging: discard() removed the earlier audio; drop this segment and the merge.
                guard !isDiscarded else {
                    try? FileManager.default.removeItem(at: merged)
                    try? FileManager.default.removeItem(at: segmentURL)
                    return
                }
                try? FileManager.default.removeItem(at: previous)
                try? FileManager.default.removeItem(at: segmentURL)
                mergedURL = merged
            } catch {
                try? FileManager.default.removeItem(at: segmentURL)
                guard !isDiscarded else { return }
                self.error = error.localizedDescription
                elapsed = mergedDuration
                return
            }
        } else {
            mergedURL = segmentURL
        }
        mergedDuration += segmentDuration
        elapsed = mergedDuration
        playbackTime = mergedDuration
    }

    /// The finished note, or nil when nothing was recorded.
    func finish() async -> (data: Data, duration: TimeInterval)? {
        if state == .recording { await pause() }
        stopPlayback()
        defer { cleanUp() }
        guard let mergedURL, mergedDuration >= 0.5, let data = try? Data(contentsOf: mergedURL) else { return nil }
        return (data, mergedDuration)
    }

    func discard() {
        isDiscarded = true
        recorder?.stop()
        recorder = nil
        if let segmentURL { try? FileManager.default.removeItem(at: segmentURL) }
        segmentURL = nil
        stopTimer()
        stopPlayback()
        cleanUp()
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? stopPlayback(keepPosition: true) : play()
    }

    func skip(by seconds: TimeInterval) {
        let target = min(max(0, playbackTime + seconds), mergedDuration)
        playbackTime = target
        player?.currentTime = target
    }

    private func play() {
        guard state == .paused, let mergedURL else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: mergedURL)
            if playbackTime >= mergedDuration - 0.05 { playbackTime = 0 }
            player.currentTime = playbackTime
            player.play()
            self.player = player
            isPlaying = true
            startTimer()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stopPlayback(keepPosition: Bool = false) {
        guard player != nil else { return }
        if keepPosition, let player { playbackTime = player.currentTime } else { playbackTime = mergedDuration }
        player?.stop()
        player = nil
        isPlaying = false
        if state != .recording { stopTimer() }
    }

    // MARK: Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: levelInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if state == .recording, let recorder {
            // Stopped by itself (the cap, or an interruption): keep what it recorded, as a pause does.
            guard recorder.isRecording else {
                elapsed = mergedDuration + segmentElapsed
                Task { await pause() }
                return
            }
            segmentElapsed = recorder.currentTime
            recorder.updateMeters()
            // -50 dB and below reads as silence; 0 dB is full scale.
            let power = CGFloat(recorder.averagePower(forChannel: 0))
            levels.append(max(0.04, min(1, (power + 50) / 50)))
            if levels.count > 600 { levels.removeFirst(levels.count - 600) }
            elapsed = mergedDuration + segmentElapsed
            if elapsed >= maxDuration { Task { await pause() } }
        } else if let player {
            playbackTime = player.currentTime
            if !player.isPlaying { stopPlayback() }
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor in await self.pause() }
    }

    private func cleanUp() {
        if let mergedURL { try? FileManager.default.removeItem(at: mergedURL) }
        mergedURL = nil
        mergedDuration = 0
        elapsed = 0
        levels = []
        playbackTime = 0
        state = .idle
        NotificationCenter.default.removeObserver(self)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func concatenate(_ urls: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
            cursor = cursor + duration
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        if #available(iOS 18, *) {
            try await export.export(to: output, as: .m4a)
        } else {
            export.outputURL = output
            export.outputFileType = .m4a
            await export.export()
            if let error = export.error { throw error }
        }
        return output
    }
}

/// The sheet Record Audio opens, laid out like the recorder in Notes and Voice Memos: title and
/// date, a live waveform under a playhead, a large timer, playback controls for what has been
/// recorded so far, and the red record / pause button. ✓ adds the recording as a voice note.
struct VoiceRecorderSheet: View {
    var onSave: (Data, TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.openURL) private var openURL
    @State private var recorder = SegmentedVoiceRecorder()
    @State private var startedAt = Date()
    @State private var permissionDenied = false
    @State private var isSaving = false

    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : Color.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            header
            titleBlock.padding(.top, 20)
            waveform.padding(.top, 36)
            Spacer(minLength: 24)
            Text(Self.preciseTime(recorder.state == .paused ? recorder.playbackTime : recorder.elapsed))
                .font(.system(size: 56, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.primary)
                .accessibilityLabel(Text(formatDuration(recorder.elapsed)))
            if permissionDenied {
                permissionNotice.padding(.top, 12)
            } else if let error = recorder.error {
                Text(error).font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
            }
            playbackControls.padding(.top, 28)
            recordButton.padding(.top, 28).padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(isSentinel ? MirrorTheme.inkBase : Color(.systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(recorder.hasAudio)
        .onDisappear { if !isSaving { recorder.discard() } }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Menu {
                Button(role: .destructive) {
                    recorder.discard()
                    dismiss()
                } label: {
                    Label("Delete Recording", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .scaledFont(18, weight: .semibold)
                    .foregroundStyle(Color.primary)
                    .frame(width: 48, height: 48)
                    .recorderCircle(isSentinel: isSentinel, fill: nil)
            }
            // A merge in progress still writes a file; deleting under it orphaned that file.
            .disabled(recorder.isMerging || isSaving)
            .accessibilityLabel("More")
            .accessibilityIdentifier("recorderMore")
            Spacer()
            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
                    .scaledFont(20, weight: .semibold)
                    .foregroundStyle(recorder.hasAudio ? Color.white : Color.secondary)
                    .frame(width: 48, height: 48)
                    .recorderCircle(isSentinel: isSentinel, fill: recorder.hasAudio ? accent : nil)
            }
            .disabled(isSaving || recorder.isMerging)
            .accessibilityLabel("Done")
            .accessibilityIdentifier("recorderDone")
        }
        .padding(.top, 16)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Group {
                if isSentinel {
                    Text("New Recording").scaledFont(20, weight: .bold, design: .monospaced).textCase(.uppercase)
                } else {
                    Text("New Recording").scaledFont(26, weight: .bold)
                }
            }
            HStack(spacing: 10) {
                Text(Self.dayAndTime(startedAt))
                Text(formatDuration(recorder.elapsed)).monospacedDigit()
            }
            .scaledFont(17, weight: .semibold)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Waveform

    /// Bars scroll left past a fixed playhead, 20 per second; second marks run along the bottom.
    private var waveform: some View {
        let barStep: CGFloat = 5
        let perSecond = CGFloat(1 / recorder.levelInterval) * barStep
        return Canvas { context, size in
            let mid = size.width / 2
            let height = size.height - 26
            var x = mid - barStep
            for level in recorder.levels.reversed() {
                if x < -barStep { break }
                let bar = max(2, level * height)
                let rect = CGRect(x: x, y: (height - bar) / 2, width: 2.5, height: bar)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.25), with: .color(.secondary))
                x -= barStep
            }
            // Second marks: labels every second, ticks every quarter.
            let now = recorder.state == .paused ? recorder.playbackTime : recorder.elapsed
            let firstSecond = Int((now - Double(mid / perSecond)).rounded(.down))
            let lastSecond = Int((now + Double(mid / perSecond)).rounded(.up))
            for second in max(0, firstSecond)...max(0, lastSecond) {
                for quarter in 0..<4 {
                    let t = Double(second) + Double(quarter) / 4
                    let tx = mid + CGFloat(t - now) * perSecond
                    guard tx >= 0, tx <= size.width else { continue }
                    let tick = quarter == 0 ? 12.0 : 6.0
                    context.fill(Path(CGRect(x: tx, y: height, width: 1, height: tick)), with: .color(.secondary.opacity(0.5)))
                    if quarter == 0 {
                        let label = Text(Self.shortTime(TimeInterval(second))).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                        context.draw(label, at: CGPoint(x: tx + 4, y: height + 18), anchor: .leading)
                    }
                }
            }
            // Playhead.
            context.fill(Path(CGRect(x: mid - 1, y: 0, width: 2, height: height)), with: .color(accent))
            context.fill(Path(ellipseIn: CGRect(x: mid - 5, y: -5, width: 10, height: 10)), with: .color(accent))
            context.fill(Path(ellipseIn: CGRect(x: mid - 5, y: height - 5, width: 10, height: 10)), with: .color(accent))
        }
        .frame(height: 240)
        .background(Color.primary.opacity(0.025).padding(.bottom, 26))
        .padding(.horizontal, -20)
        .accessibilityHidden(true)
    }

    // MARK: Controls

    private var playbackControls: some View {
        let enabled = recorder.state == .paused && !recorder.isMerging
        return HStack(spacing: 56) {
            Button { recorder.skip(by: -15) } label: {
                Image(systemName: "gobackward.15").scaledFont(32)
            }
            .accessibilityLabel("Skip back 15 seconds")
            Button { recorder.togglePlayback() } label: {
                Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill").scaledFont(44)
                    .frame(width: 48)
            }
            .accessibilityLabel(recorder.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("recorderPlay")
            Button { recorder.skip(by: 15) } label: {
                Image(systemName: "goforward.15").scaledFont(32)
            }
            .accessibilityLabel("Skip forward 15 seconds")
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
        .disabled(!enabled)
    }

    /// Red circle to record; a red rounded square while recording, which pauses.
    private var recordButton: some View {
        let isRecording = recorder.state == .recording
        return Button {
            Task { await toggleRecording() }
        } label: {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 3).frame(width: 80, height: 80)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 33, style: .continuous)
                    .fill(Color.red)
                    .frame(width: isRecording ? 34 : 66, height: isRecording ? 34 : 66)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecording)
        }
        .buttonStyle(.plain)
        .disabled(recorder.isMerging || isSaving)
        .accessibilityLabel(isRecording ? "Pause recording" : "Record")
        .accessibilityIdentifier("recorderRecord")
    }

    private var permissionNotice: some View {
        VStack(spacing: 6) {
            Text("Microphone access is off").font(.footnote.weight(.semibold))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.footnote)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Actions

    private func toggleRecording() async {
        if recorder.state == .recording {
            await recorder.pause()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard await recorder.requestPermission() else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        if recorder.state == .idle { startedAt = Date() }
        recorder.record()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func save() {
        isSaving = true
        Task {
            if let note = await recorder.finish() {
                onSave(note.data, note.duration)
            }
            dismiss()
        }
    }

    // MARK: Formatting

    static func preciseTime(_ t: TimeInterval) -> String {
        let hundredths = Int((t * 100).rounded(.down))
        return String(format: "%02d:%02d.%02d", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }

    static func shortTime(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func dayAndTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return String(localized: "Today, \(time)")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension View {
    @ViewBuilder
    func recorderCircle(isSentinel: Bool, fill: Color?) -> some View {
        if isSentinel {
            self.background(Circle().fill(fill ?? MirrorTheme.inkMid))
                .overlay(Circle().stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1))
        } else if let fill {
            self.background(Circle().fill(fill))
        } else if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(Circle().fill(Color(.tertiarySystemFill)))
        }
    }
}
#endif
