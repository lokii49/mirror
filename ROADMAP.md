# mirror Roadmap — 1.1.4+

## Bugs Fixed (1.1.4)
- [x] `moodScore` dict defined in two places → moved to `MirrorTheme`
- [x] `negativeMoods` set defined in two places → moved to `MirrorTheme`
- [x] `currentStreak` counted entries not calendar days → fixed to count unique days
- [x] `consecutiveNegativeCount` broke on mood-less entries → changed `break` to `continue`

---

## Week 1 — Visibility & Polish ✓
- [x] **Streak visible to all tiers** — flame pill in "Today" section header (all tiers, uses fixed day-counting logic)
- [x] **Ask usage counter always shown** — toolbar pill visible always for Core; colors escalate secondary → orange → red at ≤3/≤1

## Week 2 — History & Editing ✓
- [x] **Past monthly reports** — left/right month nav in heroCard; past months show cached report or "no report" card; current month uses full generation flow unchanged
- [x] **Entry time editing** — DatePicker sheet now shows graphical date + wheel time picker; presentationDetent expanded to .large

## Week 3 — Share & Memory ✓
- [x] **Share single entry** — already shipped (UIActivityViewController menu in EntryDetailView); marked done
- [x] **Daily nudge history** — collapsible "Past reflections (N)" row in Insights tab; shows last 14 nudges; each card expands inline; Core/Deep only

## Week 4 — Discovery & Habits ✓
- [x] **"On This Day"** — `EntryDetailView` shows past entries on same month+day in prior years (up to 3); shows year pill, mood dot, time, and first-line preview
- [x] **Writing reminder notification** — `NotificationService.scheduleWritingReminder(hour:minute:)` added; all-tier toggle + time picker in Settings → MirrorNotes section; separate from Core nudge

---

## Phase 2
- [x] **Sort options in Entries** — sort menu in toolbar: Newest, Oldest, Most Words, By Mood; applied within each month group; filter icon fills when non-default
- [x] **Daily word goal progress** — thin 2px progress bar above toolRow Divider; tracks total words written today across all entries + current draft; fills green on completion
- [x] **In-app model guidance** — `modelNotInstalled` state added to NudgeState/DigestState/MonthlyReportState; `ModelNotInstalledCard` rendered instead of generic error; step-by-step Gemma install instructions shown
- [x] **Blurred preview dedup** — `MoodChartCard(points:)` extracted; `moodChartCard` and `previewMoodChartCard` both delegate to it; ~37 lines removed
- [x] **Reduce WriteView @State sprawl** — undo snapshot vars (12×) consolidated into `DraftUndoSnapshot` struct; `@State var undoSnapshot` replaces all; sort toolbar extracted to `trailingToolbar` computed var
- [x] **Export to plain text / PDF** — bulk text export (Settings ShareLink already shipped); per-entry text share (EntryDetailView already shipped); PDF export added via `UIMarkupTextPrintFormatter`+`UIPrintPageRenderer`; "Export as PDF" in entry ellipsis menu
- [x] **iPad split view layout** — `NavigationSplitView` on `.regular` size class; sidebar lists all 4 sections (Entries/Write/Insights/Settings); TabView preserved for iPhone; Settings surfaced as first-class sidebar item on iPad (no longer sheet-only)
