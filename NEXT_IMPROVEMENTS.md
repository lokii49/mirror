# Next Improvements — Post Phase 2

Phase 2 complete on branch 1.1.4. All 6 post-phase-2 items shipped.

---

## 1. iPad sizeClass flip sync ✅
`onChange(of: sizeClass)` added to `ContentView`. Maps `selectedTab` ↔ `selectedSidebarItem` on multitasking resize in both directions.

## 2. PDF page size fix ✅
`EntryDetailView.makePDF()` — `UIGraphicsBeginPDFContextToData` now passes `CGRect(origin: .zero, size: pageSize)` instead of `.zero`. A4 (595×842pt) respected.

## 3. Ask counter month-boundary reset ✅ (already correct)
`thisMonthCount` in `AskView` is a computed var that filters SwiftData `Insight` records by `DateHelpers.monthIdentifier(for: Date())` on every read. Counter resets lazily the moment the month rolls over — no scheduled reset needed. No code change required.

## 4. Entry search — tag filter ✅
`SearchService.search()` and `SearchService.filter()` now match query against `entry.tags` in addition to `entry.insightContext`. `filter()` also strips a leading `#` so `#work` finds entries tagged `work`.

## 5. Voice note language display ✅ (already implemented)
`VoiceNoteAttachmentView` already shows `languageName` in the duration row; `WriteView` already passes `languageName: note.languageName`. No code change required.

## 6. Widget deep-link expansion ✅
- `mirror://nudge` → Insights tab (same as `mirror://insights`).
- `mirror://entry/<uuid>` → parses UUID from path, sets `deepLinkEntryID` state in `ContentView`, navigates to Entries tab, `EntriesTabView.onChange` finds the entry and pushes `EntryDetailView`.
