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
> - 1.4 → `7222109` — 25s timeout per recognition pass, cancellation-aware `recognize()`
> - 1.6 → `9c8c1c8` — real duration, `AVAudioRecorderDelegate`, interruption/route observers, 10-min cap
> - 1.7 → `503d930` — `AVAudioPlayerDelegate`, single `active` player
> - 1.8 → `beb0576` — debounced draft autosave
>
> Deferred, needs its own follow-up: **1.4 "Save anyway" while transcribing** (saving mid-pass
> writes to a dismissed view's state — same bug class; the timeout + 1.5 self-heal cover the
> "stuck" case). **Sentinel "REC" pulse** (`WriteView+Subviews.swift:62`) assessed — it's ambient
> chrome, never wired to recording state, so no change made.

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

> **STATUS — 2.1 + 2.2 code-complete, NOT verified.** Build green after each. Simulator UI
> automation was unreliable this whole session (cliclick coordinates + a stale install that kept
> serving an old binary), so the screenshots taken during testing can't be trusted to show the
> new code. Both need a hands-on / real-device pass.
>
> **2.1** (`c241eb5` + a follow-up): **iPad `.popover` off the Aa button + iPhone overlay in the
> keyboard's place, below the toolRow** (full panel, not a compact bar). `textView.inputView`
> hosting and all `becomeFirstResponder` forcing removed; `FormattingPanelView` gained a
> `.sheet`/`.popover` presentation mode; caret-move → panel-highlight sync already existed in
> `textViewDidChangeSelection`. iPad editor-blur auto-close is guarded off for the popover.
> To check: panel opens over a live keyboard on iPhone; caret + typing work with it open;
> caret moving between Body/Heading updates the panel; iPad popover stays up and doesn't drop
> the keyboard.
>
> **2.2** (`<pending>`): mic button records **inline** — `InlineRecordingRow` (elapsed / waveform
> / Stop / Cancel) appears where the finished note lands, keyboard + caret stay put. Recorder
> self-stops (interruption, cap) are finalized via `onChange`. `VoiceInputSheet` and the modal
> plumbing deleted (compiler-confirmed; not launch-confirmed). Mic-denied shows an inline notice.
> To check: record → row appears, keyboard stays → Stop → note attaches + transcribes; Cancel
> discards; a call mid-recording finalizes cleanly.
>
> 3 new user-facing strings (Group 1) + a few more (2.2) still need a catalog extraction pass.
> **Next session: run `/run-skill-generator`** — the `--uitesting` launch arg, the
> `-derivedDataPath` install path, and "HW keyboard suppresses `isKeyboardVisible` so the toolRow
> never shows" are the three facts that ate most of this round.
>
> **2.3–2.5 not started.** 2.5 (panel height/Dynamic Type) is partly mooted — the overlay now
> scrolls and the popover self-sizes — but the fixed `.system(size:)` / 44–50pt button frames
> inside `FormattingPanelView` still ignore Dynamic Type; a `@ScaledMetric` pass is still owed.
> The iPhone bar is the **existing toolRow** (undo/redo/Aa/photo/mic) — inline B/I/U still require
> opening the panel; add them to the bar if that's wanted.

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
`WriteViewModel.swift:30` (`save(context:)`) and `:42` (`updateEntry(_:)`) have no callers —
`WriteView+Actions.swift` does its own `Entry` construction and insertion. `save` also
doesn't set `wordCount`. Confirmed: only `WriteViewModel()` / `.text` / `.textStyleData` /
`.selectedMood` / `.wordCount` / `.configure` / `.hasContent` are referenced. Delete the two
methods to avoid someone wiring them up later.
Effort: XS.

### 3.8 `panelState.fontChoiceRaw` set once, never updated
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
