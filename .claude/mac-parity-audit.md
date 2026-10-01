# Mac vs iPhone/iPad parity audit

Started 2026-10-01. Method: grep every `#if os(iOS)` branch and shim (`PlatformCompat`), then go view by view and check the Mac expectations (keyboard, menus, context menus, dead actions). Each fix is verified in the Mac harness (`--macSnapshotParityOnly`, `--macSnapshotMenusOnly`, `--macEditorSelfTest`) against real state, not screenshots alone.

Shims checked: `UIApplication.open` goes to `NSWorkspace` (About links, Rate, feedback work); `presentShareSheet` opens `NSSharingServicePicker`, anchored at the window origin (see open items); haptics are no-ops (fine); `fullScreenCover` becomes a sheet.

## Fixed

| View | iPhone/iPad | Mac before | Fix | Verified |
|---|---|---|---|---|
| Write: entry date | Sheet with a calendar and time wheel | The iOS sheet in a 470x283 Mac sheet: calendar crushed, time field overlapping | Popover from the date title: calendar, stepper time field, Now, Done | Set date via the same binding, saved, read back `createdAt` day and `weekIdentifier` |
| Write: B/I/U | Toggle at caret or selection | Button state lagged one step at the caret (read the character before the caret, not the typing style); ⌘B/I/U only lived on toolbar buttons | State follows typing attributes; new Format menu (Title, Heading, Subheading, Body, Monospaced, Block Quote, lists, Bold, Italic, Underline, Strikethrough, Indent, Clear Formatting) with checkmarks | 14 new editor self-test checks (43/43), Format menu read from the running app |
| Write: Back shortcut | n/a | ⌘[ on Back collided with Notes' Decrease Indent | Back has no shortcut; ⌘[ and ⌘] are Decrease/Increase Indent | Menu dump |
| Settings > General: nudge and check-in times | Chevron row opening a wheel | Chevron row opening an unlabelled field | Native time stepper in the row; check-in is an on/off switch plus its own time row. Same reschedule path as iOS | Screenshot; iOS build unchanged |
| Entries list | Tap, swipe actions | No keyboard use | Up/Down move the selection (scrolls into view), Return edits, Delete asks first then selects the neighbour; context menu gains Edit and Open in New Window | Real key events: moves 0>1>2>1, Return reaches the handler, Delete shows the confirmation, Esc cancels with the count unchanged |
| Ask | Return adds a line | Same | Return sends, Shift-Return adds a line | Builds; not exercised (needs a model) |

## Checked, nothing to fix
- Reminders: scheduled through `UNUserNotificationCenter` on Mac too, and tapping the check-in reminder sets `MoodCheckInPresenter.pending`, so the Log Mood sheet opens. A time-triggered popup (without tapping a notification) is a separate, later piece.

## Open (not done yet)
- Reader: no Share or Export on the Mac toolbar (the board's reader toolbar is pin, window, delete, Edit). Candidates: File menu items (Share Entry, Export as PDF) rather than new toolbar buttons. "Export as PDF" is iOS-only code (`makePDF`).
- `presentShareSheet` on Mac anchors the share picker at the window origin; it should anchor to the clicked row or button.
- Today: iOS has a mood chart, streak and a Log mood button that the approved board does not show. Needs the owner's OK before adding visible UI.
- Write: daily word goal and word-goal UI from iOS (needs the owner's OK; not on the board).
- Mood timeline, Monthly report, Digest: no hover or keyboard work yet; Mood timeline chart has faint wedges inside the plot (area fill with several entries per day), likely also on iPhone.
- Ask: Esc, focus order and Tab order not checked. Brain View: wheel zoom, pinch and trackpad pan untested.
- Per-view keyboard pass for Digest, Report, Mood, Brain (Esc and Tab order).
