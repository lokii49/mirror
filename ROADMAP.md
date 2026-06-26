# mirror Roadmap — 1.1.4+

## Bugs Fixed (1.1.4)
- [x] `moodScore` dict defined in two places → moved to `MirrorTheme`
- [x] `negativeMoods` set defined in two places → moved to `MirrorTheme`
- [x] `currentStreak` counted entries not calendar days → fixed to count unique days
- [x] `consecutiveNegativeCount` broke on mood-less entries → changed `break` to `continue`

---

## Week 1 — Visibility & Polish
- [ ] **Streak visible to all tiers** — add streak pill to Insights tab header (currently Deep-only via MoodTimeline)
- [ ] **Ask usage counter always shown** — show "X/15 used" in askHeader always, not only at ≤3 remaining

## Week 2 — History & Editing
- [ ] **Past monthly reports** — add month picker to MonthlyReportView; reports already cached by `periodIdentifier`
- [ ] **Entry time editing** — add time component to DatePicker in WriteView (currently date-only)

## Week 3 — Share & Memory
- [ ] **Share single entry** — add `ShareLink` to EntryDetailView (plain text export)
- [ ] **Daily nudge history** — past nudges browsable below today's card; already stored in SwiftData

## Week 4 — Discovery & Habits
- [ ] **"On This Day"** — surface entries from same date in past years in EntryDetailView or Insights
- [ ] **Writing reminder notification** — daily "time to write" push if user hasn't written today (separate from nudge)

---

## Phase 2
- [ ] **Sort options in Entries** — sort by word count, mood, oldest-first (currently newest-first only)
- [ ] **Daily word goal progress** — `dailyWordGoal` AppStorage exists; surface progress bar in write toolbar
- [ ] **In-app model guidance** — if Gemma missing, guide user to download instead of raw error path
- [ ] **Blurred preview dedup** — `blurredDeepPreview` in MoodTimelineView has ~200 lines of duplicated mock views; parameterize real views
- [ ] **Reduce WriteView @State sprawl** — 40+ @State vars; extract draft state into a struct
- [ ] **Export to plain text / PDF** — per-entry and bulk export (Notion/Obsidian Phase 2 per CLAUDE.md)
- [ ] **iPad split view layout**
