import SwiftUI
import SwiftData

private let moodLabels = MirrorTheme.moodOptions

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var insights: [Insight]

    let entry: Entry

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var draftMood: String? = nil
    @State private var showDeleteConfirm = false
    @FocusState private var editorFocused: Bool

    private var moodLabel: String? {
        let mood = isEditing ? draftMood : entry.mood
        guard let mood, !mood.isEmpty else { return nil }
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
            VStack(alignment: .leading, spacing: 14) {
                // Main entry card
                VStack(alignment: .leading, spacing: 16) {
                    // Date header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.createdAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.system(size: 18, weight: .semibold))

                        HStack(spacing: 6) {
                            Text(entry.createdAt, format: .dateTime.hour().minute())
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            if isEditing {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                moodMenu
                            } else if let label = moodLabel {
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
                            Text("\(currentWordCount) words")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    if isEditing {
                        TextEditor(text: $draftText)
                            .focused($editorFocused)
                            .font(.system(size: 17, weight: .regular))
                            .lineSpacing(6)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(entry.text)
                            .font(.system(size: 17, weight: .regular))
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No text")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Photo if attached
                    if let data = entry.photoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                    }

                    if !entry.voiceNotes.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(entry.voiceNotes.indices, id: \.self) { index in
                                VoiceNoteAttachmentView(
                                    data: entry.voiceNotes[index].data,
                                    duration: entry.voiceNotes[index].duration,
                                    title: "Voice note \(index + 1)",
                                    transcript: entry.voiceNotes[index].transcript,
                                    languageName: entry.voiceNotes[index].languageName
                                )
                            }
                        }
                    }
                }
                .padding(22)
                .futureSurface(cornerRadius: 22)

                // "mirror noticed" card — only if a past insight references this entry
                if let insight = relatedInsight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("mirror noticed:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(insight.content)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    .padding(18)
                    .accentCard(cornerRadius: 18)
                    .glowShadow(color: MirrorTheme.primary, radius: 20)
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(MirrorTheme.bgBase)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if isEditing {
                        Button {
                            saveInlineEdits()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityLabel("Save changes")
                    } else {
                        Button("Edit") { beginInlineEditing() }
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
        }
        .onAppear { resetDrafts() }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var currentWordCount: Int {
        let text = isEditing ? draftText : entry.text
        return text.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
    }

    private var moodMenu: some View {
        Menu {
            ForEach(moodLabels, id: \.self) { mood in
                Button {
                    draftMood = draftMood == mood ? nil : mood
                } label: {
                    if draftMood == mood {
                        Label(mood, systemImage: "checkmark")
                    } else {
                        Text(mood)
                    }
                }
            }

            if draftMood != nil {
                Divider()
                Button("Clear Mood", role: .destructive) {
                    draftMood = nil
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(draftMood ?? "Mood")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(draftMood == nil ? .secondary : Color.accentColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                draftMood == nil ? Color(.tertiarySystemFill) : Color.accentColor.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func beginInlineEditing() {
        resetDrafts()
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            editorFocused = true
        }
    }

    private func saveInlineEdits() {
        let plain = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = plain
        entry.wordCount = plain.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
        entry.mood = draftMood
        entry.source = !entry.voiceNotes.isEmpty && plain.isEmpty ? .voice : .typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editorFocused = false
        isEditing = false
    }

    private func resetDrafts() {
        draftText = entry.text
        draftMood = entry.mood
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
