import SwiftUI
import SwiftData
import Photos
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct DraftUndoSnapshot {
    var text: String = ""
    var textStyleData: Data? = nil
    var inlineStyleData: Data? = nil
    var photos: [Data] = []
    var mood: String? = nil
    var tags: [String] = []
    var voiceNoteData: Data? = nil
    var voiceNoteDuration: TimeInterval = 0
    var voiceNoteTranscript: String? = nil
    var additionalVoiceNoteData: [Data] = []
    var additionalVoiceNoteDurations: [TimeInterval] = []
    var additionalVoiceNoteTranscripts: [String] = []
}

struct WriteView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.appDisplayMode) var displayMode
    @Query(sort: \Entry.createdAt, order: .reverse) var allEntries: [Entry]

    var entry: Entry? = nil
    var autoFocus: Bool = false
    var showsBackButton: Bool = false
    var initialText: String = ""
    var onSaveComplete: (() -> Void)? = nil

    @State var viewModel = WriteViewModel()
    @State var isKeyboardVisible = false
    @State var showSaved = false
    @State var showDeleteConfirm = false
    @State var showDiscardConfirm = false
    @State var pendingDelete = false
    @State var deleteUndoTask: Task<Void, Never>? = nil
    @State var deleteCountdown: Int = 10
    @State var undoSnapshot = DraftUndoSnapshot()
    @State var showVoiceInput = false
    @State var showPhotoPicker = false
    @State var showCameraPicker = false
    @State var photoAttachError: String? = nil
    @State var isAttachingPhoto = false
    @State var photoDataArray: [Data] = []
    @State var inlineStyleData: Data? = nil
    @State var activeInlineStyles = InlineStyleSet()
    @State var showFormattingPanel = false
    @State var canUndo = false
    @State var canRedo = false
    @State var panelState = FormattingPanelState()
    @State var fullscreenPhotoIndex: Int? = nil
    @State var voiceNoteData: Data? = nil
    @State var voiceNoteDuration: TimeInterval = 0
    @State var voiceNoteTranscript: String? = nil
    @State var voiceNoteLanguageCode: String? = nil
    @State var voiceNoteLanguageName: String? = nil
    @State var voiceNoteEnglishTranslation: String? = nil
    @State var additionalVoiceNoteData: [Data] = []
    @State var additionalVoiceNoteDurations: [TimeInterval] = []
    @State var additionalVoiceNoteTranscripts: [String] = []
    @State var additionalVoiceNoteLanguageCodes: [String] = []
    @State var additionalVoiceNoteLanguageNames: [String] = []
    @State var additionalVoiceNoteEnglishTranslations: [String] = []
    @State var transcribingVoiceNoteIndexes: Set<Int> = []
    @State var failedTranscriptionIndexes: Set<Int> = []
    @AppStorage("transcriptionLanguage") var transcriptionLanguage: String = ""
    @State var isDetectingMood = false
    @State var recPulse = false
    @State var showSignalPanel = false
    @State var pendingTextCommand: NoteTextCommand?
    @State var textCommandRevision = 0
    @State var activeParagraphStyle: NoteParagraphTextStyle = .body
    @State var entryDate: Date = Date()
    @State var showDatePicker = false
    @State var focusMode = false
    @State var entryTags: [String] = []
    @State var entryFontChoiceRaw: String = WritingFontChoice.system.rawValue
    @State var tagText: String = ""
    @State var showTagInput = false
    @State var existingTagSuggestions: [String] = []
    @AppStorage("dailyWordGoal") var dailyWordGoal: Int = 200
    @FocusState var editorFocused: Bool
    @FocusState var tagFieldFocused: Bool

    var noteDate: Date { entryDate }
    var hasDraftContent: Bool {
        viewModel.hasContent || !photoDataArray.isEmpty || !draftVoiceNotes.isEmpty
    }
    var isTranscribingVoiceNotes: Bool {
        !transcribingVoiceNoteIndexes.isEmpty
    }
    var draftVoiceNotes: [(data: Data, duration: TimeInterval, transcript: String?, languageName: String?, englishTranslation: String?)] {
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
            if displayMode == .sentinel {
                MirrorTheme.inkBase.ignoresSafeArea()
                SentinelGridBackground().ignoresSafeArea()
            } else {
                MirrorTheme.inkMid.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if !focusMode { dateHeader }

                if !focusMode {
                    tagsBar
                }

                if !draftVoiceNotes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(draftVoiceNotes.indices, id: \.self) { index in
                            let note = draftVoiceNotes[index]
                            VoiceNoteAttachmentView(
                                data: note.data,
                                duration: note.duration,
                                title: String(localized: "Voice note \(index + 1)"),
                                transcript: note.transcript,
                                languageName: note.languageName,
                                isTranscribing: transcribingVoiceNoteIndexes.contains(index),
                                transcriptionFailed: failedTranscriptionIndexes.contains(index),
                                onDelete: { removeVoiceNote(at: index) },
                                onRetryTranscription: { transcribeVoiceNote(data: note.data, index: index) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                NoteEditorTextView(
                    text: $viewModel.text,
                    textStyleData: $viewModel.textStyleData,
                    inlineStyleData: $inlineStyleData,
                    photoDataArray: $photoDataArray,
                    command: $pendingTextCommand,
                    commandRevision: $textCommandRevision,
                    isFocused: Binding(
                        get: { editorFocused },
                        set: { editorFocused = $0 }
                    ),
                    activeParagraphStyle: $activeParagraphStyle,
                    activeInlineStyles: $activeInlineStyles,
                    showFormattingPanel: $showFormattingPanel,
                    canUndo: $canUndo,
                    canRedo: $canRedo,
                    fontChoiceRaw: $entryFontChoiceRaw,
                    panelState: panelState,
                    displayMode: displayMode,
                    onPhotoTapped: { idx in fullscreenPhotoIndex = idx }
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.bar, in: Capsule())
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    .transition(.scale(scale: 0.85).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.7)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if isAttachingPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.secondary)
                    Text("Attaching photo…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.bar, in: Capsule())
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if pendingDelete {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Entry will be deleted")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text("\(deleteCountdown)s")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.easeInOut(duration: 0.3), value: deleteCountdown)
                    Button("Undo") {
                        cancelPendingDelete()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if displayMode == .sentinel {
                ViewfinderCorners(inset: 4, length: 18)
                    .padding(.top, 50)
                    .padding(.bottom, 96)
                    .padding(.horizontal, 4)
            }
        }
        .overlay {
            if showSignalPanel {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { showSignalPanel = false } }
                    .overlay(alignment: .topTrailing) {
                        signalPanel
                            .padding(.top, 96)
                            .padding(.trailing, 18)
                    }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems; focusModeToolbarItem }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if (isKeyboardVisible || editorFocused) && !focusMode {
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
                photoDataArray = entry.photoDataArray
                inlineStyleData = entry.inlineStyleData
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
                if entry.voiceNoteTranscriptionFailed && entry.voiceNoteData != nil {
                    failedTranscriptionIndexes.insert(0)
                }
            }
            entryDate = entry?.createdAt ?? Date()
            entryTags = entry?.tags ?? []
            entryFontChoiceRaw = entry?.fontChoice ?? WritingFontChoice.system.rawValue
            if entry == nil {
                restoreDraftFromStorage()
                if !initialText.isEmpty && viewModel.text.isEmpty {
                    viewModel.text = initialText
                }
            }
            panelState.onCommand = { cmd in applyTextCommand(cmd) }
            panelState.onDismiss = { showFormattingPanel = false }
            panelState.fontChoiceRaw = entryFontChoiceRaw
            if autoFocus || entry != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    editorFocused = true
                }
            }
            if displayMode == .sentinel {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    recPulse = true
                }
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            NativePhotoPicker { result in
                handlePickedPhoto(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPickerController { result in
                handlePickedPhoto(result)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(
            get: { fullscreenPhotoIndex.map { IdentifiableIndex(value: $0) } },
            set: { fullscreenPhotoIndex = $0?.value }
        )) { item in
            if item.value < photoDataArray.count {
                FullscreenPhotoView(photoData: photoDataArray[item.value])
                    .environment(\.appDisplayMode, displayMode)
            }
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
                appendVoiceNote(data: data, duration: duration)
            }
            .environment(\.appDisplayMode, displayMode)
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack(spacing: 0) {
                    DatePicker(
                        "Entry date",
                        selection: $entryDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                    Divider()
                    DatePicker(
                        "Entry time",
                        selection: $entryDate,
                        in: ...Date(),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal)
                }
                .navigationTitle("Entry Date & Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: viewModel.text) { _, _ in
            if entry == nil { saveDraftToStorage() }
        }
        .onChange(of: showTagInput) { _, open in
            if open { computeTagSuggestions() }
        }
        .onChange(of: viewModel.selectedMood) { _, _ in
            if entry == nil { saveDraftToStorage() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, entry == nil { saveDraftToStorage() }
        }
    }

}

#Preview {
    NavigationStack {
        WriteView()
            .modelContainer(for: Entry.self, inMemory: true)
    }
}
