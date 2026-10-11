# MirrorNotes roadmap

**The single roadmap.** Day-to-day work for the current branch lives in that branch's backlog (now `3.1.2-backlog.md`). Bigger plans sit beside it: `3.1.2-iphone-duo.md` and `november-paid-activation.md`. This file keeps what is open across releases, the gates and the settled decisions. Consolidated 2026-10-11 from `3.1.0-roadmap.md`, `3.0.9-product-plan.md`, `platform-roadmap.md`, `macos-design-plan.md` and `mac-parity-audit.md`, which were then deleted. Read them in git history (before the deleting commit) if a detail is missing here.

**Legend.** **[owner]** needs the owner's hands (signed build, device, App Store Connect, a decision). **[rig]** needs an llmrig round first (N ≥ 10, rubric written before running). **[unverified]** comes from earlier notes.

---

## Where it stands (2026-10-11)

| | Status |
|---|---|
| iOS 3.1.1 (18) / Mac 1.1.1 (18) | Submitted 2026-10-10, automatic release [unverified: check ASC]. Merged to `main` (PR #52). |
| 3.1.2 | In progress on branch `3.1.2`. The audit's A list, translations (B), dormant paid-tier fixes (C), hygiene (F) and part of E are done; see `3.1.2-backlog.md`. |
| Paid tiers | `allFeaturesFree = true`: everyone is Deep. Paid gating returns in a November build (`november-paid-activation.md`). |
| Downloads | Unknown. The July audit found ~0 [unverified now]. Pull App Analytics before growth spend. |

## Before 3.1.2 ships
- **iPhone Duo support (owner, 2026-10-11):** the Duo ships Oct 23, and the live 3.1.1 (iOS 27.1 SDK) already renders natively on it. Plan: `3.1.2-iphone-duo.md` (audit → must-fix → Duo design → submit by about Oct 20). The remaining E items move to 3.2.0.
- [owner] Native-speaker review of model-translated strings: everything marked `needs_review`. That covers release notes 3.0.7–3.1.1, the Write view, reflection styles, the search model, What's New, the privacy policy, plus all of 3.1.2's B work and the A16/A18 labels.
- [owner] Siri phrases and the nudge notification in a non-English system language.
- [owner] Device checks (`3.1.2-backlog.md` D3, D5, D6). These are listed under "Verify in production" below.
- Version bump (iOS 3.1.2 / Mac 1.1.2) and 10-locale release notes. No CloudKit schema change in 3.1.2 so far.

## November: paid activation
Plan and open questions: `november-paid-activation.md` (grace period, in-app notice about 2 weeks ahead, then gating with the 7-day trial). The release gate is under "Acceptance gates".

---

## Open work

### Collections and organization
- Multi-select bulk move (the store has `JournalOrganizationStore.move(_:to:in:)`; the UI needs a design call: Select mode, toolbar action, both themes, iPhone and Mac) [owner: design].
- Icon and colour pickers (the model has `icon`/`colorIndex`; no UI).
- Ask collection filter.
- Mac sidebar section for collections and saved views.

### Mac
- Today board: mood chart, streak and Log Mood from iOS [owner: OK to add visible UI].
- Write: daily word goal [owner: OK].
- Time-triggered check-in popup (the reminder notification is built; a popup without a click isn't).
- Hover and keyboard on Mood timeline, Monthly report and Digest. Ask: Esc, focus order, Tab order. Brain View: trackpad pinch and pan.
- Two "New Entry" windows open at once share one draft slot (per-window identity and restoration needed).
- Mac App Store screenshots, translations of new Mac strings [owner].
- Deferred [owner]: Sentinel on Mac.

### Reflections and AI (every item here is [rig])
- FM quoting the prompt's `Mood: X. Source: written entry.` line (19% fallback on round 12's held-out cases vs 3.6% in CLAUDE.md).
- Hospital-day wording: two variants got through 10/10 where the shipped prompt was refused 10/10.
- `SecondQuoteTests` fails on iOS 27.1 (NLTagger treats sentence-initial "Exam" as a name → `FMDailyGuard.restoreNames`).
- Model-written reflection styles: Plain and Question FAILED round 12; nothing new without a passing round.
- Deferred [owner]: FM daily reflection with today-only context (the rig never tested the background brief).

### Writing and editor
- `NoteEditorRenderCostTests` stops at 10k characters; reader and Mac thumbnails for unreadable photos unchecked.
- Bump `PhotoMarkerRepair.flag` to `.v2` in the first release after most devices are off 3.0.9 [owner].
- Won't do now: incremental editor read-back (11.2 ms per keystroke at 50k is inside a frame; revisit only if real entries get much longer).

### Search and Ask
- Japanese keyword search: questions have no spaces; try `NLTokenizer`.
- Measure it/pt/ru/ko/zh in the retrieval rig.
- To replace the hosted embedding model, publish a new path and SHA, never the same URL.

### Export
- [owner] Open the exported package in Obsidian and Notion and document fidelity limits. No compatibility claims before that.

### Stretch
- Source citations for Ask, digest and report (audit existing source metadata first; quotes must match the source).
- Entry links and backlinks; related moments.
- Custom templates (may overlap reflection styles).

### Tests
- `macNightlyIsDue`, `MacQuickCaptureModel`, `MacGlobalHotKey`, the Mac reader and PDF export: untested (`mirrorTests` is iOS-only).
- `DailyReflectionTimingTests` skip silently without a model; five screenshot-only tests assert nothing (`3.1.2-backlog.md` E).
- `DocumentScannerTests` hangs when the phone locks.

### Platform
- visionOS: start with the "Designed for iPad" availability toggle (no code), then a native target sharing the Mac abstractions. Brain View is the spatial candidate. llama.cpp has the `xros-arm64` slice; add `.visionOS(.v1)` to `SwiftLlama/Package.swift` when needed.

---

## Verify in production [owner]
- Install over the previous version; sheet layout on iOS 17/18.
- Restore offer and local backup (`LocalJournalBackup`, `JournalRestoreCopy`); whether `JournalSafety`'s `eventChangedNotification` fires under SwiftData (if not, "Not backed up" never shows).
- Widget and lock screen never show the second quote.
- Hospital-day `refusedDayNudge` on an Apple Intelligence device.
- Two devices plus a 3.0.8 client keeping `collectionID`; cross-device Delete Everything.
- Real ja/zh/ko keyboards; shake, three-finger undo and iPad ⌘Z; VoiceOver pass and accessibility text sizes; manual kill-and-relaunch draft check.
- Mac signed build: Touch ID, ⌥⌘J under the sandbox, a real check-in notification click, widgets on hardware, backup on resign-active, the app-switcher cover, What's New, widget window reuse.
- Notification Content Extension on a real device (the 3.1.2 build was checked on the 14 Pro in English).

---

## Growth (owner-led, parallel)
Order, measuring after each step (impressions → page views → installs → trials) before stacking channels:
1. Apple Search Ads, $10/day for two weeks.
2. Show HN, Thursday 9 AM–12 PM ET ("on-device AI journal, now on Mac, never invents what you didn't write").
3. Product Hunt relaunch with the Mac app as the news.
4. Promo-allowed subreddits: r/SideProject, r/iosapps, r/BuildInPublic, r/indiehackers.
5. Mac channels: Mac App Store editorial nomination, MacStories / 9to5Mac tips.
6. Housekeeping:
   - Four awesome-list PRs are still open as of 2026-10-11: tehtbl/awesome-note-taking#89, dreamingechoes/awesome-mental-health#78, pluja/awesome-privacy#879, janhq/awesome-local-ai#131. Bump or close them.
   - The mirrornotes.app name collision can't be fixed: win on mirrornotes.org SEO and App Store search.

App Store title "MirrorNotes: AI Journal, Diary" and the "adhd" keyword are live in all 10 locales (checked 2026-10-07). The 24/7 marketing routine is disabled (2026-09-20).

---

## Acceptance gates (carried from the 3.0.9 product plan)
- **Search:** combined filters, quotes/exclusions, diacritics, CJK, empty queries, unavailable keys, edits/deletes/sync and transcript updates behave the same on both platforms. Highlights stay accurate after Unicode normalization. Warm search p95 ≤ 150 ms at 2,000 entries and ≤ 300 ms at 5,000 (measured 2026-10-09: 39 / 98 ms).
- **Saved views:** survive restart and sync, keep Any/All semantics and sort, handle timezone and day changes. Concurrent edits need a documented conflict policy and a real two-device test.
- **Writing:** force-quit and backgrounding during edits or media saves never lose acknowledged draft content. Failed writes never show Saved. IME text never duplicates or disappears. Long-entry typing p95 ≤ 50 ms input-to-frame.
- **Collections:** moving, deleting and renaming work offline and sync. Missing collection references resolve visibly without hiding entries. Collections and saved views take part in Delete Everything, backup/restore and export/import. Test sync arrival order and concurrent deletion vs movement.
- **Export/import:** round-trip text, formatting, dates, moods, tags, collection membership, photos, audio and transcripts (synthetic fixtures). Duplicate filenames and Unicode are safe. Interrupted or low-storage runs preserve the journal. UUID collisions, path traversal and size limits are tested.
- **Links (if built):** rename/preview changes, target deletion, sync order, partial export, cyclic links and round-trip imports work. Backlinks are authored references only, never inferred.
- **Paid release:**
  - live product configuration checked;
  - signed iOS/Mac purchase lifecycle passed;
  - free access confirmed;
  - migration and restore passed;
  - transition policy final;
  - store text and paywall truthful.
  - `allFeaturesFree` flips only as part of that release. Never infer entitlement failure from a network error. No journal text in analytics.

## Sync and CloudKit notes (carried from the platform roadmap)
- Sync needs the same container (`iCloud.com.lokesh.mirror`) in every target's entitlements, the same Apple ID with iCloud on, and the **same CloudKit environment**. TestFlight and App Store builds use Production; Xcode-run builds use Development and won't see App Store data.
- New `@Model` types or fields need the schema deploy to Production before any TestFlight/App Store build (seed with `--seedCloudKitSchema` on a simulator signed into iCloud, then delete the seed rows).
- Sync is eventual and rides on silent push.
- Insights stay in the one synced store (decision 2026-10-01): the Ask cap and the 24h cache count `Insight` rows. If duplicate reflections ever appear across devices, de-duplicate on `periodIdentifier` rather than splitting the store.
- Mac has no `BGTaskScheduler`. Generation runs on app-active plus a 3–6 AM `NSBackgroundActivityScheduler` pass while the app is open; a closed Mac catches up at the next launch.

---

## Standing rules
- CLAUDE.md security rules apply; fixtures and rig cases use synthetic text only.
- Any prompt, `@Guide`, guard or grammar change needs an llmrig round first (N ≥ 10, rubric first).
- New CloudKit record types need the schema-deploy gate.
- Device tests run on the iPhone 14 Pro with a separate bundle id (`tools/testing/`), never the real app; ask before using the iPhone 13.
- New features are standalone surfaces (own sheet, storage, entry point) unless asked otherwise.

## Settled: don't reopen without new evidence
- Longer FM reflection (2–3 sentences, V1f): FAILED rig round 10.
- Extra app-built lines (mood trend, theme, streak): declined; only the second quote shipped.
- Loosening the Gemma grammar back to free prose: measured ~0/40 faithful.
- "Practical" reflection style (a tip every day): rejected; good and neutral days get no tip.
- Save keeps switching to Entries (Write view UX item 7, owner 2026-10-09).
- Journal key stays `WhenUnlocked` (owner 2026-10-11): background generation while locked is a no-op.
- Native macOS, not Catalyst (llama.cpp has no Catalyst slice).

**Never:** Android, web, social features.
