import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var insights: [Insight]

    let entry: Entry
    var onDone: (() -> Void)? = nil

    @State private var showEditor = false
    @State private var showDeleteConfirm = false
    @State private var relatedInsight: Insight? = nil
    @State private var displayedWordCount: Int = 0

    private var moodLabel: String? {
        let mood = entry.mood
        guard let mood, !mood.isEmpty else { return nil }
        return mood
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
                            Text("\(displayedWordCount) words")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    if entry.textDecryptionFailed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Encrypted entry unavailable")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("This entry still exists, but this device does not have the encryption key needed to read its text.")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !entry.photoDataArray.isEmpty || !allPhotoTokens(in: entry.text).isEmpty || !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        InlineEntryContent(text: entry.text, textStyleData: entry.textStyleData, photoDataArray: entry.photoDataArray)
                    } else {
                        Text("No text")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !entry.voiceNotes.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(entry.voiceNotes.indices, id: \.self) { index in
                                let note = entry.voiceNotes[index]
                                VoiceNoteAttachmentView(
                                    data: note.data,
                                    duration: note.duration,
                                    title: "Voice note \(index + 1)",
                                    transcript: note.transcript,
                                    languageName: note.languageName,
                                    transcriptionFailed: index == 0 && entry.voiceNoteTranscriptionFailed
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
                        Text("MirrorNotes noticed:")
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
        .task(id: entry.id) {
            let text = entry.text
            let prefix = text
                .components(separatedBy: .whitespacesAndNewlines)
                .prefix(6)
                .joined(separator: " ")
            relatedInsight = insights.first { insight in
                insight.content.localizedCaseInsensitiveContains(prefix)
            }
            displayedWordCount = strippedWordCount(text)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button("Edit") { showEditor = true }
                        .font(.system(size: 16, weight: .medium))
                        .disabled(entry.textDecryptionFailed)

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
        .navigationDestination(isPresented: $showEditor) {
            WriteView(entry: entry, autoFocus: true, showsBackButton: true)
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                onDone?()
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

private struct InlineEntryContent: View {
    let text: String
    let textStyleData: Data?
    let photoDataArray: [Data]

    private var paragraphStyles: [NoteParagraphTextStyle] {
        guard let textStyleData,
              let document = try? JSONDecoder().decode(NoteTextStyleDocument.self, from: textStyleData) else {
            return []
        }
        return document.paragraphStyles
    }

    private var displayLines: [String] {
        text.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                if let photoIndex = inlinePhotoIndex(from: line.trimmingCharacters(in: .whitespaces)),
                   photoIndex < photoDataArray.count,
                   let uiImage = UIImage(data: photoDataArray[photoIndex]) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .padding(.vertical, 4)
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    styledText(for: line, at: index)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func styledText(for line: String, at index: Int) -> some View {
        let style = paragraphStyles.indices.contains(index) ? paragraphStyles[index] : legacyStyle(for: line)
        let displayLine = lineWithoutLegacyPrefix(line)
        if style == .title {
            Text(displayLine)
                .font(.system(size: 30, weight: .bold))
        } else if style == .heading {
            Text(displayLine)
                .font(.system(size: 22, weight: .bold))
        } else if style == .subheading {
            Text(displayLine)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if style == .monospaced {
            Text(displayLine)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
        } else if style == .checklistUnchecked || style == .checklistChecked {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(style == .checklistChecked ? "✓" : "○")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(style == .checklistChecked ? .tertiary : .secondary)
                    .frame(width: 24, alignment: .center)
                Text(displayLine)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(style == .checklistChecked ? .tertiary : .primary)
                    .strikethrough(style == .checklistChecked, color: .secondary)
            }
        } else {
            Text(line)
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(6)
        }
    }

    private func lineWithoutLegacyPrefix(_ line: String) -> String {
        if line.hasPrefix("### ") { return String(line.dropFirst(4)) }
        if line.hasPrefix("## ") { return String(line.dropFirst(3)) }
        if line.hasPrefix("# ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
        if line.hasPrefix("○ ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("✓ ") { return String(line.dropFirst(2)) }
        return line
    }

    private func legacyStyle(for line: String) -> NoteParagraphTextStyle {
        if line.hasPrefix("### ") { return .subheading }
        if line.hasPrefix("## ") { return .heading }
        if line.hasPrefix("# ") { return .title }
        if line.hasPrefix("    ") { return .monospaced }
        if line.hasPrefix("✓ ") { return .checklistChecked }
        if line.hasPrefix("○ ") { return .checklistUnchecked }
        return .body
    }
}
