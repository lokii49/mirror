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

| Reader: share and export | Share as text, Export as PDF (iOS only) | No way to share or export an entry | File menu: Share Entry…, Export as PDF… (⇧⌘E, A4 pages like iPhone, save panel), Delete Entry… (⌘⌫, with the confirmation); the board's toolbar is unchanged | PDF written from the first entry, 1 page, entry text read back out of the PDF |
| Share picker (all share actions) | Share sheet | Opened at the window's top-left corner | Anchored at the pointer | Builds; not exercised |
| Reader and insight pages: text | Long-press to select and copy | Not selectable | Selection enabled on the reader, Digest, Report, Mood, Ask (not on Brain's canvas) | Builds; not exercised |
| Icon buttons | n/a | Write's toolbar icons had no tooltips | `.help` on every Write icon button (reader already had them) | Builds |
| Windows | Titles in the app switcher | Title empty (hidden title bar) so the Window menu and Mission Control showed blanks | Title follows the page (Write, Entries, Today, Ask…), "New Entry" for the new-entry window | Read back from the running window: Entries, Today, Ask |
| Ask | Field focus on tap | Page opened with no focus | The question field is focused when the page opens | Builds; not exercised |

| Photo viewer (tap a photo in Write) | Full-screen cover with pinch and double-tap zoom | A sheet with no size: collapsed to a thin strip, photo cropped to a few pixels (user report) | Sized sheet (560x420 minimum, up to the screen), Done on the left (Esc closes), Share on the right | Opened from the harness: photo fits, Done and Share visible |
| Calendar, Year mode (Entries) | Grid under the header | Horizontal ScrollView stretched to fill the column, leaving a big empty gap (user report) | Frame at the grid's natural height | Before and after captures |
| First-run onboarding | Full-screen flow, five steps | Sheet with no size (user screenshot: just dots and a button); fifth step offers Sentinel, which Mac hides | Sized sheet (560x720); Mac flow ends at "Write your first entry" with "Start journaling" | Each step captured |

## Checked, nothing to fix
- Reminders: scheduled through `UNUserNotificationCenter` on Mac too, and tapping the check-in reminder sets `MoodCheckInPresenter.pending`, so the Log Mood sheet opens. A time-triggered popup (without tapping a notification) is a separate, later piece.

- Digest, Report, Mood, Ask, Brain: no gestures beyond buttons on iPhone, so no pointer gaps; Brain's 2D view uses drag and pinch (trackpad pinch maps to the same gesture).

## Open (not done yet)
- Today: iOS has a mood chart, streak and a Log mood button that the approved board does not show. Needs the owner's OK before adding visible UI.
- Write: daily word goal and word-goal UI from iOS (needs the owner's OK; not on the board).
- Mood timeline, Monthly report, Digest: no hover or keyboard work yet; Mood timeline chart has faint wedges inside the plot (area fill with several entries per day), likely also on iPhone.
- Ask: Esc, focus order and Tab order not checked. Brain View: pinch and trackpad pan untested.
- **Done (checked in code 2026-10-10):** Brain 2D mouse-wheel zoom (`BrainConstellationView.swift`, `scrollWheel`), and Report Left/Right arrows for the month switch (`MonthlyReportView.swift`, `onKeyPress(.leftArrow/.rightArrow)`). Not re-verified on hardware.
