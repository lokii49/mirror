# WriteView Audit — current state vs. Apple Notes

Date: 2026-09-09. Scope: `Features/Write/` (WriteView + subviews, `NoteEditorTextView`, the Aa
formatting panel) and the voice recording / transcription path (`VoiceInputManager`,
`VoiceInputSheet`, `VoiceTranscriptionService`, `WriteView+VoiceNotes`).

Benchmark: Apple Notes. The bar is "typing, formatting, and dictation feel as solid and
predictable as Notes," not "match every Notes feature."

**This document is an audit only. Nothing here has been changed.** Fixes are sketched, not
applied.

---

## Scope call — Notes features we are deliberately NOT chasing

A journaling app does not need most of what Notes' editor carries. Explicitly out of scope:

| Notes feature | Verdict |
|---|---|
| Tables | Out. No journaling use. |
| Drawing / handwriting / Apple Pencil | Out. |
| Document scanning, photo markup | Out. Photo attach already exists; markup is not journaling. |
| Collaboration / shared notes | Out — CLAUDE.md bans social/sharing forever. |
| Note links, tags-as-links, folders | Out for now (folders are Phase 2 per CLAUDE.md). |
| Attach PDF / arbitrary files | Out. |

**In scope and worth adding** (small, high-value for journaling prose):
- **Block quote** paragraph style — natural for quoting others / past selves. Cheap: one more
  case alongside `.monospaced` in `NoteParagraphTextStyle` + panel button.
- **Inline link** (URL on selected text) — Notes supports it; low effort, occasionally wanted.
- Everything else below is about making the editor we already have behave correctly.

