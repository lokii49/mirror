import SwiftUI

/// The watch's one screen: Log Mood and Quick Note, and how many items are still on their way.
struct WatchHomeView: View {
    @Environment(WatchSender.self) private var sender

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchMoodPicker()
                } label: {
                    Label("Log Mood", systemImage: "face.smiling")
                }
                NavigationLink {
                    WatchNoteView()
                } label: {
                    Label("Quick Note", systemImage: "square.and.pencil")
                }
                if sender.waiting > 0 {
                    Text("Waiting for iPhone: \(sender.waiting)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("MirrorNotes")
        }
    }
}

/// The twelve moods, as in the app (names and colours), positive first. The colours are
/// `MirrorTheme.moodColor(for:)`'s exact values (the watch target can't import it).
private struct WatchMoodPicker: View {
    @Environment(WatchSender.self) private var sender
    @Environment(\.dismiss) private var dismiss
    @State private var sent: String?

    static let moods: [(key: String, name: LocalizedStringResource, color: Color)] = [
        ("Joyful", "Joyful", Color(red: 1.000, green: 0.835, blue: 0.310)),
        ("Grateful", "Grateful", Color(red: 0.400, green: 0.733, blue: 0.416)),
        ("Peaceful", "Peaceful", Color(red: 0.506, green: 0.831, blue: 0.980)),
        ("Content", "Content", Color(red: 0.302, green: 0.714, blue: 0.675)),
        ("Energized", "Energized", Color(red: 1.000, green: 0.596, blue: 0.000)),
        ("Hopeful", "Hopeful", Color(red: 0.584, green: 0.459, blue: 0.804)),
        ("Anxious", "Anxious", Color(red: 0.831, green: 0.659, blue: 0.294)),
        ("Overwhelmed", "Overwhelmed", Color(red: 0.851, green: 0.416, blue: 0.388)),
        ("Frustrated", "Frustrated", Color(red: 0.851, green: 0.541, blue: 0.310)),
        ("Drained", "Drained", Color(red: 0.604, green: 0.588, blue: 0.639)),
        ("Sad", "Sad", Color(red: 0.416, green: 0.624, blue: 0.820)),
        ("Numb", "Numb", Color(red: 0.765, green: 0.796, blue: 0.820)),
    ]

    var body: some View {
        if let sent {
            WatchSentView(title: LocalizedStringResource(stringLiteral: sent)) { dismiss() }
        } else {
            List(Self.moods, id: \.key) { mood in
                Button {
                    sender.send(.mood, value: mood.key)
                    sent = mood.key
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(mood.color).frame(width: 10, height: 10)
                        Text(mood.name)
                    }
                }
            }
            .navigationTitle("Log Mood")
        }
    }
}

/// A note: dictation, Scribble or the keyboard (watchOS offers them on the text field).
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
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Quick Note")
        }
    }
}

private struct WatchSentView: View {
    let title: LocalizedStringResource
    let done: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(title).font(.headline)
            Text("Sent to MirrorNotes on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done", action: done)
        }
    }
}
