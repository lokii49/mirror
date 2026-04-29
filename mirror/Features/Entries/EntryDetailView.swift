import SwiftUI
import SwiftData

private let moodLabels: [String] = ["Rough", "Low", "Okay", "Good", "Alive"]

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var insights: [Insight]

    let entry: Entry

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    private var moodLabel: String? {
        guard let mood = entry.mood, !mood.isEmpty else { return nil }
        return mood
    }

    private var relatedInsight: Insight? {
        insights.first { insight in
            insight.content.localizedCaseInsensitiveContains(
                entry.text.components(separatedBy: .whitespacesAndNewlines).prefix(6).joined(separator: " ")
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Date header
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.system(size: 18, weight: .semibold))

                    HStack(spacing: 6) {
                        Text(entry.createdAt, format: .dateTime.hour().minute())
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        if let label = moodLabel {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(entry.wordCount) words")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Entry text
                if !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.text)
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Photo if attached
                if let data = entry.photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let data = entry.voiceNoteData {
                    VoiceNoteAttachmentView(data: data, duration: entry.voiceNoteDuration)
                }

                // "mirror noticed" section — only if a past insight references this entry
                if let insight = relatedInsight {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("mirror noticed:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(insight.content)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
            }
            .padding(22)
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button("Edit") { showEdit = true }
                        .font(.system(size: 16, weight: .medium))

                    Menu {
                        Button("Share as text") { shareText() }
                        Button("Delete Entry", systemImage: "trash", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showEdit) {
            WriteView(entry: entry, showsBackButton: true)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func shareText() {
        let dateStr = entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let shareText = "\(dateStr)\n\n\(entry.text)"
        let av = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }
}
