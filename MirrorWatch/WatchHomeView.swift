import SwiftUI

/// The watch's one screen (owner's option A, 2026-11-06): Record a voice note first, then Type a
/// Note, then Log Mood, and how many items are still on their way to the iPhone.
struct WatchHomeView: View {
    @Environment(WatchSender.self) private var sender
    @State private var path: [WatchScreen] = WatchHomeView.initialPath

    enum WatchScreen: String, Hashable { case record, type, mood }

    /// DEBUG `--watchScreen=record|type|mood` opens that screen (simulator screenshots can't tap).
    private static var initialPath: [WatchScreen] {
        #if DEBUG
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--watchScreen=") }),
           let screen = WatchScreen(rawValue: String(arg.dropFirst("--watchScreen=".count))) {
            return [screen]
        }
        #endif
        return []
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 8) {
                    NavigationLink(value: WatchScreen.record) {
                        HStack(spacing: 10) {
                            Image(systemName: "mic.fill")
                                .font(.title3)
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.18), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Record").font(.headline)
                                Text("A voice note").font(.caption2).opacity(0.85)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(WatchTheme.heroFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    WatchTile(title: "Type a Note", systemImage: "keyboard", screen: .type)
                    WatchTile(title: "Log Mood", systemImage: "face.smiling", screen: .mood)

                    if sender.waiting > 0 {
                        Text("Waiting for iPhone: \(sender.waiting)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("MirrorNotes")
            .navigationDestination(for: WatchScreen.self) { screen in
                switch screen {
                case .record: WatchRecordView()
                case .type: WatchNoteView()
                case .mood: WatchMoodPicker()
                }
            }
        }
    }
}

/// The app's plum on the watch (Plum & Paper): the accent for text, the deep plums for fills that
/// carry white.
enum WatchTheme {
    static let plum = Color(red: 0.788, green: 0.545, blue: 0.776)        // #C98BC6
    static let fill = Color(red: 0.541, green: 0.216, blue: 0.412)        // #8A3769
    static let heroFill = LinearGradient(colors: [Color(red: 0.431, green: 0.165, blue: 0.333), fill,
                                                  Color(red: 0.604, green: 0.267, blue: 0.471)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let tile = Color(red: 0.122, green: 0.102, blue: 0.118)        // #1F1A1E
}

private struct WatchTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let screen: WatchHomeView.WatchScreen

    var body: some View {
        NavigationLink(value: screen) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchTheme.plum)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.08), in: Circle())
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WatchTheme.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Record

/// Recording starts when the screen opens. Stop keeps it for review (Play, Send); ✕ or leaving
/// without sending deletes it. Nothing leaves the watch until Send.
private struct WatchRecordView: View {
    @Environment(WatchSender.self) private var sender
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = WatchRecorder()
    @State private var sent = false
    @State private var outboxFull = false

    var body: some View {
        Group {
            if sent {
                WatchSentView(title: "Voice note sent") { dismiss() }
            } else {
                switch recorder.state {
                case .idle, .recording:
                    recording
                case .recorded, .playing:
                    review
                case .denied:
                    message("Turn on the microphone for MirrorNotes in Settings on your watch.")
                case .failed:
                    message("Couldn't record. Try again.")
                }
            }
        }
        .toolbar {
            if !sent {
                ToolbarItem(placement: .cancellationAction) {
                    Button { recorder.discard(); dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Discard")
                }
            }
        }
        .task { await recorder.start() }
        .onDisappear { if !sent { recorder.discard() } }
        .alert("Too many notes waiting", isPresented: $outboxFull) {
            Button("OK") { dismiss() }
        } message: {
            Text("Open MirrorNotes on your iPhone so the waiting notes can arrive, then record again.")
        }
    }

    private var recording: some View {
        VStack(spacing: 10) {
            Text(Self.clock(recorder.elapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                    Capsule().fill(WatchTheme.plum).frame(width: 4, height: 4 + 22 * level)
                }
            }
            .frame(height: 28)
            .accessibilityHidden(true)
            Button { recorder.stop() } label: {
                RoundedRectangle(cornerRadius: 5).fill(.white).frame(width: 20, height: 20)
                    .frame(width: 56, height: 56)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
            .disabled(recorder.state != .recording)
        }
    }

    private var review: some View {
        VStack(spacing: 10) {
            Text(Self.clock(recorder.elapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            Text("Voice note").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    recorder.togglePlayback()
                } label: {
                    Label(recorder.state == .playing ? "Pause" : "Play",
                          systemImage: recorder.state == .playing ? "pause.fill" : "play.fill")
                }
                Button {
                    guard let note = recorder.takeRecording() else { return }
                    if sender.sendVoice(from: note.url, duration: note.duration) {
                        sent = true
                    } else {
                        outboxFull = true
                    }
                } label: {
                    Text("Send").fontWeight(.semibold)
                }
                .tint(WatchTheme.fill)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash").font(.title2).foregroundStyle(.secondary)
            Text(text).font(.footnote).multilineTextAlignment(.center)
        }
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Mood

/// The twelve moods, as in the app (names and colours), positive first, three across. The
/// colours are `MirrorTheme.moodColor(for:)`'s exact values (the watch target can't import it);
/// the six hard moods carry the app's thin ring, so good and hard read apart without colour.
private struct WatchMoodPicker: View {
    @Environment(WatchSender.self) private var sender
    @Environment(\.dismiss) private var dismiss
    @State private var sent: String?

    static let moods: [(key: String, name: LocalizedStringResource, color: Color, hard: Bool)] = [
        ("Joyful", "Joyful", Color(red: 1.000, green: 0.835, blue: 0.310), false),
        ("Grateful", "Grateful", Color(red: 0.400, green: 0.733, blue: 0.416), false),
        ("Peaceful", "Peaceful", Color(red: 0.506, green: 0.831, blue: 0.980), false),
        ("Content", "Content", Color(red: 0.302, green: 0.714, blue: 0.675), false),
        ("Energized", "Energized", Color(red: 1.000, green: 0.596, blue: 0.000), false),
        ("Hopeful", "Hopeful", Color(red: 0.584, green: 0.459, blue: 0.804), false),
        ("Anxious", "Anxious", Color(red: 0.831, green: 0.659, blue: 0.294), true),
        ("Overwhelmed", "Overwhelmed", Color(red: 0.851, green: 0.416, blue: 0.388), true),
        ("Frustrated", "Frustrated", Color(red: 0.851, green: 0.541, blue: 0.310), true),
        ("Drained", "Drained", Color(red: 0.604, green: 0.588, blue: 0.639), true),
        ("Sad", "Sad", Color(red: 0.416, green: 0.624, blue: 0.820), true),
        ("Numb", "Numb", Color(red: 0.765, green: 0.796, blue: 0.820), true),
    ]

    var body: some View {
        if let sent {
            WatchSentView(title: LocalizedStringResource(stringLiteral: sent)) { dismiss() }
        } else {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
                    ForEach(Self.moods, id: \.key) { mood in
                        Button {
                            sender.send(.mood, value: mood.key)
                            sent = mood.key
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(mood.color)
                                    .overlay { if mood.hard { Circle().strokeBorder(.white.opacity(0.55), lineWidth: 2) } }
                                    .frame(width: 34, height: 34)
                                Text(mood.name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .navigationTitle("Log Mood")
        }
    }
}

// MARK: - Type

/// A typed note: the keyboard, Scribble or dictation, as watchOS offers on the text field.
private struct WatchNoteView: View {
    @Environment(WatchSender.self) private var sender
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sent = false

    var body: some View {
        if sent {
            WatchSentView(title: "Note sent") { dismiss() }
        } else {
            VStack(spacing: 10) {
                TextField("Note", text: $text, axis: .vertical)
                Button("Send") {
                    sender.send(.note, value: text.trimmingCharacters(in: .whitespacesAndNewlines))
                    sent = true
                }
                .tint(WatchTheme.fill)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Type a Note")
        }
    }
}

private struct WatchSentView: View {
    let title: LocalizedStringResource
    let done: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(WatchTheme.fill, in: Circle())
            Text(title).font(.headline)
            Text("Sent to MirrorNotes on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done", action: done)
        }
    }
}
