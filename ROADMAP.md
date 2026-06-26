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
- [ ] **In-app model guidance** — if Gemma missing, guide user to download instead of raw error path
- [x] **Blurred preview dedup** — `MoodChartCard(points:)` extracted; `moodChartCard` and `previewMoodChartCard` both delegate to it; ~37 lines removed
- [ ] **Reduce WriteView @State sprawl** — 40+ @State vars; extract draft state into a struct
- [ ] **Export to plain text / PDF** — per-entry and bulk export (Notion/Obsidian Phase 2 per CLAUDE.md)
- [ ] **iPad split view layout**
