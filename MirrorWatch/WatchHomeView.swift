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

/// The twelve moods, as in the app (names and colours), positive first.
private struct WatchMoodPicker: View {
    @Environment(WatchSender.self) private var sender
    @Environment(\.dismiss) private var dismiss
    @State private var sent: String?

    static let moods: [(key: String, name: LocalizedStringResource, color: Color)] = [
        ("Joyful", "Joyful", Color(red: 0.98, green: 0.76, blue: 0.20)),
        ("Grateful", "Grateful", Color(red: 0.38, green: 0.75, blue: 0.45)),
        ("Peaceful", "Peaceful", Color(red: 0.45, green: 0.75, blue: 0.95)),
        ("Content", "Content", Color(red: 0.36, green: 0.70, blue: 0.66)),
        ("Energized", "Energized", Color(red: 0.98, green: 0.58, blue: 0.20)),
        ("Hopeful", "Hopeful", Color(red: 0.62, green: 0.50, blue: 0.92)),
        ("Anxious", "Anxious", Color(red: 0.85, green: 0.68, blue: 0.30)),
        ("Overwhelmed", "Overwhelmed", Color(red: 0.78, green: 0.42, blue: 0.52)),
        ("Frustrated", "Frustrated", Color(red: 0.88, green: 0.42, blue: 0.36)),
        ("Drained", "Drained", Color(red: 0.55, green: 0.55, blue: 0.62)),
        ("Sad", "Sad", Color(red: 0.42, green: 0.52, blue: 0.80)),
        ("Numb", "Numb", Color(red: 0.62, green: 0.62, blue: 0.66)),
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
