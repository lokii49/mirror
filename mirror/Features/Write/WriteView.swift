import SwiftUI
import SwiftData
import PhotosUI

private let moodLabels: [String] = ["Rough", "Low", "Okay", "Good", "Alive"]

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
    @FocusState private var editorFocused: Bool

    private var noteDate: Date { entry?.createdAt ?? Date() }
    private var hasDraftContent: Bool {
        viewModel.hasContent || photoData != nil || voiceNoteData != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                dateHeader

                if let voiceNoteData {
                    VoiceNoteAttachmentView(data: voiceNoteData, duration: voiceNoteDuration)
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
                voiceNoteData = data
                voiceNoteDuration = duration
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
                Text(viewModel.selectedMood ?? "Mood")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(viewModel.selectedMood == nil ? .secondary : Color.accentColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                viewModel.selectedMood == nil
                    ? Color(.secondarySystemFill)
                    : Color.accentColor.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mood")
        .accessibilityValue(viewModel.selectedMood ?? "Not selected")
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
            }
        }

        if entry != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Done") { saveAndDismiss() }
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
                .disabled(!hasDraftContent)
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
                    Image(systemName: voiceNoteData != nil ? "waveform.circle.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(voiceNoteData != nil ? Color.accentColor : .primary)
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
        if let entry {
            if hasDraftContent {
                update(entry)
                entry.photoData = photoData
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
            }
        } else {
            if hasDraftContent {
                let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = Entry(text: plain, mood: viewModel.selectedMood, source: voiceNoteData != nil && plain.isEmpty ? .voice : .typed)
                entry.photoData = photoData
                entry.voiceNoteData = voiceNoteData
                entry.voiceNoteDuration = voiceNoteDuration
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
        guard entry == nil, hasDraftContent else { return }
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEntry = Entry(text: plain, mood: viewModel.selectedMood, source: voiceNoteData != nil && plain.isEmpty ? .voice : .typed)
        savedEntry.photoData = photoData
        savedEntry.voiceNoteData = voiceNoteData
        savedEntry.voiceNoteDuration = voiceNoteDuration
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
    }

    private func update(_ entry: Entry) {
        let plain = viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.text = plain
        entry.wordCount = plain.split { $0.isWhitespace }.filter { !$0.isEmpty }.count
        entry.mood = viewModel.selectedMood
        entry.source = voiceNoteData != nil && plain.isEmpty ? .voice : .typed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
