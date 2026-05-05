import SwiftUI
import SwiftData
import PhotosUI

private let moodLabels = MirrorTheme.moodOptions

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var insights: [Insight]

    let entry: Entry

    @State private var isEditing = false
    @State private var draftText = ""
    @State private var draftMood: String? = nil
    @State private var draftPhotoData: Data? = nil
    @State private var pendingTextCommand: NoteTextCommand?
    @State private var pendingBeforePhotoCommand: NoteTextCommand?
    @State private var pendingAfterPhotoCommand: NoteTextCommand?
    @State private var showDeleteConfirm = false
    @State private var showPhotoPicker = false
    @State private var photoAttachError: String? = nil
    @State private var isAttachingPhoto = false
    @State private var showVoiceInput = false
    @State private var beforePhotoFocused = false
    @State private var afterPhotoFocused = false
    @FocusState private var editorFocused: Bool

    private var hasInlinePhoto: Bool {
        draftPhotoData != nil && draftText.contains(inlinePhotoToken)
    }

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
                        NoteEditorTextView(
                            text: $draftText,
                            photoData: $draftPhotoData,
                            command: $pendingTextCommand,
                            isFocused: Binding(
                                get: { editorFocused },
                                set: { editorFocused = $0 }
                            )
                        )
                        .frame(minHeight: 260)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !entry.text.replacingOccurrences(of: inlinePhotoToken, with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.photoData != nil {
                        InlineEntryContent(text: entry.text, photoData: entry.photoData)
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
                                let deleteAction: (() -> Void)? = isEditing ? { removeDetailVoiceNote(at: index) } : nil
                                VoiceNoteAttachmentView(
                                    data: note.data,
                                    duration: note.duration,
                                    title: "Voice note \(index + 1)",
                                    transcript: note.transcript,
                                    languageName: note.languageName,
                                    onDelete: deleteAction
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                editToolRow
            }
        }
        .onAppear { resetDrafts() }
        .sheet(isPresented: $showPhotoPicker) {
            NativePhotoPicker { result in
                handlePickedPhoto(result)
            }
            .ignoresSafeArea()
        }
        .alert("Photo not attached", isPresented: Binding(
            get: { photoAttachError != nil },
            set: { if !$0 { photoAttachError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoAttachError ?? "")
        }
        .sheet(isPresented: $showVoiceInput) {
            VoiceInputSheet { data, duration in
                let newIndex = entry.additionalVoiceNoteData.count
                entry.additionalVoiceNoteData.append(data)
                entry.additionalVoiceNoteDurations.append(duration)
                transcribeAndSaveDetailVoiceNote(data: data, index: newIndex)
            }
        }
        .overlay {
            if isAttachingPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Attaching photo")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar, in: Capsule())
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entry)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var editToolRow: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button { showPhotoPicker = true } label: {
                    Image(systemName: draftPhotoData != nil ? "photo.fill" : "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(draftPhotoData != nil ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Button { showVoiceInput = true } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Button { pendingTextCommand = .checklist } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                detailFormatMenu
            }
            .padding(.horizontal, 8)
        }
        .background(.bar)
    }

    private var detailFormatMenu: some View {
        Menu {
            Button { pendingTextCommand = .title } label: { Label("Title", systemImage: "textformat.size.larger") }
            Button { pendingTextCommand = .heading } label: { Label("Heading", systemImage: "textformat.size") }
            Button { pendingTextCommand = .subheading } label: { Label("Subheading", systemImage: "textformat") }
            Button { pendingTextCommand = .body } label: { Label("Body", systemImage: "text.alignleft") }
            Button { pendingTextCommand = .monospaced } label: { Label("Monostyled", systemImage: "curlybraces") }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func transcribeAndSaveDetailVoiceNote(data: Data, index: Int) {
        Task {
            guard let result = try? await VoiceTranscriptionService.transcribe(audioData: data, token: "") else { return }
            await MainActor.run {
                while entry.additionalVoiceNoteTranscripts.count <= index {
                    entry.additionalVoiceNoteTranscripts.append("")
                }
                entry.additionalVoiceNoteTranscripts[index] = result.transcript
                while entry.additionalVoiceNoteLanguageCodes.count <= index {
                    entry.additionalVoiceNoteLanguageCodes.append("")
                }
                entry.additionalVoiceNoteLanguageCodes[index] = result.languageCode
                while entry.additionalVoiceNoteLanguageNames.count <= index {
                    entry.additionalVoiceNoteLanguageNames.append("")
                }
                entry.additionalVoiceNoteLanguageNames[index] = result.languageName
            }
        }
    }

    private func removeDetailVoiceNote(at index: Int) {
        if index == 0 {
            entry.voiceNoteData = nil
            entry.voiceNoteDuration = 0
            entry.voiceNoteTranscript = nil
            entry.voiceNoteLanguageCode = nil
            entry.voiceNoteLanguageName = nil
            entry.voiceNoteEnglishTranslation = nil
            if !entry.additionalVoiceNoteData.isEmpty {
                entry.voiceNoteData = entry.additionalVoiceNoteData.removeFirst()
                entry.voiceNoteDuration = entry.additionalVoiceNoteDurations.isEmpty ? 0 : entry.additionalVoiceNoteDurations.removeFirst()
                entry.voiceNoteTranscript = entry.additionalVoiceNoteTranscripts.isEmpty ? nil : entry.additionalVoiceNoteTranscripts.removeFirst()
                entry.voiceNoteLanguageCode = entry.additionalVoiceNoteLanguageCodes.isEmpty ? nil : entry.additionalVoiceNoteLanguageCodes.removeFirst()
                entry.voiceNoteLanguageName = entry.additionalVoiceNoteLanguageNames.isEmpty ? nil : entry.additionalVoiceNoteLanguageNames.removeFirst()
                entry.voiceNoteEnglishTranslation = entry.additionalVoiceNoteEnglishTranslations.isEmpty ? nil : entry.additionalVoiceNoteEnglishTranslations.removeFirst()
            }
        } else {
            let additionalIndex = index - 1
            if entry.additionalVoiceNoteData.indices.contains(additionalIndex) {
                entry.additionalVoiceNoteData.remove(at: additionalIndex)
            }
            if entry.additionalVoiceNoteDurations.indices.contains(additionalIndex) {
                entry.additionalVoiceNoteDurations.remove(at: additionalIndex)
            }
            if entry.additionalVoiceNoteTranscripts.indices.contains(additionalIndex) {
                entry.additionalVoiceNoteTranscripts.remove(at: additionalIndex)
            }
            if entry.additionalVoiceNoteLanguageCodes.indices.contains(additionalIndex) {
                entry.additionalVoiceNoteLanguageCodes.remove(at: additionalIndex)
            }
            if entry.additionalVoiceNoteLanguageNames.indices.contains(additionalIndex) {
                entry.additionalVoiceNoteLanguageNames.remove(at: additionalIndex)
            }
            if entry.additionalVoiceNoteEnglishTranslations.indices.contains(additionalIndex) {
                entry.additionalVoiceNoteEnglishTranslations.remove(at: additionalIndex)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var currentWordCount: Int {
        let text = isEditing ? draftText : entry.text
        return text.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
    }

    private var moodMenu: some View {
        Menu {
            ForEach(moodLabels, id: \.self) { mood in
                Button {
                    draftMood = draftMood == mood ? nil : mood
                } label: {
                    Label {
                        Text(mood)
                    } icon: {
                        Circle()
                            .fill(MirrorTheme.moodColor(for: mood))
                            .frame(width: 10, height: 10)
                            .overlay {
                                if draftMood == mood {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
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
                    .foregroundStyle(draftMood == nil ? .secondary : MirrorTheme.moodColor(for: draftMood ?? ""))
                if let draftMood {
                    Circle()
                        .fill(MirrorTheme.moodColor(for: draftMood))
                        .frame(width: 7, height: 7)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                draftMood == nil ? Color(.tertiarySystemFill) : MirrorTheme.moodColor(for: draftMood ?? "").opacity(0.12),
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
        entry.wordCount = plain.replacingOccurrences(of: inlinePhotoToken, with: "")
            .split { $0.isWhitespace }
            .filter { !$0.isEmpty }
            .count
        entry.mood = draftMood
        entry.photoData = draftPhotoData
        entry.source = !entry.voiceNotes.isEmpty && plain.isEmpty ? .voice : .typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editorFocused = false
        isEditing = false
    }

    private func resetDrafts() {
        draftText = entry.text
        if entry.photoData != nil, !draftText.contains(inlinePhotoToken) {
            let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            draftText = trimmed.isEmpty ? inlinePhotoToken : "\(trimmed)\n\(inlinePhotoToken)"
        }
        draftMood = entry.mood
        draftPhotoData = entry.photoData
    }

    private func handlePickedPhoto(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isAttachingPhoto = true
            Task {
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let preparedData = try await Task.detached(priority: .userInitiated) {
                        try preparedInlinePhotoData(fromFileAt: url)
                    }.value
                    draftPhotoData = preparedData
                    draftText = textWithInlinePhotoToken(draftText)
                    isAttachingPhoto = false
                } catch {
                    isAttachingPhoto = false
                    photoAttachError = "This image could not be attached. Try a different image or export it as JPEG first."
                }
            }
        case .failure:
            photoAttachError = "This image could not be attached. Try a different image or export it as JPEG first."
        }
    }

    private var beforePhotoDetailBinding: Binding<String> {
        Binding(
            get: {
                guard let r = draftText.range(of: inlinePhotoToken) else { return draftText }
                return String(draftText[..<r.lowerBound]).trimmingCharacters(in: .newlines)
            },
            set: { newValue in
                guard let r = draftText.range(of: inlinePhotoToken) else { draftText = newValue; return }
                let after = String(draftText[r.upperBound...]).trimmingCharacters(in: .newlines)
                draftText = newValue.isEmpty ? "\(inlinePhotoToken)\n\(after)" : "\(newValue)\n\(inlinePhotoToken)\n\(after)"
            }
        )
    }

    private var afterPhotoDetailBinding: Binding<String> {
        Binding(
            get: {
                guard let r = draftText.range(of: inlinePhotoToken) else { return "" }
                return String(draftText[r.upperBound...]).trimmingCharacters(in: .newlines)
            },
            set: { newValue in
                guard let r = draftText.range(of: inlinePhotoToken) else { return }
                let before = String(draftText[..<r.lowerBound]).trimmingCharacters(in: .newlines)
                draftText = before.isEmpty ? "\(inlinePhotoToken)\n\(newValue)" : "\(before)\n\(inlinePhotoToken)\n\(newValue)"
            }
        )
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
    let photoData: Data?

    private var displayLines: [String] {
        if photoData != nil, !text.contains(inlinePhotoToken) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty ? inlinePhotoToken : "\(trimmed)\n\(inlinePhotoToken)").components(separatedBy: .newlines)
        }
        return text.components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                if line == inlinePhotoToken, let photoData, let uiImage = UIImage(data: photoData) {
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
                    styledText(for: line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func styledText(for line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(String(line.dropFirst(2)))
                .font(.system(size: 30, weight: .bold))
        } else if line.hasPrefix("## ") {
            Text(String(line.dropFirst(3)))
                .font(.system(size: 22, weight: .bold))
        } else if line.hasPrefix("### ") {
            Text(String(line.dropFirst(4)))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
        } else if line.hasPrefix("    ") {
            Text(String(line.dropFirst(4)))
                .font(.system(size: 16, weight: .regular, design: .monospaced))
        } else {
            Text(line)
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(6)
        }
    }
}
