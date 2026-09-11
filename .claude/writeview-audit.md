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
> 3 new user-facing strings (Group 1) + a few more (2.2) still need a catalog extraction pass.
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

### 2.5 Formatting panel height is a hardcoded 346pt
`NoteEditorTextView.swift:2381` — `CGRect(x: 0, y: 0, width: textView.frame.width, height: 346)`.

- Clips on iPhone SE and in landscape.
- Ignores Dynamic Type entirely: `FormattingPanelView` uses fixed `.system(size:)` and fixed
  `44`/`50`pt button frames throughout, in an editor that sets
  `adjustsFontForContentSizeCategory = true` (`NoteEditorTextView.swift:40`). A user at an
  accessibility text size gets a panel with clipped, tiny-relative labels.
- No iPad treatment — on iPad Notes uses a popover; here it's still a bottom input view.

Fix: `@ScaledMetric` for sizes; measure the hosting controller's `sizeThatFits` instead of a
literal; add a `.popover` branch for `horizontalSizeClass == .regular`.
Effort: M. Sentinel parity: both themes share the fixed sizes — fixing helps both.

---

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
