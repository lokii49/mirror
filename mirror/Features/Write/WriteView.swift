import SwiftUI
import SwiftData
import Combine
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

    /// iPad presents the formatting panel as a popover off the Aa button;
    /// iPhone as an overlay above the keyboard. Keyed off the idiom, not
    /// `horizontalSizeClass` — inside a NavigationSplitView detail pane the
    /// class reports `.compact` on iPad, which sent it down the iPhone path.
    var usesPopoverPanel: Bool { UIDevice.current.userInterfaceIdiom == .pad }

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
    @State var draftSaveTask: Task<Void, Never>? = nil
    // "Keep writing" follow-up (writing-roadmap.md 1.2) — entirely ephemeral, never
    // persisted, never part of the draft/entry text unless the user explicitly taps it in.
    @State var followUpTask: Task<Void, Never>? = nil
    @State var followUpQuestion: String? = nil
    @State var followUpEngine: LLMEngine? = nil
    @State var followUpWordCountAtLastCheckpoint: Int = 0
    /// Hash of an existing entry's content as loaded, so saveAndDismiss can skip
    /// the write (and CloudKit modification) when the entry was only opened to read.
    @State var loadedContentHash: Int = 0
    @State var voiceRecorder = VoiceInputManager()
    @State var isRecordingInline = false
    @State var recordingPermissionDenied = false
    @State var showPhotoPicker = false
    @State var showCameraPicker = false
    @State var photoAttachError: String? = nil
    @State var showDocumentScanner = false
    @State var isScanningText = false
    @State var textScanError: String? = nil
    @State var showTalkItOut = false
    @State var showTalkItOutPaywall = false
    @State var talkItOutUnavailableMessage: String? = nil
    @State var isAttachingPhoto = false
    @State var photoDataArray: [Data] = []
    @State var inlineStyleData: Data? = nil
    @State var activeInlineStyles = InlineStyleSet()
    @State var showFormattingPanel = false
    /// Long-press on the mic button (audit 2.3) — the app's own mic only
    /// leads to a post-hoc-transcribed voice memo; live word-by-word
    /// dictation exists (the system keyboard's mic key) but nothing in the
    /// app ever points to it. Rather than inventing a new coach-mark system
    /// for one button, or building in-app streaming recognition (the L-effort
    /// option), this makes the existing distinction discoverable in place.
    @State var showVoiceButtonHint = false
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
    /// Why each index in `failedTranscriptionIndexes` failed — e.g. "This
    /// language isn't available for offline transcription on this device."
    /// vs. a generic "Transcription failed." Absent for an index means either
    /// it hasn't failed, or it was inferred as failed on reopen
    /// (`markPendingNotesForRetry()`) with no real error to report — falls
    /// back to the existing generic copy in that case (audit 2.4).
    @State var transcriptionFailureMessages: [Int: String] = [:]
    @State var transcriptionTasks: [Int: Task<Void, Never>] = [:]
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
    @State var showLinkEditor = false
    @State var linkEditorURLText = ""
    @State var linkEditorHasExisting = false
    @AppStorage("dailyWordGoal") var dailyWordGoal: Int = 200
    @FocusState var editorFocused: Bool
    @FocusState var tagFieldFocused: Bool

    /// Drives the inline voice-recording timer; the handler no-ops unless
    /// `isRecordingInline`.
    let recElapsedTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

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

            // The whole write surface scrolls as one — header, tags, voice notes
            // and the editor. Scrolling up past the voice notes brings the editor
            // with it; the editor itself doesn't scroll (it grows to fit its text,
            // see NoteEditorTextView.sizeThatFits).
            ScrollView {
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
                                    transcriptionFailureMessage: transcriptionFailureMessages[index],
                                    onDelete: { removeVoiceNote(at: index) },
                                    onRetryTranscription: { transcribeVoiceNote(data: note.data, index: index) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if isRecordingInline {
                        InlineRecordingRow(
                            elapsed: voiceRecorder.elapsed,
                            onStop: { finishInlineRecording() },
                            onCancel: { cancelInlineRecording() }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if recordingPermissionDenied {
                        MicPermissionNotice { recordingPermissionDenied = false }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // "Talk it out" starter (writing-roadmap.md Tier 2) — only on a genuinely
                    // blank new entry. Disappears the instant there's any content, since at
                    // that point the user is already writing and doesn't need a starter.
                    if entry == nil && !hasDraftContent && !focusMode {
                        TalkItOutChip { presentTalkItOut() }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .transition(.opacity)
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
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)

            if showSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MirrorTheme.green)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(MirrorTheme.inkMid, in: Capsule())
                    .overlay { Capsule().stroke(MirrorTheme.inkBorder, lineWidth: 1) }
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
                .background(MirrorTheme.inkMid, in: Capsule())
                .overlay { Capsule().stroke(MirrorTheme.inkBorder, lineWidth: 1) }
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if isScanningText {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.secondary)
                    Text("Recognizing text…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(MirrorTheme.inkMid, in: Capsule())
                .overlay { Capsule().stroke(MirrorTheme.inkBorder, lineWidth: 1) }
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
                .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MirrorTheme.inkBorder, lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let followUpQuestion, !focusMode, !pendingDelete, !showSaved, !isAttachingPhoto, !isScanningText, !showFormattingPanel {
                FollowUpChip(
                    question: followUpQuestion,
                    engine: followUpEngine,
                    onUse: { useFollowUpQuestion() },
                    onDismiss: { dismissFollowUp() }
                )
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
            }
            entryDate = entry?.createdAt ?? Date()
            entryTags = entry?.tags ?? []
            entryFontChoiceRaw = entry?.fontChoice ?? WritingFontChoice.system.rawValue
            if entry == nil {
                // Real bug, found on-device (0.1's widget prompt, 0.2's templates, and Tier 2's
                // "Talk it out" all hit this): restoring an unrelated leftover autosaved draft
                // used to run unconditionally, before this check — so any stale draft sitting
                // in UserDefaults from an earlier, unrelated Write session silently won over an
                // explicit initialText request, sometimes producing a blank/wrong editor for no
                // visible reason ("sometimes seeing blank screen after talk it out questions").
                // When a caller explicitly asks for specific starting text, that intent wins
                // outright — the stale draft is left untouched in storage (not cleared, no data
                // loss), just not loaded into this particular prefilled session.
                if initialText.isEmpty {
                    restoreDraftFromStorage()
                } else if viewModel.text.isEmpty {
                    viewModel.text = initialText
                }
                // A restored draft only persists audio, not transcripts — decode
                // anything still missing one. Rare, and there's no saved entry to
                // spuriously dirty.
                rekickPendingTranscriptions()
            } else {
                // Opening a saved entry: surface a Retry for any note with audio
                // but no transcript (including notes that failed on an older
                // build, where only the first note's failure was recorded).
                // Don't auto-decode here — that would set isTranscribingVoiceNotes
                // and disable Save on every open.
                markPendingNotesForRetry()
            }
            loadedContentHash = currentContentHash()
            panelState.onCommand = { cmd in applyTextCommand(cmd) }
            panelState.onRequestLinkEditor = {
                linkEditorURLText = panelState.activeLinkURL ?? ""
                linkEditorHasExisting = panelState.activeLinkURL != nil
                showLinkEditor = true
            }
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
        .sheet(isPresented: $showDocumentScanner) {
            DocumentScannerController { result in
                handleScannedPages(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showTalkItOut) {
            NavigationStack {
                TalkItOutView(
                    onFinish: { composed in
                        appendTalkItOutText(composed)
                        showTalkItOut = false
                    },
                    onCancel: { showTalkItOut = false }
                )
                .navigationTitle(displayMode == .sentinel ? "COMMS" : "Talk it out")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTalkItOut = false }
                    }
                }
            }
            .environment(\.appDisplayMode, displayMode)
        }
        .sheet(isPresented: $showTalkItOutPaywall) {
            PaywallView(initialTier: .core)
                .environment(\.appDisplayMode, displayMode)
        }
        .alert("Not ready yet", isPresented: Binding(
            get: { talkItOutUnavailableMessage != nil },
            set: { if !$0 { talkItOutUnavailableMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(talkItOutUnavailableMessage ?? "")
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
        .alert("Scan not added", isPresented: Binding(
            get: { textScanError != nil },
            set: { if !$0 { textScanError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(textScanError ?? "")
        }
        .alert(linkEditorHasExisting ? "Edit Link" : "Add Link", isPresented: $showLinkEditor) {
            TextField("https://example.com", text: $linkEditorURLText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") { applyTextCommand(.link(url: linkEditorURLText)) }
            if linkEditorHasExisting {
                Button("Remove Link", role: .destructive) { applyTextCommand(.link(url: nil)) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onReceive(recElapsedTimer) { _ in
            if isRecordingInline { voiceRecorder.refreshElapsed() }
        }
        .onChange(of: voiceRecorder.isRecording) { _, recording in
            // Recorder stopped itself (interruption, route change, 10-min cap) —
            // finalize the note we have.
            if !recording && isRecordingInline { finishInlineRecording() }
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
            if entry == nil { scheduleDraftSave() }
            scheduleFollowUpCheck()
        }
        .onChange(of: showTagInput) { _, open in
            if open { computeTagSuggestions() }
        }
        .onChange(of: editorFocused) { _, focused in
            // When the editor fully loses focus (keyboard/panel dismissed), drop
            // the panel state so it doesn't reopen on the next focus.
            if !focused { showFormattingPanel = false }
        }
        .onChange(of: viewModel.selectedMood) { _, _ in
            if entry == nil { flushDraftSave() }
        }
        .onChange(of: photoDataArray) { _, _ in
            if entry == nil { saveDraftAttachments() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, entry == nil { flushDraftSave() }
        }
        .onDisappear {
            cancelDraftSave()
            followUpTask?.cancel()
            followUpTask = nil
            if isRecordingInline { voiceRecorder.discardRecording() }
        }
    }

}

#Preview {
    NavigationStack {
        WriteView()
            .modelContainer(for: Entry.self, inMemory: true)
    }
}
