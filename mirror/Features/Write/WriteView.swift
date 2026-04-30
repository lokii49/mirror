import SwiftUI
import SwiftData
import PhotosUI

private let moodLabels = MirrorTheme.moodOptions

struct WriteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var entry: Entry? = nil
    var autoFocus: Bool = false
    var showsBackButton: Bool = false

    @State private var viewModel = WriteViewModel()
    @State private var isKeyboardVisible = false
    @State private var showSaved = false
    @State private var showDeleteConfirm = false
    @State private var showVoiceInput = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var photoData: Data? = nil
    @State private var voiceNoteData: Data? = nil
    @State private var voiceNoteDuration: TimeInterval = 0
    @State private var voiceNoteTranscript: String? = nil
    @State private var voiceNoteLanguageCode: String? = nil
    @State private var voiceNoteLanguageName: String? = nil
    @State private var voiceNoteEnglishTranslation: String? = nil
    @State private var additionalVoiceNoteData: [Data] = []
    @State private var additionalVoiceNoteDurations: [TimeInterval] = []
    @State private var additionalVoiceNoteTranscripts: [String] = []
    @State private var additionalVoiceNoteLanguageCodes: [String] = []
    @State private var additionalVoiceNoteLanguageNames: [String] = []
    @State private var additionalVoiceNoteEnglishTranslations: [String] = []
    @State private var transcribingVoiceNoteIndexes: Set<Int> = []
    @State private var isDetectingMood = false
    @FocusState private var editorFocused: Bool

    private var noteDate: Date { entry?.createdAt ?? Date() }
    private var hasDraftContent: Bool {
        viewModel.hasContent || photoData != nil || !draftVoiceNotes.isEmpty
    }
    private var isTranscribingVoiceNotes: Bool {
        !transcribingVoiceNoteIndexes.isEmpty
    }
    private var draftVoiceNotes: [(data: Data, duration: TimeInterval, transcript: String?, languageName: String?, englishTranslation: String?)] {
        var notes: [(Data, TimeInterval, String?, String?, String?)] = []
        if let voiceNoteData {
            notes.append((
                voiceNoteData,
                voiceNoteDuration,
                voiceNoteTranscript,
                voiceNoteLanguageName,
                voiceNoteEnglishTranslation
            ))
        }
        for (index, data) in additionalVoiceNoteData.enumerated() {
            let duration = index < additionalVoiceNoteDurations.count ? additionalVoiceNoteDurations[index] : 0
            let transcript = index < additionalVoiceNoteTranscripts.count ? additionalVoiceNoteTranscripts[index] : nil
            let languageName = index < additionalVoiceNoteLanguageNames.count ? additionalVoiceNoteLanguageNames[index] : nil
            let translation = index < additionalVoiceNoteEnglishTranslations.count ? additionalVoiceNoteEnglishTranslations[index] : nil
            notes.append((
                data,
                duration,
                transcript,
                languageName,
                translation
            ))
        }
        return notes
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                dateHeader

                if !draftVoiceNotes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(draftVoiceNotes.indices, id: \.self) { index in
                            VoiceNoteAttachmentView(
                                data: draftVoiceNotes[index].data,
                                duration: draftVoiceNotes[index].duration,
                                title: "Voice note \(index + 1)",
                                transcript: draftVoiceNotes[index].transcript,
                                languageName: draftVoiceNotes[index].languageName,
                                isTranscribing: transcribingVoiceNoteIndexes.contains(index)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.text)
                        .focused($editorFocused)
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(6)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemBackground))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    if viewModel.text.isEmpty {
                        Text("What's on your mind?")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showSaved {
                Text("Saved")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar, in: Capsule())
                    .transition(.opacity.animation(.easeOut(duration: 0.3)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isKeyboardVisible {
                toolRow
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onAppear {
            viewModel.configure(entry: entry)
            if let entry {
                photoData = entry.photoData
                voiceNoteData = entry.voiceNoteData
                voiceNoteDuration = entry.voiceNoteDuration
                voiceNoteTranscript = entry.voiceNoteTranscript
                voiceNoteLanguageCode = entry.voiceNoteLanguageCode
                voiceNoteLanguageName = entry.voiceNoteLanguageName
                voiceNoteEnglishTranslation = entry.voiceNoteEnglishTranslation
                additionalVoiceNoteData = entry.additionalVoiceNoteData
                additionalVoiceNoteDurations = entry.additionalVoiceNoteDurations
                additionalVoiceNoteTranscripts = entry.additionalVoiceNoteTranscripts
                additionalVoiceNoteLanguageCodes = entry.additionalVoiceNoteLanguageCodes
                additionalVoiceNoteLanguageNames = entry.additionalVoiceNoteLanguageNames
                additionalVoiceNoteEnglishTranslations = entry.additionalVoiceNoteEnglishTranslations
            }
            if autoFocus || entry != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    editorFocused = true
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            Task {
                photoData = try? await item?.loadTransferable(type: Data.self)
            }
        }
        .sheet(isPresented: $showVoiceInput) {
            VoiceInputSheet { data, duration in
                appendVoiceNote(data: data, duration: duration)
            }
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(noteDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            moodMenu
        }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var moodMenu: some View {
        Menu {
            Button {
                detectMoodWithMirror()
            } label: {
                Label(isDetectingMood ? "Detecting…" : "Mirror suggests", systemImage: "sparkles")
            }
            .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDetectingMood)

            Divider()

            ForEach(moodLabels, id: \.self) { mood in
                Button {
                    viewModel.selectedMood = viewModel.selectedMood == mood ? nil : mood
                } label: {
                    if viewModel.selectedMood == mood {
                        Label(mood, systemImage: "checkmark")
                    } else {
                        Text(mood)
                    }
                }
            }

            if viewModel.selectedMood != nil {
                Divider()
                Button("Clear Mood", role: .destructive) {
                    viewModel.selectedMood = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isDetectingMood {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 13, height: 13)
                } else {
                    Text(viewModel.selectedMood ?? "Mood")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(viewModel.selectedMood == nil ? .secondary : Color.accentColor)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                viewModel.selectedMood == nil && !isDetectingMood
                    ? Color(.secondarySystemFill)
                    : Color.accentColor.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mood")
        .accessibilityValue(viewModel.selectedMood ?? "Not selected")
    }

    private func detectMoodWithMirror() {
        let text = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let token = KeychainManager.load() else { return }
        isDetectingMood = true
        Task {
            let detected = try? await InsightService.detectEmotion(text: text, token: token)
            await MainActor.run {
                if let detected, MirrorTheme.moodOptions.contains(detected) {
                    viewModel.selectedMood = detected
                }
                isDetectingMood = false
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if showsBackButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    saveAndDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isTranscribingVoiceNotes)
            }
        }

        if entry != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Done") { saveAndDismiss() }
                        .disabled(isTranscribingVoiceNotes)
                    Button("Delete Entry", systemImage: "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { deleteAndDismiss() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveDraft()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(hasDraftContent ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!hasDraftContent || isTranscribingVoiceNotes)
                .accessibilityLabel("Save entry")
            }
        }
    }

    private var toolRow: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                // Photo button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: photoData != nil ? "photo.fill" : "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(photoData != nil ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // Voice button
                Button {
                    presentVoiceNoteSheet()
                } label: {
                    Image(systemName: !draftVoiceNotes.isEmpty ? "waveform.circle.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(!draftVoiceNotes.isEmpty ? Color.accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)

            if viewModel.wordCount > 0 {
                HStack {
                    Text("\(viewModel.wordCount) words")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .background(.bar)
    }

    private func saveAndDismiss() {
        guard !isTranscribingVoiceNotes else { return }
        if let entry {
            if hasDraftContent {
                update(entry)
                entry.photoData = photoData
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
                entry.voiceNoteTranscript = voiceNoteTranscript
                entry.voiceNoteLanguageCode = voiceNoteLanguageCode
                entry.voiceNoteLanguageName = voiceNoteLanguageName
                entry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
                entry.additionalVoiceNoteData = additionalVoiceNoteData
                entry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
                entry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
                entry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
                entry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
                entry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
            }
        } else {
            if hasDraftContent {
                let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
                entry.photoData = photoData
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
                entry.voiceNoteTranscript = voiceNoteTranscript
                entry.voiceNoteLanguageCode = voiceNoteLanguageCode
                entry.voiceNoteLanguageName = voiceNoteLanguageName
                entry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
                entry.additionalVoiceNoteData = additionalVoiceNoteData
                entry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
                entry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
                entry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
                entry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
                entry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
                modelContext.insert(entry)
                withAnimation { showSaved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { showSaved = false }
                }
            }
        }
        dismiss()
    }

    private func saveDraft() {
        guard entry == nil, hasDraftContent, !isTranscribingVoiceNotes else { return }
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEntry = Entry(text: plain, mood: viewModel.selectedMood, source: !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed)
        savedEntry.photoData = photoData
        savedEntry.voiceNoteData = voiceNoteData
        savedEntry.voiceNoteDuration = voiceNoteDuration
        savedEntry.voiceNoteTranscript = voiceNoteTranscript
        savedEntry.voiceNoteLanguageCode = voiceNoteLanguageCode
        savedEntry.voiceNoteLanguageName = voiceNoteLanguageName
        savedEntry.voiceNoteEnglishTranslation = voiceNoteEnglishTranslation
        savedEntry.additionalVoiceNoteData = additionalVoiceNoteData
        savedEntry.additionalVoiceNoteDurations = additionalVoiceNoteDurations
        savedEntry.additionalVoiceNoteTranscripts = additionalVoiceNoteTranscripts
        savedEntry.additionalVoiceNoteLanguageCodes = additionalVoiceNoteLanguageCodes
        savedEntry.additionalVoiceNoteLanguageNames = additionalVoiceNoteLanguageNames
        savedEntry.additionalVoiceNoteEnglishTranslations = additionalVoiceNoteEnglishTranslations
        modelContext.insert(savedEntry)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        clearDraft()
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showSaved = false }
        }
    }

    private func clearDraft() {
        viewModel.text = ""
        viewModel.selectedMood = nil
        selectedPhotoItem = nil
        photoData = nil
        voiceNoteData = nil
        voiceNoteDuration = 0
        voiceNoteTranscript = nil
        voiceNoteLanguageCode = nil
        voiceNoteLanguageName = nil
        voiceNoteEnglishTranslation = nil
        additionalVoiceNoteData = []
        additionalVoiceNoteDurations = []
        additionalVoiceNoteTranscripts = []
        additionalVoiceNoteLanguageCodes = []
        additionalVoiceNoteLanguageNames = []
        additionalVoiceNoteEnglishTranslations = []
        transcribingVoiceNoteIndexes = []
    }

    private func update(_ entry: Entry) {
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = plain
        entry.wordCount = plain.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
        entry.mood = viewModel.selectedMood
        entry.source = !draftVoiceNotes.isEmpty && plain.isEmpty ? .voice : .typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func appendVoiceNote(data: Data, duration: TimeInterval) {
        let noteIndex: Int
        if voiceNoteData == nil {
            voiceNoteData = data
            voiceNoteDuration = duration
            voiceNoteTranscript = nil
            voiceNoteLanguageCode = nil
            voiceNoteLanguageName = nil
            voiceNoteEnglishTranslation = nil
            noteIndex = 0
        } else {
            additionalVoiceNoteData.append(data)
            additionalVoiceNoteDurations.append(duration)
            additionalVoiceNoteTranscripts.append("")
            additionalVoiceNoteLanguageCodes.append("")
            additionalVoiceNoteLanguageNames.append("")
            additionalVoiceNoteEnglishTranslations.append("")
            noteIndex = additionalVoiceNoteData.count
        }
        transcribeVoiceNote(data: data, index: noteIndex)
    }

    private func transcribeVoiceNote(data: Data, index: Int) {
        guard let token = KeychainManager.load() else { return }
        transcribingVoiceNoteIndexes.insert(index)
        Task {
            do {
                let result = try await VoiceTranscriptionService.transcribe(audioData: data, token: token)
                await MainActor.run {
                    applyTranscription(result, toVoiceNoteAt: index)
                    transcribingVoiceNoteIndexes.remove(index)
                }
            } catch {
                await MainActor.run {
                    transcribingVoiceNoteIndexes.remove(index)
                }
            }
        }
    }

    private func applyTranscription(_ transcription: VoiceTranscription, toVoiceNoteAt index: Int) {
        if index == 0 {
            voiceNoteTranscript = transcription.transcript
            voiceNoteLanguageCode = transcription.languageCode
            voiceNoteLanguageName = transcription.languageName
            voiceNoteEnglishTranslation = transcription.englishTranslation
        } else {
            let additionalIndex = index - 1
            guard additionalVoiceNoteData.indices.contains(additionalIndex) else { return }
            additionalVoiceNoteTranscripts[additionalIndex] = transcription.transcript
            additionalVoiceNoteLanguageCodes[additionalIndex] = transcription.languageCode
            additionalVoiceNoteLanguageNames[additionalIndex] = transcription.languageName
            additionalVoiceNoteEnglishTranslations[additionalIndex] = transcription.englishTranslation
        }
    }

    private func presentVoiceNoteSheet() {
        editorFocused = false
        isKeyboardVisible = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showVoiceInput = true
        }
    }

    private func deleteAndDismiss() {
        if let entry { modelContext.delete(entry) }
        dismiss()
    }
}


#Preview {
    NavigationStack {
        WriteView()
            .modelContainer(for: Entry.self, inMemory: true)
    }
}
