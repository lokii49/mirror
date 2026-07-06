# mirror-loop state

The agent forgets each run. This file does not — read it before starting.

## Backlog

Seed source: SwiftUI `var body`/computed properties doing per-frame `.sorted`/`.filter`/`Dictionary(grouping:)`
work with no `.task`-cached equivalent (same bug shape as the fixes already benchmarked in
`mirrorTests/PerformanceXCTests.swift`). Re-scan `Features/**/*.swift` for this pattern before assuming the list below is complete.

Candidates found 2026-07-06, not yet done:
- `Features/Insights/InsightView.swift:401` — `dominantMoodThisWeek` (`Dictionary(grouping: moodEntries...)`), no cache
- `Features/Insights/InsightView.swift:1029` — `dominantMood` (`Dictionary(grouping: points...)`), no cache
- `Features/Insights/MonthlyReportView.swift:348` — `topMood` in `MonthlyStatsStrip`, no cache
- `Features/Entries/EntryDetailView.swift:25` — `.filter` over `allEntries` on every eval, check cost at scale

Already fixed / not backlog items (verified during discovery, do not re-add without new evidence):
- `Features/Entries/EntryListView.swift` — `listSnapshot` already `.task(id: snapshotDeps)`-cached
- `Features/Entries/CalendarHeatmap.swift` — `dayCache` already `.task(id:)`-cached

## Log

- [1] MoodTimelineView.swift heatmap chain (`allMoodPoints`/`dayMoodMap`/`heatmapWeeks`) recomputed on every body re-eval (range taps, paywall sheet) despite depending only on `entries`, not `selectedRange` — cached via `.task(id: entries.map(\.encryptedMood).hashValue)` into `@State` vars, matching `CalendarHeatmap.swift` precedent. Added `test_moodTimelineHeatmap_perFrameVsCached` to `PerformanceXCTests.swift`. Build gate + full mirrorTests target green. — **KEEP** (2.0.3, PR #17)
- [2] InsightView.swift:401 `dominantMoodThisWeek` — DISCARD (no code touched) — groups only current-week entries (few items), not a hot path
- [2] InsightView.swift:1029 `dominantMood` (MoodWeekChartView) — DISCARD (no code touched) — same, week-scoped subset
- [2] MonthlyReportView.swift:348 `topMood` (MonthlyStatsStrip) — DISCARD (no code touched) — one-month-scoped subset, trivial
- [2] EntryDetailView.swift:25 `onThisDayEntries` — DISCARD (no code touched) — full-history scan but runs once per detail-view open, not per-frame/animated; one-time cost is acceptable

## Blocked

- InsightView.swift dominantMood(ThisWeek), MonthlyReportView.swift topMood, EntryDetailView.swift onThisDayEntries — not a hot path by the seed heuristic's own definition (per-frame recompute on unrelated state). Outer-loop adjustment: the `Dictionary(grouping:)`/`.filter` grep is too broad a seed signal on its own — future scans must also check (a) dataset scope (week/month vs full history) and (b) whether the containing view has frequently-churning unrelated `@State` that retriggers body eval. Don't re-add without that evidence.

## Status

Backlog empty as of 2026-07-06 after honest re-scope — stopping per stop condition. Re-scan `Features/**/*.swift` fresh next run rather than trusting this file's stale candidate list.
