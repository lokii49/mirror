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
- `Features/Settings/SettingsView.swift` — already `.task(id: entries.count)`-cached
- `Features/Write/WriteView+Subviews.swift` — `dailyWordCount` now cached, see Log [3]
- `Features/Insights/AskView.swift` — `askHistory`/`chatHistory`/`thisMonthCount` now cached, see Log [5]
- `Features/Insights/InsightView.swift` — `moodEntries`/`thisMonthEntries`/`currentStreak`/`pastNudges` now cached, see Log [6]
- `Features/Write/WriteView+Tags.swift` `filteredTagSuggestions` — DISCARD (2026-07-07, no code touched) — operates on `existingTagSuggestions`, a small @State array populated once via `computeTagSuggestions()` when the tag input opens (`WriteView.swift:360`), not per-keystroke; already-filtered-subset false positive
- `Features/Insights/InsightViewModel.swift` `thisMonthEntries`/etc. — DISCARD (2026-07-07, no code touched) — these run inside `async func load*` methods called from `.task`/`.onChange`, not from a view `body`; not per-frame

## Log

- [1] MoodTimelineView.swift heatmap chain (`allMoodPoints`/`dayMoodMap`/`heatmapWeeks`) recomputed on every body re-eval (range taps, paywall sheet) despite depending only on `entries`, not `selectedRange` — cached via `.task(id: entries.map(\.encryptedMood).hashValue)` into `@State` vars, matching `CalendarHeatmap.swift` precedent. Added `test_moodTimelineHeatmap_perFrameVsCached` to `PerformanceXCTests.swift`. Build gate + full mirrorTests target green. — **KEEP** (2.0.3, PR #17)
- [2] InsightView.swift:401 `dominantMoodThisWeek` — DISCARD (no code touched) — groups only current-week entries (few items), not a hot path
- [2] InsightView.swift:1029 `dominantMood` (MoodWeekChartView) — DISCARD (no code touched) — same, week-scoped subset
- [2] MonthlyReportView.swift:348 `topMood` (MonthlyStatsStrip) — DISCARD (no code touched) — one-month-scoped subset, trivial
- [2] EntryDetailView.swift:25 `onThisDayEntries` — DISCARD (no code touched) — full-history scan but runs once per detail-view open, not per-frame/animated; one-time cost is acceptable
- [3] WriteView+Subviews.swift `dailyWordCount` filtered+reduced the full-history `allEntries` @Query on every read; `toolRow` (part of `body`) reads `viewModel.wordCount` directly and that `@Observable` property updates on every keystroke while typing, so this full-history scan ran on every character typed in the editor — likely the highest-frequency instance of this bug shape found so far. Cached the saved-history portion into `@State var cachedSavedWordCountToday` via `.task(id: allEntries.count)` on `WriteView.swift`, matching `CalendarHeatmap`/`MoodTimelineView` precedent; `dailyWordCount` now reads the cache and only adds the live `viewModel.wordCount` per keystroke. Added `test_dailyWordCount_perKeystrokeVsCached` to `PerformanceXCTests.swift`. NOT build/test-verified (no Xcode/simulator in this sandbox) — awaiting local xcodebuild + mirrorTests run. — proposed (2.0.4, PR #18, branch `loop/writeview-dailywordcount-cache`)

- [4] 2026-07-07 local verify: PR #18 (WriteView dailyWordCount cache, cloud-proposed) was merged by user before local verification — ran gates retroactively: build green, mirrorTests 91/91 pass incl. new test_dailyWordCount_perKeystrokeVsCached. — KEEP (verified post-merge)
- [5] AskView.swift `chatHistory` filtered+sorted the full-history `allInsights` @Query (all `InsightType` cases, no date/range predicate) on every read; `content` (part of `body`) reads it via `ForEach(chatHistory)`, and the view holds `@State private var question`/`keyboardHeight`/`isInputFocused` that churn on every keystroke/keyboard event while the Ask chat is open, so this ran on every character typed. Cached `askHistory`/`chatHistory` into `@State` (`cachedAskHistory`/`cachedChatHistory`) via `.task(id: allInsights.count)` on `AskView.swift`, matching `CalendarHeatmap`/`MoodTimelineView`/`WriteView` precedent; `thisMonthCount` now filters the cache too. Added `test_askViewChatHistory_perKeystrokeVsCached` to `PerformanceXCTests.swift`. NOT build/test-verified (no Xcode/simulator in this sandbox) — awaiting local xcodebuild + mirrorTests run. — proposed (2.0.4, PR #19, branch `loop/askview-chathistory-cache`)

- [6] 2026-07-07 InsightView.swift: `moodEntries`, `thisMonthEntries`, and `currentStreak` each scan the full-history `entries` @Query with no date/range predicate already applied, and `pastNudges` filters+sorts the full `insights` @Query — all four are read directly from `body`/its always-evaluated section subviews (`nudgeSection`, `explorationSection`, `pastNudgesSection` guard, `MoodWeekChartView`), so every unrelated `@State` toggle in this view (`nudgeExpanded`, `digestExpanded`, `pastNudgesExpanded`, any sheet) re-ran all four from scratch, some multiple times per single body eval. This refines the earlier (2026-07-06, Log [2]) `dominantMoodThisWeek` DISCARD: that assessment only looked at the `Dictionary(grouping:)` step in isolation (correctly cheap, small week-scoped input) and didn't examine that its input (`moodEntries`) is itself an uncached full-history scan read directly from `body`. Cached all four into `@State` (`cachedMoodEntries`/`cachedThisMonthEntries`/`cachedCurrentStreak`/`cachedPastNudges`) via `.task(id: entries.count)` / `.task(id: insights.count)`, matching `CalendarHeatmap`/`MoodTimelineView`/`WriteView`/`AskView` precedent. Added `test_insightViewBodyRecompute_perToggleVsCached` to `PerformanceXCTests.swift`. NOT build/test-verified (no Xcode/simulator in this sandbox) — awaiting local xcodebuild + mirrorTests run. — proposed (2.0.4, PR #20, branch `loop/insightview-fullhistory-cache`)

## Blocked

- InsightView.swift dominantMood(ThisWeek)'s own `Dictionary(grouping:)` step, MonthlyReportView.swift topMood, EntryDetailView.swift onThisDayEntries — not a hot path by the seed heuristic's own definition (per-frame recompute on unrelated state). Outer-loop adjustment: the `Dictionary(grouping:)`/`.filter` grep is too broad a seed signal on its own — future scans must also check (a) dataset scope (week/month vs full history) and (b) whether the containing view has frequently-churning unrelated `@State` that retriggers body eval, AND (c, added 2026-07-07) trace one level *into* the inputs of a cheap-looking computed property — a small-input step can still sit downstream of an uncached full-history scan (see Log [6]). Don't re-add without new evidence.

## Status

PR #18 (WriteView `dailyWordCount` cache) was merged and verified locally (91/91 mirrorTests pass) — see Log [4]. PR #19 open against 2.0.4 (branch `loop/askview-chathistory-cache`) for the AskView `chatHistory` fix — awaiting local Xcode build/test verification before merge. PR #20 opened against 2.0.4 (branch `loop/insightview-fullhistory-cache`) this run for the InsightView `moodEntries`/`thisMonthEntries`/`currentStreak`/`pastNudges` cache — awaiting local Xcode build/test verification before merge. Re-scan `Features/**/*.swift` fresh next run rather than trusting this file's stale candidate list.

## Product decision (2026-07-07)

- WriteView word-goal bar is now **per-entry** (`viewModel.wordCount / dailyWordGoal`), by user decision — the daily cumulative `dailyWordCount` + `cachedSavedWordCountToday` cache (PR #18) was removed. Do NOT re-propose caching a daily word count in WriteView; the full-history scan no longer exists. `test_dailyWordCount_perKeystrokeVsCached` kept as a standalone benchmark.