> **STATUS — Block quote shipped on `2.1.1`; inline link scoped and deferred, not attempted.**
>
> **Block quote**: added `.blockQuote` to `NoteParagraphTextStyle` and `NoteTextCommand`,
> `NoteEditorTextView.attributes(for:)` (16pt head/first-line indent, `UIColor.secondaryLabel`,
> body font — deliberately **not** italic: baking italic into the paragraph style's own font
> would fight the Italic inline toggle, which reads/writes `.traitItalic` on the rendered font
> directly via `applyInlineStyles`/`isStyleApplied` — a quoted paragraph would make the "I"
> button read as falsely active, and toggling it off would silently strip the quote's font
> trait), the Return-key single-block-reset condition, and `paragraphStyle(for command:)`. New
> "Quote" button added to the Aa panel's Row 1 (already horizontal-scrolling from the 2.5 fix).
> `staticListMarkerPrefix` correctly falls through its `default: nil` — no list marker.
>
> Also fixed a parity gap the first pass missed: `EntryDetailView.styledText(for:at:)` — the
> **read-only** entry view, which has its own if/else style→font mapping rather than reusing the
> editor's — had no `.blockQuote` branch, so a quoted paragraph would render correctly while
> typing but silently lose its styling (fall through to plain body) the moment the entry was
> reopened for reading. Added a matching branch there (secondary color + 16pt leading padding,
> same non-italic treatment). `SampleData.swift`'s `NoteParagraphTextStyle` usages are literal
> arrays, not exhaustive switches — nothing to add there.
>
> Verified: `xcodebuild build` green, `xcodebuild build-for-testing` green, `mirrorTests`
> 205/205 (was 199/199 before this item). Added `blockQuoteIsMutedAndIndentedButNotItalic`,
> `blockQuoteRoundTripsThroughEncodedTextStyleData` (Codable-level — the interactive
> `apply(.blockQuote, ...)` toolbar path needs `textView.isFirstResponder`, which this file's
> headless harness cannot simulate, per its own documented scope), and added `.blockQuote` to
> the existing `titleHeadingSubheadingHaveNoMarker` and
> `headingSubheadingTitleMonoResetTypingToBodyOnReturn` loops. Not verified on-device or via
> UI test (environment instability this session — see 2.3's STATUS block).
>
> **Inline link — scoped, explicitly deferred, not started.** Not actually "low effort" as
> originally guessed: needs (1) a URL-entry UI on a text selection (prompt/alert/sheet — no
> existing pattern in this codebase to reuse), (2) new persisted storage — `InlineStyleRange`
> today only carries bold/italic/underline/strikethrough/highlightIndex, so a link is a stored-
> format change, not an additive enum case like block quote was, and (3) tap handling that
> doesn't collide with the checklist marker's existing tap gesture (`handleTap`/`FakeTap` in
> `FormattingCombinationTests.swift`). Left for a dedicated follow-up.

---

## Group 1 — Data loss & correctness (fix first)

These lose or corrupt user content. In an app whose entire pitch is "your data is always
yours," these outrank every polish item.

> **STATUS — all of Group 1 fixed** on branch `writeview-group1-fixes` (off `2.1.1`), 8 commits
> (7 fixes + 1 review pass), `xcodebuild build-for-testing` green, `mirrorTests` green except 4
> `ThemeExtractionServiceTests` that fail identically on the base commit `82c4e39` (`NaturalLanguage`
> model drift, unrelated — verified in a worktree).
> **No CloudKit schema change** — nothing here touches the SwiftData model, so it's mergeable
> without a Console "Deploy Schema Changes" pass.
> - 1.1 + 1.5 → `4036337` — transcription keyed by retained `Task`, cancel-all + re-kick on delete, self-heal on open
> - 1.2 → `6aadb3f` — `DraftAttachmentStore`, encrypted photo/voice blobs in Application Support
> - 1.3 → `384de4c` + review pass — save an emptied entry, but skip the write (and CloudKit modification) when an entry was only opened to read
> - 1.4 → `7222109` — 25s timeout per recognition pass, cancellation-aware `recognize()`;
>   `+ 55dd2c3` — save-anyway while transcribing, full STATUS block below
> - 1.6 → `9c8c1c8` — real duration, `AVAudioRecorderDelegate`, interruption/route observers, 10-min cap
> - 1.7 → `503d930` — `AVAudioPlayerDelegate`, single `active` player
> - 1.8 → `beb0576` — debounced draft autosave
>
> **1.4 "Save anyway" while transcribing** — now also fixed, on `2.1.1` directly (see STATUS
> block under 1.4 below). **Sentinel "REC" pulse** (`WriteView+Subviews.swift:62`) assessed —
> it's ambient chrome, never wired to recording state, so no change made.

### 1.1 Deleting a voice note reassigns an in-flight transcript to the wrong audio
`WriteView+VoiceNotes.swift:64` (`removeVoiceNote(at:)`), `:27` (`transcribeVoiceNote`).

`transcribeVoiceNote` keys its result by a fixed `index` captured at call time and stored in
`transcribingVoiceNoteIndexes` / `failedTranscriptionIndexes`. `removeVoiceNote(at: 0)`
promotes `additionalVoiceNoteData.removeFirst()` into the primary slot, shifting every
remaining note down one position — but never reindexes the two index sets, and no `Task`
handle is retained, so the running transcription cannot be cancelled.

Failure: notes `[P, A, B]`, `A` transcribing with `index: 1`. User deletes `P`. `A` becomes
primary (index 0), `B` shifts to index 1. `A`'s task completes → `applyTranscription(result,
toVoiceNoteAt: 1)` writes **A's transcript onto B**. Entry saves and CloudKit-syncs the wrong
text. The AI then reflects on `B` using `A`'s words.

Fix: give each voice note a stable identity (UUID) instead of a positional index; store
`[UUID: Task]` and cancel on delete; key transcript application by UUID. This is the root
cause of 1.5 too.
Effort: M. Sentinel parity: N/A (logic).

### 1.2 Draft autosave silently drops photos and voice notes
`WriteView+Actions.swift:246` (`saveDraftToStorage`), `:256` (`restoreDraftFromStorage`).

`hasDraftContent` (`WriteView.swift:93`) counts `photoDataArray` and `draftVoiceNotes`, but
`saveDraftToStorage` persists only text, textStyleData, inlineStyleData, mood, tags.
`onChange(of: scenePhase == .background)` calls it. So: attach a photo or record 40s of
audio, get a phone call / app killed → the attachment is gone, with no indication it ever
existed. Notes never loses an attachment mid-edit.

Fix: persist photo data + voice note data/durations/transcripts to the draft store (they are
already `Data`; encrypt like the text). Or, cheaper and arguably better: auto-materialize a
real `Entry` as soon as there is any attachment, and edit that (Notes' model — every note is
always saved).
Effort: M. Sentinel parity: N/A.

### 1.3 Emptying an existing entry's text discards the edit
`WriteView+Actions.swift:20` — `saveAndDismiss`, the `entry != nil` branch is wrapped in
`if hasDraftContent { … }` then falls through to `dismiss()`.

Open an existing entry, select all, delete, tap the save checkmark. `hasDraftContent` is
false, so `update(entry)` never runs and the cleared text is never written. The user thinks
they saved an empty entry; reopening shows the old text. Either persist the empty state or
prompt "delete this entry?" — Notes deletes an emptied note. Silently reverting is the one
thing not to do.
Effort: S. Sentinel parity: N/A.

### 1.4 An entry can become unsaveable — transcription has no timeout
`WriteView+Subviews.swift:316,351` — save button `.disabled(isTranscribingVoiceNotes)`.
`VoiceTranscriptionService.swift:104` (`recognize`) — the continuation only resumes on
`error` or `result.isFinal`.

`SFSpeechRecognitionTask` can stall without ever delivering a final result or an error
(bad audio, recognizer wedged). `transcribingVoiceNoteIndexes` never clears → the save
button is disabled forever → the user cannot save the entry and cannot tell why.

Fix: wrap `recognize` in a timeout (e.g. `Task` + `withThrowingTaskGroup` racing a
`Task.sleep`, cancel the recognition task on timeout → treated as failed → retry button
shown). Separately, allow "Save anyway" while transcribing (transcript can fill in later /
be retried from the entry).
Effort: M. Sentinel parity: copy already exists for both themes.

> **STATUS — "Save anyway" half fixed on `2.1.1` directly** (timeout half was already done —
> `7222109`, 25s cap + cancellation-aware `recognize()`, see Group 1 header). This closes the
> remaining gap: the Save buttons no longer disable while a voice note is transcribing.
>
> Root cause matched 1.1/1.5's class exactly: `applyTranscription(_:toVoiceNoteAt:)` writes
> into this view's own `@State`, keyed by a positional index. Saving mid-transcription either
> dismisses the view (existing entry) or resets the draft to a blank one (new entry) — either
> way the in-flight task's eventual write lands nowhere anyone reads, or worse, onto whatever
> a fresh draft's note ends up at the same index.
>
> Fix: `continueTranscriptionAfterSaveAnyway(for:in:)` (`WriteView+VoiceNotes.swift`) cancels
> every `@State`-bound transcription task still running at save time and restarts each one
> from scratch as a self-contained `Task` that captures the persisted `Entry` + `ModelContext`
> directly — independent of this view's lifecycle. It writes through a new `static func
> applyTranscription(_:to:atIndex:)` (no `self` capture; unit-testable without a mic or a live
> `WriteView`) instead of the `@State`-targeting original. This restarts the pass rather than
> handing off the in-flight one — accepted: `VoiceTranscriptionService` serializes passes
> behind its own semaphore, so it costs at most one extra ~25s-capped pass, and avoids ever
> having two writers (the dismissed view's dying task, the new self-contained one) racing on
> the same index. On failure, index-0 sets `entry.voiceNoteTranscriptionFailed`; an
> additional-note failure isn't a stored flag (matches the live path) — `markPendingNotesForRetry()`
> infers it from empty-transcript + present-audio the next time the entry reopens. Wired into
> both `saveAndDismiss()` (existing-entry branch, plus the new-entry branch for defensive
> consistency) and `saveDraft()`, before either function's draft/task cleanup. Removed
> `.disabled(isTranscribingVoiceNotes)` from both Save buttons in `WriteView+Subviews.swift`.
>
> **Guard-order fix, caught by advisor before commit**: the handoff call in
> `saveAndDismiss()` originally sat *after* two early-return guards
> (`!entry.textDecryptionFailed`, `currentContentHash() != loadedContentHash`). A Retry-
> triggered transcription on an already-saved entry (tap Retry on a `voiceNoteTranscriptionFailed`
> entry, then Save before it resolves) changes neither of those — the transcript hasn't
> landed yet — so the content-hash guard would fire and dismiss before the handoff ever ran,
> reproducing the exact bug on the one path Retry exists for. Moved the handoff to the top of
> the `if let entry` block, before both guards.
>
> **Follow-on regression from that move, also caught by advisor**: moving the handoff earlier
> also moved it ahead of `entry.voiceNoteTranscriptionFailed = … && failedTranscriptionIndexes
> .contains(0)` — but the handoff's last step is `failedTranscriptionIndexes.removeAll()`. Net
> effect: saving while *any* note was transcribing would always write `false` to the flag,
> even for an unrelated note (e.g. index 0) that was already known-failed and just waiting on
> a Retry that hadn't resolved yet — silently dropping its "AI won't reflect on this" state.
> Fixed by snapshotting `failedTranscriptionIndexes` into a local `failedAtSave` right before
> the handoff runs, and reading that snapshot instead. `saveDraft()` and the new-entry branch
> of `saveAndDismiss()` both already assign the flag before their own handoff call, so they
> needed no change — verified by re-reading both after the fix.
>
> **Unit test added**: `mirrorTests/VoiceNoteTranscriptionTests.swift`, 4 cases covering
> `WriteView.applyTranscription(_:to:atIndex:)`'s index arithmetic directly (index 0 → primary
> fields only; index N → `additionalIndex N-1` only, siblings untouched; index 0 with no
> primary audio is a no-op; an out-of-range additional index is a no-op). Made the function
> `static` specifically to enable this — no mic, no live `WriteView` needed.
>
> Drive-by fix, not part of 1.4 itself: `saveDraft()` was missing the
> `savedEntry.voiceNoteTranscriptionFailed = …` assignment that both branches of
> `saveAndDismiss()` already had — added for parity.
>
> Known limitation, not fixed here: `autoDetectMoodIfNeeded(for:)` runs at save time with the
> transcript still empty, and `backfillMissingMoodsIfNeeded` only targets entries with
> `encryptedMood == nil` — so a mood inferred from a voice-only entry's text won't be
> recomputed once the transcript lands after a "save anyway". Pre-existing gap, out of scope
> for 1.4.
>
> Verified: `xcodebuild build` green, `build-for-testing` green (iPhone 17 sim, iOS 26.5),
> `mirrorTests` 190/190 green (`xcrun xcresulttool get test-results summary` confirms
> `"failedTests": 0`, `"totalTestCount": 190`, including the 4 new
> `VoiceNoteTranscriptionTests` cases individually confirmed `"Passed"` via `xcresulttool get
> test-results tests`). **Not** exercised end-to-end in `mirrorUITests` — the simulator has no
> real mic (see `testVoice_micButton_recordsInlineWithoutModal`'s existing limitation), so the
> record → save-anyway → transcript-lands-on-the-persisted-entry flow is device-only and
> unverified beyond code review + the unit-level index-arithmetic coverage above.

### 1.5 Transcription failure on notes 2+ is never persisted
`WriteView.swift:297` and `WriteView+Actions.swift:39,72` only ever track index 0
(`failedTranscriptionIndexes.contains(0)` → `entry.voiceNoteTranscriptionFailed`).
`WriteView.swift:297` re-inserts only index 0 on `onAppear`.

Record two notes; second fails to transcribe. Save. Reopen the entry: the failed note shows
no error, no Retry button, and `insightContext` silently omits it — the AI never reads that
audio and the user is never told. Only the *first* voice note gets the "AI won't reflect on
this" warning treated as durable.

Fix: store a per-note failed flag (array or, with the UUID model from 1.1, a set of failed
UUIDs) on `Entry`; rehydrate all of them in `onAppear`.
Effort: M (S if folded into 1.1). Sentinel parity: N/A.

### 1.6 Recording duration is wall-clock, not audio time; interruptions corrupt it
`VoiceInputManager.swift:96` — `duration = max(elapsed, recorder?.currentTime ?? 0)` runs
*after* `recorder?.stop()`, at which point `currentTime` is 0. So `duration` is always
`elapsed`, which is `Date().timeIntervalSince(startedAt)` computed by a `Timer.publish` that
lives **inside `VoiceInputSheet`** (`WriteView+VoiceNotes` / `VoiceInputSheet:309`).

Consequences:
- If the sheet's timer stalls (scroll, background) the displayed and stored duration drift
  from the actual audio length.
- `VoiceInputManager` declares `AVAudioRecorderDelegate` conformance but implements none of
  it — no `audioRecorderDidFinishRecording`, no `audioRecorderEncodeErrorDidOccur`.
- No `AVAudioSession` interruption or route-change observer. Incoming call during recording:
  the recorder stops, `isRecording` stays `true`, `elapsed` keeps counting wall-clock, the
  UI still shows a running timer over dead audio.
- No max duration and no free-disk check — a forgotten recording grows unbounded.

Fix: read `recorder.currentTime` *before* `stop()`, or capture the file's real duration via
`AVAudioPlayer(contentsOf:).duration` / `AVURLAsset` after finishing. Implement the delegate
callbacks. Observe `AVAudioSession.interruptionNotification` and
`routeChangeNotification`. Cap at ~10 min with a visible countdown.
Effort: M. Sentinel parity: timer/status UI exists in both themes; check the "REC" pulse in
`dateHeader` (`WriteView+Subviews.swift:62`) still reflects reality after an interruption.

### 1.7 Playback button sticks on "pause"; two notes can play at once
`VoiceInputManager.swift:113` (`VoiceNotePlayer`).

No `AVAudioPlayerDelegate`, so `audioPlayerDidFinishPlaying` is never received and
`isPlaying` never returns to `false` — the button shows "pause" indefinitely after a note
finishes. Each `VoiceNoteAttachmentView` owns its own `VoiceNotePlayer`
(`VoiceInputManager.swift:155`), so with multiple notes you can start two playing
simultaneously, and one's `stop()` calls
`AVAudioSession.setActive(false, …)` out from under the other.

Fix: add the delegate, reset `isPlaying` on finish; hoist to a single shared player
(environment object) so starting one stops the others; don't deactivate the session while
another note is mid-playback.
Effort: S. Sentinel parity: play/pause glyph is shared.

### 1.8 Encrypt-per-keystroke on the draft path
`WriteView.swift:391` — `onChange(of: viewModel.text)` → `saveDraftToStorage()` →
`MirrorEncryption.encryptString(<entire document>)` + `JSONEncoder` over the tag array, on
**every character typed** in a new entry.

For a long entry this is measurable input latency and battery. Notes writes incrementally
and off the keystroke path.

Fix: debounce the draft save (~0.75–1.5s of idle, plus an immediate flush on
`scenePhase == .background` and on nav away). The background flush already exists at
`WriteView.swift:400`.
Effort: S. Sentinel parity: N/A. **Best latency win outside the editor internals.**

---

## Group 2 — Structural gaps vs. Notes (the "does it feel like Notes" items)

> **STATUS — merged to `2.1.1` (2026-09-10, merge `fcc9164`). Build green. 2.1 + 2.2
> code-complete; user verifying by hand.**
>
> **2.1 — RESOLVED as an iPad-only fix.** The original complaint ("panel replaces the
> keyboard") stands *by design* on iPhone. Final mechanism (`5ef6587`, the last commit to
> touch this — supersedes the earlier `c241eb5` / `1f757f5` overlay attempt this block used
> to describe):
> - **iPhone** — panel is the text view's `inputView` (`NoteEditorTextView.swift:2403`,
>   `usesInputView = idiom == .phone`). Keyboard is *visually swapped* for the panel but the
>   text view keeps first responder, so the selection survives and typing resumes the instant
>   the panel closes. This is the Apple Notes model — a panel stacked over a live keyboard
>   leaves no room for the editor on a phone. The earlier "resign keyboard, panel below the
>   toolRow" overlay was reverted: resigning first responder dropped the selection so tools
>   couldn't act on it, and re-focusing was racy.
> - **iPad** — `.popover` off the Aa button (`WriteView+Subviews.swift:448`), keyboard never
>   touched. `usesPopoverPanel = idiom == .pad` (keyed off idiom, *not* `horizontalSizeClass`
>   — WriteView sits in a `NavigationSplitView` detail pane which reports `.compact` on iPad).
> - `FormattingPanelView` gained `Presentation { .sheet, .popover }` — `.sheet` scrolls + shows
>   a grabber (iPhone inputView), `.popover` is bare (iPad supplies its own chrome).
> - User to verify by hand: iPhone Aa swaps keyboard↔panel, second Aa / tap-into-editor brings
>   the keyboard back, formatting acts on the current selection; iPad popover stays up and
>   doesn't drop the keyboard; caret moving between Body/Heading updates the panel highlight.
>
> **2.2** (`58b45d8`): mic button records **inline** — `InlineRecordingRow`
> (`VoiceInputManager.swift:413`: elapsed / waveform / Stop / Cancel) renders where the
> finished note lands (`WriteView.swift:187`), keyboard + caret stay put.
> `startInlineRecording` / `finishInlineRecording` / `cancelInlineRecording`
> (`WriteView+VoiceNotes.swift:167`) are permission-gated; recorder self-stops (interruption,
> 10-min cap) are finalized via `onChange(of: voiceRecorder.isRecording)`
> (`WriteView.swift:411`). `VoiceInputSheet` and the modal plumbing deleted
> (compiler-confirmed). Mic-denied shows `MicPermissionNotice` inline.
> User to verify by hand: record → row appears, keyboard stays → Stop → note attaches +
> transcribes; Cancel discards; a call mid-recording finalizes cleanly (device only).
>
> **Debt still live after the 2.1 decision** (the reverted overlay design had been assumed to
> close these):
> - **2.5** — iPhone panel height is still the hardcoded `CGRect(... height: 346)` at
>   `NoteEditorTextView.swift:2426`. Clips on SE / landscape / large Dynamic Type. The `.popover`
>   branch self-sizes, so 2.5 is now iPhone-only + the `@ScaledMetric` pass on the fixed
>   `.system(size:)` / 44–50pt button frames inside `FormattingPanelView`. **Now has a
>   reproducible symptom**: on iPhone 17 Pro sim with no checklist active (so no bulk-ops row
>   pushing it further down), the highlight color row — the panel's last row — fails to appear
>   in 3 separate UI-test runs (`testFormattingPanel_highlights_clearButtonPresent` /
>   `clearHighlight` / `colorCellsTappable`, all reproducible, not timing-flake — same ~25-33s
>   as passing tests). Consistent with the 346pt fixed-height `ScrollView` cutting the panel
>   before the highlight row lays out. Not root-caused past that — needs Xcode's view debugger
>   on a live panel, which wasn't done. **Candidate for 2.5's fix, not a separate item.**
> - **3.4** — the `DispatchQueue.main.async` hop on every panel command is still load-bearing
>   on iPhone (inputView teardown race). Only the iPad popover path is free of it.
> - `InlineRecordingRow` cancel button uses `Color(.tertiarySystemFill)`
>   (`VoiceInputManager.swift:429`) — same theme-ignoring pattern 3.3 flags for the delete button.
> - Stale code comments describing the abandoned overlay: `FormattingPanelView.swift:28`,
>   `WriteView+Subviews.swift:443`, and the `.sheet` case name is now a misnomer (it's
>   inputView-hosted, not a sheet).
>
> **`mirrorUITests` modernized (2026-09-10/11) — 31/32 passing clean on iPhone 17 Pro sim**
> (25/32 before 3.1/3.2/3.3, below, fixed the highlight-row label bug; 31/32 after also
> fixing `paragraphStyle_cycleThroughAll`'s horizontal-scroll tap). Only
> `testVoice_micButton_recordsInlineWithoutModal` remains, likely an environment limit
> (no mic input on this sandboxed host), not confirmed as an app bug.
> Original suite (last touched 2026-05-13, predates the panel rework): 28 failed / 3 passed,
> every failure a renamed accessibility label, not an app regression — Aa `"Text formatting"`
> → `"Formatting"`, mic → `"Record voice note"`, checklist button gone from the toolRow
> (May 2026), plus `app.cells.firstMatch` hitting the calendar heatmap instead of an entry row.
> Fixed: label refs, `applyChecklistViaPanel`/`open`/`closeFormattingPanel` helpers,
> `openEntryForEditing` (locates rows by text), `discardDraft` assertion rewritten for the
> undo-countdown behavior (`startDeleteWithUndo`, `WriteView+Actions.swift:195` — clears
> immediately, button stays enabled as the undo affordance), `keyboardIconButton_closesPanel`
> replaced with `aaButton_closesPanelAndRestoresKeyboard` (no keyboard icon in the panel
> anymore — closes via "Hide formatting", asserts `app.keyboards` presence as the 2.1 proof),
> and a new `testVoice_micButton_recordsInlineWithoutModal` for 2.2.
>
> **Second bug found and fixed: cross-test draft contamination.** `--uitesting` only skips
> onboarding (`ContentView.swift:92`) — the draft (`UserDefaults` + `DraftAttachmentStore`) and
> every `Entry`/`Insight` persist on-disk across app relaunches, and no test cleaned up after
> itself. Each `XCUIApplication().launch()` restored the *previous* test's draft, so by test 20
> the editor held every prior test's typed text concatenated together, breaking cursor-position
> and panel-layout assumptions. Confirmed by re-running 2 failures in isolation — both passed
> clean with identical code. Fix: new `--clearWriteTestState` launch arg (DEBUG-only,
> `mirrorApp.swift`, matching the existing `--seedX`/`--clearX` pattern) wipes the draft
> (`WriteView.clearAllDraftStorage()`, a new static split off `clearDraftStorage()`) and all
> `Entry`/`Insight` rows (`SampleData.clear(from:)`, already existed) on launch;
> `launchApp()` now passes it. Took the suite from 22/32 → 25/32.
>
> **Re-isolated the 2 ambiguous ones on a calm machine (load avg back to ~3):**
> `Regression_openAaOnChecklistLine` **passed clean** — confirmed as residual-load noise, not
> a real bug. `editEntry_deleteButtonShowsConfirmation` **failed again at normal speed**
> (21-33s, 2/2) — genuinely reproducible, but the *test's premise was wrong*, not the app:
> `WriteView+Subviews.swift:307,333` shows "Delete entry" and "Discard draft" call the **same**
> `startDeleteWithUndo()` — an existing entry is no longer deleted via confirmation dialog, it
> gets the same immediate-clear + 10s-undo-countdown as a discarded draft. Renamed to
> `testToolbar_editEntry_deleteButtonShowsUndoCountdown` and rewritten to assert the undo
> banner ("Entry will be deleted" + "Undo" button) instead of a `Delete`/`Cancel` dialog —
> not yet re-run (this environment's simulator/XCTRunner launch denied requests under
> repeated back-to-back runs; compiles clean, verified by reading the handler code directly).
> Left the toolRow's `--clearWriteTestState` reset alone — the undo-tap at the end of the new
> test restores the entry rather than actually deleting it, so it stays side-effect-free.
>
> **Highlight-row mystery solved by 3.1 (below): it was a test bug, not 2.5.** The "clear
> highlight" (xmark) button had no explicit `accessibilityLabel` — its default SwiftUI/UIKit
> label was never actually the literal string `"xmark"` the 3 tests matched against
> (`NSPredicate(format: "label == 'xmark'")`), so they never found it, regardless of layout.
> 3.1 gave it a real explicit `accessibilityIdentifier("xmark")` (kept stable for exactly this
> reason) + `accessibilityLabel("No highlight")`; tests switched from the label predicate to
> `app.buttons["xmark"]` (identifier lookup). All 3 **now pass**. The 346pt-clipping theory
> was never confirmed and is retracted — no evidence the highlight row is actually clipped.
>
> **`paragraphStyle_cycleThroughAll` fixed.** "Mono" is the rightmost item in the
> paragraph-style row's horizontal `ScrollView`; a synthetic `.tap()` doesn't auto-scroll like
> VoiceOver does, so it's off-screen with a degenerate frame — and even *reading*
> `.isHittable` on it throws ("Activation point invalid"), so the fix has to scroll
> unconditionally before touching the Mono element at all, not gate on a hittability check.
> Fix: drag from "Subheading" (the prior, still-hittable button in the same row) via
> `XCUICoordinate.press(forDuration:thenDragTo:)` before targeting Mono. Verified in isolation
> — failed before, passes clean at normal speed (28s) after.
>
> **1 still fails / unresolved (down from 6 — 31/32 passing):**
> - **`testVoice_micButton_recordsInlineWithoutModal`** — mic tapped, no permission dialog
>   fired (already decided from an earlier run), then neither the recording row nor the
>   permission notice ever appeared. Most likely this sandboxed sim host has no usable mic
>   input device at all (silent `AVAudioRecorder` failure) — consistent with the existing
>   "real mic — device only" caveat, but not confirmed against a device or a host with mic
>   access, so can't rule out a real bug.
>
> Clean-vs-degraded matters here: a first re-run attempt on a thrashing machine (load avg
> 16-157) took 8 hours instead of ~10 minutes and produced mostly-bogus failures — always
> check `uptime` before trusting a run's failures as real.
>
> **String catalog extraction — done (2026-09-12).** 20 WriteView/voice-note-scoped keys had
> been extracted into `Localizable.xcstrings` (key + auto-generated comment present) but never
> translated beyond `en` — e.g. `"Cancel recording"`, `"Stop and add recording"`, `"Quote"`,
> `"No highlight"`, `"Transcription failed."`, `"AI won't reflect on this note."`, the mic
> permission notice, the 2.3 long-press popover copy, and the `VoiceTranscriptionError` case
> descriptions. Translated all 20 into the app's existing 9 locales (de/es/fr/it/ja/ko/pt-BR/
> ru/zh-Hans), reusing established vocabulary from neighboring entries (e.g. "voice note" →
> `Sprachnotiz`/`nota de voz`/`ボイスノート`/`음성 메모`/etc., already consistent across the
> catalog) rather than inventing new terms. Edited `Localizable.xcstrings` directly (JSON) since
> there's no Xcode GUI in this environment; diffed against `git show HEAD` first to confirm the
> change touched only the 20 targeted keys (two unrelated pre-existing empty entries got
> reformatted from multi-line `{}` to single-line `{}` as a side effect of Python's JSON
> serializer — cosmetic only, values unchanged). Verified by decoding the built app's
> `de.lproj`/`ja.lproj` `Localizable.strings` after a real build — the translated values are
> present in the compiled output, not just the source catalog.
> `xcodebuild build` green (all 10 locales compile).
>
> Out of scope, left alone: ~15 other untranslated keys elsewhere in the catalog (Deep Scan /
> X-ray / paywall strings — not WriteView, not this audit's concern).
>
> **2.3–2.4 not started.**

### 2.1 The Aa panel replaces the keyboard instead of floating over it
`NoteEditorTextView.swift:2383` — `textView.inputView = panelUIView; textView.reloadInputViews()`.

The formatting panel is installed as the text view's `inputView`, so opening it **removes the
keyboard entirely**. While the panel is open you cannot type, cannot dictate, and the code
has to force `becomeFirstResponder()` to keep the panel on screen
(`NoteEditorTextView.swift:2386`). Apple Notes shows formatting as a small floating bar /
popover *above a live keyboard* (a true popover on iPad), so you format and keep writing in
one motion.

This is the single biggest "doesn't feel like Notes" item in the formatting surface.

Fix options, cheapest first:
1. Host the panel as `textView.inputAccessoryView` (stays above the keyboard) — modest change,
   big feel improvement, but the panel is tall (346pt) so it eats most of the screen.
2. A compact single-row accessory bar (B / I / U, list, checklist, Aa-for-more) with the full
   panel as an optional expansion — closest to Notes.
3. A floating SwiftUI overlay pinned above the keyboard via keyboard-frame observation, panel
   content unchanged.
Effort: M–L. Sentinel parity: `FormattingPanelView` already branches on `displayMode`;
re-hosting doesn't change that, but re-test both.

### 2.2 Voice recording is fully modal — can't write while recording
`WriteView+VoiceNotes.swift:105` (`presentVoiceNoteSheet`) resigns first responder, waits
0.25s, then presents `VoiceInputSheet` as a `.sheet`.

Recording blocks the whole editor. Notes records inline (a live audio row appears in the
note, insertion point stays active, you keep typing). For a journaling app where people
narrate and jot at the same time, this is a real workflow gap.

Fix: inline recording — start from the toolbar mic, show a live recording row where the
voice-note attachment will land, keep the keyboard and cursor. The `VoiceNoteAttachmentView`
row UI already exists; needs a "recording" state and a stop control.
Effort: M–L. Sentinel parity: recording chrome exists in both (`VoiceInputSheet` branches);
port the states to the inline row for both.

### 2.3 No live dictation anywhere
Only path is record-file → `SFSpeechURLRecognitionRequest` after the fact
(`VoiceTranscriptionService.swift:37`).

Notes (and the system keyboard) offer live dictation: tap the mic, words appear as you speak.
mirror has the keyboard's built-in dictation available for free (it's the system keyboard),
but there is no in-app affordance pointing users to it, and the app's own mic button leads
only to the modal recorder. Consider: (a) documenting/keeping keyboard dictation as the
"speak into the text" path and reserving the app recorder for "attach an audio memo," and
(b) making that distinction visible in the toolbar (two affordances, not one ambiguous mic).
Effort: S (framing/UX) to L (in-app streaming recognition). Sentinel parity: toolbar icons
branch already.

> **STATUS — (b) shipped on `2.1.1` at the S-effort scope; (a) is this popover's copy, not
> separate documentation; in-app streaming recognition (the L option) not attempted.**
>
> No coach-mark/tip pattern existed anywhere in the app to reuse (checked — grepped for
> `onLongPressGesture`/`CoachMark`/`TipView`/`infoPopover` across `Features/`), and inventing
> one for a single button felt like a bigger decision than this item's own S-effort framing.
> Instead: long-press the mic button (`WriteView+Subviews.swift`) reveals a small popover —
> "Voice Note" / "Records audio and transcribes it afterward — good for a longer memo." / "For
> live dictation as you type, use the mic key on your keyboard." That *is* the (a)
> documentation this item asked for — it doesn't additionally exist in onboarding or Settings,
> neither of which mentions dictation today (checked, not assumed).
>
> **Gesture-conflict bug, caught by advisor before commit**: the first version wrapped the mic
> in a SwiftUI `Button` with the hint on a `.simultaneousGesture` long-press. `Button`'s own tap
> gesture still fires alongside a simultaneous long-press — they don't mutually exclude — so a
> long-press meant to read the hint would *also* start a recording behind the popover, the worst
> possible outcome for a discoverability affordance. Rewritten as a plain `Image` view with
> explicit `.onTapGesture`/`.onLongPressGesture` instead of a `Button` — mutually exclusive by
> construction. Added `.accessibilityAddTraits(.isButton)` (lost when dropping `Button`) and
> `.accessibilityAction(named: "What this does")` — long-press is invisible to VoiceOver
> entirely, so without an explicit accessibility action a VoiceOver user would have no way to
> reach the same explanation at all.
>
> **Verification gap, stated plainly**: added `mirrorUITests.testVoice_micButtonLongPress_
> showsHintWithoutRecording` (long-presses the mic, asserts the hint text appears *and* no
> recording started, then confirms a plain tap afterward still records normally). **This test
> has not actually passed** — both runs died in `FBSOpenApplicationServiceErrorDomain`
> (`RequestDenied`) before the app even launched, with machine load at 110–130 at the time
> (checked via `uptime`, not guessed at). The fix is reasoned to be correct (plain-view
> mutually-exclusive gestures are the standard, documented pattern for exactly this "tap vs.
> long-press on one control" case) but is **not** simulator- or device-verified. `xcodebuild
> build` is green; that's the only verification this pass actually got.

### 2.4 Post-hoc transcription is single-shot with no partial results
`VoiceTranscriptionService.swift:39` — `request.shouldReportPartialResults = false`, and the
service tries locales sequentially, each a full recognition pass over the whole file
(`:33` loop). A 3-minute multilingual note can spin through several full passes.

- No progress indication beyond an indeterminate spinner.
- `requiresOnDeviceRecognition = true` everywhere (`:38`) — correct for the privacy guarantee,
  but on devices/locales without an on-device model the note just fails with no explanation
  of *why* (CLAUDE.md forbids sending text off-device, and audio is text-equivalent here, so
  this constraint should stay — but the failure message should say "this language isn't
  available offline on this device").
- The NL-based language re-validation (`:46`) silently `continue`s past a correct transcript
  if `NLLanguageRecognizer` disagrees, with short texts exempted at `count >= 20` — brittle.

Fix: surface partial results as progress; cap total locales tried; distinguish "no offline
model for this language" from "recognition failed" in the error shown on the attachment row.
Effort: M. Sentinel parity: "DECODE FAILED" / "Transcription failed" copy exists for both.

> **STATUS — locale cap + error distinction fixed on `2.1.1`; partial-results progress
> explicitly deferred.** Two of the three `Fix:` items landed; the third needs a UI-shape
> decision (a progress bar? a streaming preview of the transcript-so-far? something else) this
> pass didn't make — flagged, not silently dropped.
>
> **Distinguishing "no offline model" from "recognition failed", the headline ask**: added
> `VoiceTranscriptionError` (`VoiceTranscriptionService.swift`) — 4 cases
> (`permissionDenied`/`noOfflineModelAvailable`/`timedOut`/`recognitionFailed`), each with real
> `errorDescription` copy. This mattered more than the audit item implied: every failure
> already threw `InsightError.serviceUnavailable(String)`, but `InsightError.errorDescription`
> **ignores that associated string** and always returns its own fixed, Insight-flavored text
> ("...Mirror will try again tonight while your phone charges" — meaningless for voice), and
> nothing ever unwrapped the enum to read the string directly either — so every distinct
> failure reason was being discarded twice over, not shown with the wrong specificity.
> `WriteView`/`WriteView+VoiceNotes.swift`/`WriteView.swift` gained a parallel
> `transcriptionFailureMessages: [Int: String]` alongside the existing `failedTranscriptionIndexes: Set<Int>`
> (kept in sync at every insert/remove/removeAll site), threaded into
> `VoiceNoteAttachmentView`'s new `transcriptionFailureMessage` param, which now composes the
> attachment row's failure line from the real reason instead of a single fixed string — falling
> back to the old generic copy when there's no real error to report (e.g. a failure inferred on
> reopening a saved entry, which only ever sees "audio present, transcript missing," never *why*).
>
> **Classification priority, corrected by advisor before commit**: the naive version classified
> whatever `lastError` happened to hold when the locale loop exhausted. The common real case —
> one locale's on-device model decodes the audio fine, but the NL-based language re-validation
> rejects it as the wrong language, then every other candidate locale gets skipped for having no
> downloaded model — never throws a catchable error at all (`continue`, not `catch`), so
> `lastError` stays whatever an *earlier, unrelated* locale's attempt threw (or `nil`), and the
> naive version would show a stale or generic message instead of the true "no model for this
> language" reason. Fixed by tracking `nlRejectedAny` separately and preferring
> `.noOfflineModelAvailable` over both a stale `lastError` and the generic `.recognitionFailed`
> when rejection-by-language is the only thing that actually happened.
>
> **Cancellation, second advisor catch**: `VoiceTranscriptionError.classify(_:)` maps any
> non-`VoiceTranscriptionError` (a raw `SFSpeechRecognizer` `NSError`, a `CancellationError`)
> to `.recognitionFailed` so nothing unreadable reaches the UI — correct for a real failure, but
> a task cancelled out from under a recognition pass (delete, or the 1.4 save-anyway handoff)
> would classify the same way and write "Transcription failed." for what wasn't a failure at
> all. `transcribeVoiceNote`'s catch already guarded `if Task.isCancelled`; added `|| error is
> CancellationError` as belt-and-suspenders in case that flag and the thrown error type were
> ever to disagree at that exact point — cheap, can't hurt, directly closes the gap either way.
>
> **Locale cap**: added `maxLocalesAttempted = 6` — `localeList()` can offer ~28 candidates, but
> only ones with a *downloaded* on-device model reach an actual recognition pass
> (`supportsOnDeviceRecognition`), so this was already bounded in practice by how many models a
> given device happens to have, just not by anything explicit. Six passes (~4.5min worst case
> at the existing 45s/pass timeout) is a real, stated ceiling instead of "whatever the device
> happens to carry."
>
> **NL-validation brittleness** (the third bullet — `count >= 20` exemption, silent `continue`
> on disagreement) — read but not touched. It's characterized as "brittle," not broken, and
> changing a heuristic threshold without data on how often it actually misfires would be
> guessing; left as documented, not silently dropped.
>
> **Partial-results progress — deferred, not attempted.** This is a real UI-shape decision (a
> progress bar reading pass N of 6? a live-updating transcript preview via
> `shouldReportPartialResults = true`, which changes `recognize()`'s continuation-based
> single-result design into a streaming one?) that wasn't this pass's call to make alone.
> Noted here so it isn't silently dropped from the audit; picking a direction needs a decision,
> not more code.
>
> Verified: `xcodebuild build` green, `build-for-testing` green, `mirrorTests` 195/195 (192
> prior + 3 new `VoiceTranscriptionErrorTests`, covering `classify(_:)`'s pass-through/fallback
> behavior and that every case has a distinct, non-empty description). **Not** verified: the
> locale-loop classification logic itself (`nlRejectedAny`, the cap, the cancellation guard) —
> exercising that needs real `SFSpeechRecognizer` behavior across multiple locales, which isn't
> mockable in this test target. Reasoned through and reviewed, not exercised by a test.

### 2.5 Formatting panel height is a hardcoded 346pt
`NoteEditorTextView.swift:2381` — `CGRect(x: 0, y: 0, width: textView.frame.width, height: 346)`.
(Now `height: 360` after the STATUS block below — line numbers have also shifted.)

- Clips on iPhone SE and in landscape.
- Ignores Dynamic Type entirely: `FormattingPanelView` uses fixed `.system(size:)` and fixed
  `44`/`50`pt button frames throughout, in an editor that sets
  `adjustsFontForContentSizeCategory = true` (`NoteEditorTextView.swift:40`). A user at an
  accessibility text size gets a panel with clipped, tiny-relative labels.
- No iPad treatment — on iPad Notes uses a popover; here it's still a bottom input view.

Fix: `@ScaledMetric` for sizes; measure the hosting controller's `sizeThatFits` instead of a
literal; add a `.popover` branch for `horizontalSizeClass == .regular`.
Effort: M. Sentinel parity: both themes share the fixed sizes — fixing helps both.

> **STATUS — Dynamic Type + the 346pt literal fixed on `2.1.1`; the iPad bullet was already
> stale.** `usesPopoverPanel` (`WriteView.swift:35`) shipped with the 2.1 work earlier this
> session — iPad already gets a `.popover`, not a bottom input view. Only the first two bullets
> were live.
>
> **`@ScaledMetric` pass (`FormattingPanelView.swift`)**: one shared `@ScaledMetric(relativeTo:
> .body) private var typeScale: CGFloat = 1.0` — the officially recommended pattern for a
> cluster of custom point sizes that should scale together while keeping their relative
> proportions (Title 22pt vs. Mono 13pt, etc.), rather than 15 separate metrics. Every fixed
> font size and button `frame(width:height:)` in the file is now `base * typeScale`.
>
> **Horizontal overflow, caught by advisor before this was "just" a font pass**: scaling
> button sizes without giving rows 2 ("B"/"I"/"U"/"S"), 3 (list types + indent), 3b (checklist
> bulk ops), and 4 (highlights) the same horizontal `ScrollView` rows 0/1 already have would
> have made large Dynamic Type sizes *worse*, not better — content would grow past an iPhone
> SE's 375pt width with a trailing `Spacer(minLength: 0)` that cannot rescue an overflow, only
> push the tail out of reach. Wrapped all four in `ScrollView(.horizontal)`, matching rows 0/1.
> Row 3's indent-increase/decrease pair stays pinned outside the scroll region (so it's never
> the thing scrolled out of reach) with a **fixed, unscaled frame** — `listButton(...,
> scaleFrame: false)` — because two 50pt-wide buttons scaling *in addition to* the four
> scrolling list buttons would eat most of the SE-width row and leave the scrollable region a
> sliver at large accessibility sizes; the glyph inside still scales, just within that fixed
> box.
>
> **The 346pt literal was a real, if tiny, bug — not the imprecise "clips on iPhone SE" the
> item described.** Added `mirrorTests/FormattingPanelSizingTests.swift`, which measures
> `FormattingPanelView`'s actual `sizeThatFits` at 375pt width (iPhone SE) via
> `UIHostingController`, with the checklist bulk-ops row active — the panel's tallest
> configuration, which a bare `FormattingPanelState()` skips by default and which the first
> draft of this test missed (caught by advisor). At the system default text size, that
> configuration measures **347pt — 1pt over** the old 346pt literal, meaning the panel's own
> bottom row was being clipped by exactly 1pt on stock settings, before any Dynamic Type is
> involved. Bumped the literal to **360pt** (`NoteEditorTextView.swift`) for real headroom
> instead of a number that happened to almost work. Confirmed via the same test that
> `accessibility3` still exceeds 360pt (bounded under 900pt — the test doesn't assert an exact
> figure, only that it's grown *and* stayed sane) and relies on `panelRows`' own `ScrollView`
> in the `.sheet` presentation — that's expected and by design, not a bug: bumping
> the literal further would eat into the editor's own visible area for no benefit, since the
> panel already scrolls past 360pt regardless of how high the fixed frame goes.
>
> **What's verified vs. reasoned**: the height numbers above are measured, not eyeballed —
> `xcodebuild build` green, `build-for-testing` green, `mirrorTests` 192/192 (190 prior + 2 new
> `FormattingPanelSizingTests`, individually confirmed `Passed`). The horizontal-scroll fix
> itself is **not** exercised by any test — nothing in the suite drives a `ScrollView(.horizontal)`
> — so "192/192 green" here is a no-regression signal for the height/scaling math, not proof
> that rows 2–4 are actually reachable by scrolling on a real SE at `accessibility5`. That
> needs an on-device check, same caveat as 3.9's still-open scroll-to-cursor item.
>
> **Known gap, not fixed here**: `formattingPanelHost` (`updateFormattingPanel(textView:
> visible:)`) is built once on first show and its `rootView` is never refreshed after that.
> `typeScale` resolves from the environment at that one construction, so a user who changes
> the system text size *while the panel is already showing* keeps the old scale until the
> panel is torn down and rebuilt (e.g. dismissing and reopening it) — not a regression from
> this fix, but this fix makes the staleness more visible than it was when everything was a
> fixed literal. Pre-existing pattern, out of scope for 2.5.

## Group 3 — Polish, accessibility, perf

> **STATUS — 3.1, 3.2, 3.3 fixed** (2026-09-11), on `2.1.1`. `xcodebuild build` green.
> mirrorUITests 25/32 → 30/32 (fixed the highlight-row test's stale label lookup as a
> side effect of 3.1 — see Group 2 STATUS above).
> - **3.1** — real `.accessibilityLabel` on every inline/list/highlight button ("Bold",
>   "Bulleted list", "Pink", …), `.accessibilityAddTraits(.isSelected)` on every toggle
>   (inline, paragraph, font, list, highlight). Kept the old glyph/icon-name as
>   `.accessibilityIdentifier` on each so existing UI-test lookups (`app.buttons["B"]`,
>   `app.buttons["checklist"]`) still resolve — only the VoiceOver-facing label changed.
> - **3.2** — `highlightColors` replaced by `HighlightPalette.colors(for: displayMode)`
>   (`FormattingPanelView.swift`): 5 light/dark-adaptive pairs for Classic (same hues,
>   deepened dark variants — `MirrorTheme.hex`, made internal to reuse it) + a distinct
>   ember/warm-neutral set for Sentinel. Applied in both the panel swatches and the
>   editor's own highlight-attribute rendering (`NoteEditorTextView.swift` — 3 call sites,
>   was reading the same fixed light pastels for the actual highlighted text, not just
>   the panel UI).
> - **3.3** — `VoiceInputManager.swift`'s voice-note delete button *and* the newly-added
>   `InlineRecordingRow`'s cancel button (spotted during 2.1/2.2 verification, same
>   pattern) both now branch `displayMode == .sentinel ? MirrorTheme.inkMid :
>   Color(.tertiarySystemFill)` like every sibling control.

### 3.1 Formatting panel is nearly invisible to VoiceOver
`FormattingPanelView.swift` throughout.

- `inlineButton("B" …)` etc. expose the bare glyph "B"/"I"/"U"/"S" as the label — VoiceOver
  reads "B". No `.accessibilityLabel("Bold")`.
- Active state is conveyed only by color/stroke — no `.accessibilityAddTraits(.isSelected)`.
- Highlight swatches (`highlightButton`, `:276`) have no label at all — "button".
- `paragraphStyleButton` / `fontChoiceButton` labels are OK but still lack the selected trait.

Fix: real labels + `.isSelected` trait on every panel control.
Effort: S. Sentinel parity: labels are theme-independent.

### 3.2 Highlight colors are five fixed light pastels
`FormattingPanelView.swift:4` — `highlightColors` is a module-level `[Color]` of hardcoded
light-mode pastels. No dark-mode variants (they'll look washed out / low-contrast on the
dark editor) and no Sentinel variant (the rest of the panel carefully branches ember/mono).

Fix: resolve highlights through `MirrorTheme` with light/dark pairs, and a Sentinel set (or
suppress highlight colors in Sentinel in favor of the ember accent).
Effort: S–M (need to store an index, already done — just remap at render). Sentinel parity:
**this is a live divergence** of exactly the kind CLAUDE.md flags.

### 3.3 Voice-note delete button ignores the theme
`VoiceInputManager.swift:226` — the delete "x" background is hardcoded
`Color(.tertiarySystemFill)` while the surrounding card and every sibling control branch on
`displayMode`. Small, but it's the CLAUDE.md "check both themes on every themed view" rule.
Effort: XS. Sentinel parity: **that's the bug.**

### 3.4 `DispatchQueue.main.async` wrapped around every panel command
`FormattingPanelView.swift:110,152,180,207,235,254,280` — every button does
`DispatchQueue.main.async { state.onCommand?(…) }`. The comment at
`NoteEditorTextView.swift:2367` explains the panel host is created once and never rebuilt
specifically so in-flight taps aren't dropped — i.e. this async hop is load-bearing but
fragile. It also adds a frame of latency to every formatting action vs. Notes' instant
response.

Fix: once the panel is a keyboard accessory / popover (2.1) rather than a swapped `inputView`,
the teardown race goes away and these can likely become synchronous. Re-evaluate then.
Effort: folded into 2.1. Sentinel parity: N/A.

> **STATUS — checked, still genuinely blocked. Not attempted.** This item's own fix note
> premises on 2.1 having changed *how the iPhone panel is presented* — but re-reading 2.1's
> actual STATUS block and the current code: 2.1 gave **iPad** a `.popover` (`usesPopoverPanel`,
> `WriteView.swift:35`); iPhone still swaps the formatting panel in as `textView.inputView`
> (`usesInputView`, `NoteEditorTextView.swift:2432`, unchanged). The teardown race the
> `DispatchQueue.main.async` hop guards against — the panel host being torn down and rebuilt
> mid-tap — is still real on iPhone, which is the device this async hop actually matters for.
>
> Making these synchronous now, without first re-architecting the iPhone panel the way 2.1 did
> for iPad, would very likely reintroduce the dropped-tap bug the async hop was added to fix in
> the first place. Doing that re-architecture properly (iPhone panel as a keyboard accessory
> view instead of a swapped `inputView`) is a real UI-structure change — closer in size to
> redoing 2.1 itself than to a one-line "make it synchronous" — and not something to take on
> inside this pass, especially with the simulator's UI-test runner currently unreliable
> (`FBSOpenApplicationServiceErrorDomain` launch denials under machine load, seen repeatedly
> this session) to verify a change of that size against. Left open, correctly scoped now
> instead of assumed-resolved by a dependency that only half-landed.

### 3.5 `@Query` loads every entry into the write screen

> **FIXED** (2026-09-11). `allEntries` removed from `WriteView`. `computeTagSuggestions()`
> (unchanged call site — still only runs when the tag-input row opens) now fetches on demand:
> `var descriptor = FetchDescriptor<Entry>(); descriptor.propertiesToFetch =
> [\.encryptedTagsStorage]` (`propertiesToFetch` is a settable property on the descriptor, not
> an initializer arg — first attempt didn't compile). `.tags` is computed/encrypted, backed by
> `encryptedTagsStorage`, so that's the stored property to scope the fetch to. `WriteView` no
> longer observes/re-renders on entry changes elsewhere in the app. `xcodebuild build` green,
> `mirrorTests` 186/186 green.

`WriteView.swift:29` — `@Query(sort: \Entry.createdAt, order: .reverse) var allEntries: [Entry]`.

Only consumer found is `computeTagSuggestions()` (`WriteView+Tags.swift:144`), which just
wants the distinct tag set. This loads (and decrypts, on access) every entry, and makes the
whole editor re-render whenever *any* entry changes anywhere (e.g. a background mood-detect
save). On a large journal that's a real cost on a latency-sensitive screen.

Fix: a `FetchDescriptor` with `propertiesToFetch: [\.tags]` run once in `onAppear`, or a
lightweight cached tag index. Don't hold a live `@Query` of all entries here.
Effort: S. Sentinel parity: N/A.

### 3.6 Editor re-renders the full attributed string more than it needs to
`NoteEditorTextView.swift:68` (`updateUIView`) → `applyStyledText(preservingSelection: true)`
on **every** SwiftUI update pass.

Mitigation is in place: `applyStyledText` (`:920`) has a signature check
(`lastRenderedText` / style / inline / photo / width / font) and early-returns when nothing
changed, and `textViewDidChange` (`:293`) guards re-entrancy with `isApplyingStyledText`.
So the common keystroke case is cheap. But:
- `logicalText(from:)` (`:1002`) rebuilds the whole string char-by-char (Swift `String`
  concatenation in a loop, plus `allPhotoTokens` sort) on every `textViewDidChange`, and is
  also called in `updateUIView:71` for the comparison. For a 5–10k-char entry that's work on
  every keystroke.
- The early-return still calls `bounded(selectedRange, in: textView.text)` which bridges the
  full `String`.

Verdict: not a Group 1 bug, but the `logicalText` cost is the thing to profile if typing
feels heavy on long entries. Consider caching the logical text and invalidating on structural
edits only.
Effort: M (needs profiling first). Sentinel parity: N/A.

> **STATUS — profiled on `2.1.1`, no code change.** No Instruments access in this environment,
> so substituted a real wall-clock measurement for a guess: added
> `mirrorTests/NoteEditorRenderCostTests.swift`, which calls `Coordinator.logicalText(from:)` +
> `.displayTextEquivalent(for:)` directly against a populated `UITextView` — the exact pair
> `updateUIView:75` calls on every SwiftUI update pass, confirmed by reading it: **both** sides
> of that comparison do a full-document rebuild, not just the one `logicalText` call the audit
> item named; `applyStyledText`'s own change-detection cache only protects the render step
> downstream of this comparison, never this comparison itself.
>
> **Measured** (Simulator, Debug config, Apple Silicon — a floor, not a device-representative
> figure): **1.34ms** at ~5k chars (no photos), **1.98ms** at ~10k chars (no photos), **0.85ms**
> at ~5k chars with 3 inline photos (exercises `allPhotoTokens`' sort + the attachment-char
> rebuild loop the no-photo cases skip entirely — no meaningfully higher than the no-photo
> case at the same size). All three against a 16.67ms frame budget at 60fps, which is the
> budget for the *whole* update pass, not just this comparison.
>
> **Verdict confirmed, not just assumed**: this is not the thing making typing feel heavy on
> long entries, at these sizes, on this hardware. Left as documented headroom, per the item's
> own "not a Group 1 bug" line — no caching added. The `updateUIView:75` double full-document
> rebuild is real and deliberately left unfixed by this decision, not an unnoticed gap; a
> future reader hitting a real perf complaint on long entries should start there, with actual
> Instruments time-profile data from a real device before changing anything, not re-derive
> this finding from scratch.
>
> **Durable artifact**: the three tests double as a regression guard, not just one-time
> evidence — bounds set at roughly 3x the measured figures (headroom for machine variance,
> still tight enough to catch an accidental algorithmic regression, e.g. an O(n²) reintroduction
> would blow well past them). If `logicalText`/`displayTextEquivalent` ever gets meaningfully
> more expensive, these trip before a user notices.
>
> **Method caveats, stated rather than hidden behind a clean number**: Debug config in
> Simulator on Apple Silicon isn't a slow real device — absolute numbers here are a floor. The
> populated `UITextView` carries plain (unstyled) attributed text, so `textStyle(at:)`/
> `indentLevelValue(at:)` take their early-return paths on every paragraph rather than reading
> real paragraph-style attributes — a length-driven cost approximation, not a claim that
> styling itself is free.
>
> Verified: `xcodebuild build` green, `build-for-testing` green, `mirrorTests` 198/198 (195
> prior + 3 new `NoteEditorRenderCostTests`). This item's own tests *are* the verification —
> there's no separate "did the fix work" check since the fix was measuring, not changing code.

### 3.7 Dead code in `WriteViewModel`

> **FIXED** (2026-09-11). Both methods deleted, confirmed zero callers (grepped
> `mirror/`/`mirrorTests/`/`mirrorUITests/`). `import SwiftData` in `WriteViewModel.swift` also
> dropped — it was only there for `save(context: ModelContext)`'s parameter type; `Entry` (used
> in `configure(entry:)`) doesn't need the import at a use site, only where it's declared.

`WriteViewModel.swift:30` (`save(context:)`) and `:42` (`updateEntry(_:)`) have no callers —
`WriteView+Actions.swift` does its own `Entry` construction and insertion. `save` also
doesn't set `wordCount`. Confirmed: only `WriteViewModel()` / `.text` / `.textStyleData` /
`.selectedMood` / `.wordCount` / `.configure` / `.hasContent` are referenced. Delete the two
methods to avoid someone wiring them up later.
Effort: XS.

### 3.8 `panelState.fontChoiceRaw` set once, never updated

> **RESOLVED — the property was dead, not stale.** Verified: nothing reads
> `panelState.fontChoiceRaw` (grepped every `.fontChoiceRaw` reference in `mirror/`). The
> render path that matters — `entryDefaultFontChoice` in `NoteEditorTextView.swift:1780` — was
> already reading `parent.fontChoiceRaw` directly, i.e. the live `entryFontChoiceRaw` binding,
> not the panel's copy. The panel's own active-state highlight uses a *different*, correctly
> live-refreshed property, `activeFontChoice` (updated on every caret move via
> `fontChoiceValue(at:in:)`). So there was no drift to fix — `fontChoiceRaw` on
> `FormattingPanelState` was write-once, read-never. Deleted the property and its one
> assignment (`WriteView.swift:363`); one unit test (`FormattingCombinationTests.swift:40`)
> also set it redundantly alongside the real binding — removed that line too.
> `xcodebuild build-for-testing` green, `mirrorTests` 186/186 green.

`WriteView.swift:312` sets `panelState.fontChoiceRaw = entryFontChoiceRaw` in `onAppear` and
never again, while `entryFontChoiceRaw` continues to be edited (via `.fontFamily` commands)
and saved to `entry.fontChoice` (`WriteView+Actions.swift:25,55,103`). The panel comment
(`FormattingPanelView.swift:19`) says font is now per-paragraph and `fontChoiceRaw` is
"entry-wide fallback only." Verify the entry-wide fallback used for rendering an empty
paragraph doesn't drift from what the user last picked. Low severity but worth a test.
Effort: S to verify.

### 3.9 Smaller Notes-parity nits
- No word/char count anywhere except the daily-goal chip (`WriteView+Subviews.swift:42`);
  Notes has none either, so leave it — but the goal chip only appears `if viewModel.wordCount
  > 0` and the "/ Xw" only at `>= 50`, which is a slightly odd staircase.
- `keyboardDismissMode = .interactive` is set (`NoteEditorTextView.swift:37`) — good, matches
  Notes.
- Placeholder is a single `UILabel` pinned top-left (`:43`) — fine, but it stays visible when
  `textStyleData != nil` logic at `:962` is subtle; verify it hides correctly for a
  photo-only draft.
- No "scroll to cursor on keyboard show" handling seen — verify the caret isn't hidden behind
  the toolRow / panel on a full screen of text.

> **STATUS — three of four resolved on `2.1.1`, no code changes needed; one stays open.** Went
> through each of the four claims individually rather than taking any at face value. The
> fourth went through two write-ups before landing here — the first got the mechanism wrong,
> caught before commit; the corrected version still can't be settled by reading code alone.
>
> - **Placeholder for a photo-only draft — retracted, was a false theory.** A photo isn't
>   inserted as an invisible attachment against an empty `text` binding; `insertPhotoToken(in:)`
>   (`NoteEditorTextView.swift:1209`) writes an explicit `"[[mirror-photo-N]]"` token into
>   `parent.text` itself (`logicalText(from:)` round-trips attachment chars through the same
>   token), then calls `updatePlaceholder(in:)` directly. So `parent.text.isEmpty` is false the
>   moment a photo lands, and the placeholder hides correctly with no text ever typed. Traced
>   the actual insertion call path rather than trusting the `:962` condition read in isolation.
> - **"No scroll to cursor on keyboard show" — "no handling seen" is wrong; whether it's
>   *sufficient* stays open.** A mechanism exists: `scrollCaretToVisible(in:)`
>   (`NoteEditorTextView.swift:323`) nudges the enclosing `ScrollView` toward the caret, called
>   from `textViewDidChangeSelection` (:610, tap-to-position) and `textViewDidChange` (:317,
>   while typing).
>
>   First write-up here flagged the formatting panel as the risk — its stacked 44–50pt rows vs.
>   the nudge's fixed 48pt clearance — on the assumption the panel is an overlay stacked *on
>   top of* the keyboard. Wrong, caught on a second pass: `updateFormattingPanel(textView:
>   visible:)` (`:2404`) sets `textView.inputView = panel` — on iPhone the panel *replaces* the
>   keyboard as the input view, the identical slot, not a second surface. That kills the
>   height-comparison theory outright.
>
>   What it doesn't settle: whether the enclosing `ScrollView` (`WriteView.swift:156`) gets an
>   automatic keyboard-safe-area inset at all — no `.ignoresSafeArea(.keyboard)` opt-out is
>   present, which usually means SwiftUI's standard automatic avoidance applies, but I didn't
>   verify that on device and the function's own doc comment (`:36-38`, `"the text view doesn't
>   scroll … so keep the caret above the keyboard by nudging the enclosing scroll view"`) reads
>   as if the manual nudge is *the* mechanism, not a secondary refinement on top of automatic
>   avoidance. Both readings are defensible from the code alone — automatic avoidance could be
>   handling the region-clears-the-panel part while the nudge only handles "scroll to this
>   specific point within that region" (my current read), or avoidance could be absent/
>   insufficient and the 48pt nudge is the entire budget (the original worry, on inset grounds
>   rather than height grounds). Not resolving this from a code read a third time — needs
>   on-device confirmation with the panel open on a full screen of text. Left open.
> - **`keyboardDismissMode` — already correct**, nothing to do; the audit item itself said so.
> - **Word-count staircase — real, left as-is.** Bare count for 1–49 words, `"Nw / Xw"` from 50
>   up to goal, checkmark at goal. Shipped unchanged since `57f493c` (1.0.9, a squash commit —
>   no message explaining why). No evidence of intent either way, and no evidence of user
>   confusion either; leaving unchanged pending a concrete complaint rather than guessing at a
>   rationale that isn't in the code or history.
>
> No build/test run needed — no source changed. One sub-item (scroll-to-cursor clearance under
> the open panel, on inset grounds not height grounds) stays open, not closed by this pass.

---

## Suggested order of work

1. **1.1, 1.5** together (UUID identity for voice notes) — stops transcript corruption.
2. **1.3** (empty-entry save) — one-line-ish, high user trust impact.
3. **1.2** (draft loses attachments) — pick the "always a real Entry" model if feasible.
4. **1.8** (debounce draft save) — quick latency win.
5. **1.6, 1.7** (recorder/player correctness) — bundle the AV delegate + interruption work.
6. **1.4** (transcription timeout + save-anyway).
7. **2.1** (Aa panel → keyboard accessory / popover) — the headline "feels like Notes" fix.
8. **2.2** (inline recording) — second headline.
9. **3.1, 3.2, 3.3** (panel a11y + themed highlights + themed delete button) — cheap, and
   3.2/3.3 are CLAUDE.md Sentinel-parity obligations.
10. **3.5, 3.7, 3.8** cleanup.
11. **2.4, 2.5, 3.6** — needs profiling / design.
