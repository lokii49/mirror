<!-- Copy of the workspace CLAUDE.md (mirror-workspace/CLAUDE.md), committed 2026-10-10 so Claude cloud sessions get the project rules. Paths below are written from the workspace folder: "mirror/tools/...", "mirror/.claude/..." and "mirror/Packages/..." are "tools/...", ".claude/..." and "Packages/..." from this repo root; "mirror/Core/..." and "mirror/Features/..." are the same. Keep both copies in sync. -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

**mirror** — a local-first, privacy-first AI journaling iOS app. All AI runs on-device (Gemma 3 1B via `LocalLLMService`). No cloud AI backend.

**Spec docs** (`mirror-technical-spec.md`, `mirror-ios-backend-implementation.md`, `mirror-claude-code-prompts.md`) describe an earlier Cloudflare Worker + Supabase architecture that has been superseded. **CLAUDE.md is now canonical.** Ignore any spec doc references to Cloudflare Worker, Claude API, `worker.ts`, Supabase, or Apple Sign In.

- `mirror-strategic-features.md` is referenced by earlier notes as the product-strategy doc but is not present in this repo — treat any claim sourced to it as unverified until it's found or rewritten.

---

## Architecture

> **UPDATED**: AI runs fully on-device via local LLM (Gemma 3 1B). `worker.ts` and Cloudflare Worker path are retired. Prompts live in `InsightService.swift` only.

```
iOS (SwiftUI + SwiftData)
├── Local storage: SwiftData
├── Cloud sync: CloudKit (automatic, free, private)
└── AI: LocalLLMService (Gemma 3 1B, on-device, no network)
```

**Core privacy guarantee**: Journal entry text NEVER leaves the device. All AI inference is on-device. No server, no logging, no database for journal data. Only the generated insight is saved (on-device via SwiftData).

**SwiftData replaces SQLite** — iOS 17+. CloudKit sync is one line: `ModelConfiguration(cloudKitDatabase: .automatic)`. No custom SyncService needed.

**Local LLM replaces Cloudflare Worker** — `LocalLLMService.swift` runs Gemma 3 1B on-device. All system prompts live in `InsightService.swift`. `worker.ts` is retired.

**RevenueCat** — sits between app and Apple IAP. Handles purchase flow, receipt validation, renewal, cancellation, webhooks.

---

## Subscription Tiers

| Feature | Free | Core ($2.99/mo or $29.99/yr) | Deep ($4.99/mo or $49.99/yr) |
|---------|------|------------------------------|------------------------------|
| Write entries (unlimited, forever) | ✓ | ✓ | ✓ |
| Read all past entries | ✓ | ✓ | ✓ |
| Full-text search (local) | ✓ | ✓ | ✓ |
| iCloud backup | ✓ | ✓ | ✓ |
| Daily Nudge | ✗ | ✓ | ✓ |
| Ask (15x/month) | ✗ | ✓ | ✗ |
| Ask (unlimited) | ✗ | ✗ | ✓ |
| Weekly Digest | ✗ | ✓ | ✓ |
| Home screen widget | ✗ | ✓ | ✓ |
| Monthly Deep Report | ✗ | ✗ | ✓ |
| Mood Timeline + full analytics | ✗ | ✗ | ✓ |
| Mood Alerts (3 consecutive negatives) | ✗ | ✗ | ✓ |

**Free tier principle**: "Your data is always yours. You pay for the AI layer. Never punish free users for writing." Free users get ALL their entries, ALL history, forever. No 30-day limit.

**Ask cap**: Core = 15/month. Deep = unlimited. Cut immediately — no grandfathering.

App Store Connect products:
- `mirror_core_monthly` — $2.99/mo, 7-day free trial
- `mirror_core_yearly` — $29.99/yr (~16% savings), 7-day free trial
- `mirror_deep_monthly` — $4.99/mo, 7-day free trial
- `mirror_deep_yearly` — $49.99/yr (~17% savings), 7-day free trial

RevenueCat setup:
- Entitlement `core` — maps to mirror_core_monthly + mirror_core_yearly
- Entitlement `deep` — maps to mirror_deep_monthly + mirror_deep_yearly
- Offering `core` — contains mirror_core_monthly + mirror_core_yearly
- Offering `deep` — contains mirror_deep_monthly + mirror_deep_yearly

---

## AI Model

`LocalLLMService` routes each generation through `FoundationModelEngine` (Apple's on-device Foundation Models framework, iOS 26+, Apple Intelligence-capable devices only) whenever it is available, and uses bundled **Gemma 3 1B** (llama.cpp) only when it is not — unsupported OS, ineligible device, Apple Intelligence off, or model not ready — or when Foundation Models cannot work in the text's language (Russian today: `FoundationModelEngine.supports(languageCode:)`). **A device that has Foundation Models never falls back to Gemma after a Foundation Models failure** (guardrail refusal, exhausted context): the error reaches the caller, which shows its own honest card (since 2026-10-02). `InsightService` doesn't branch behavior on which engine ran, but `LocalLLMService.generate` does report it (`LLMEngine`, `.foundationModels`/`.gemma`) for diagnostic attribution — saved on `Insight.generatedByEngine`, synced, never shown in the UI. No cloud API, no cost per user either way.

**System prompts** live in `mirror/Core/Services/InsightService.swift` — `DAILY_REFLECTION_FM_SYSTEM`, `DAILY_NUDGE_GEMMA_INSTRUCTIONS`, `WEEKLY_DIGEST_SYSTEM`, `WEEKLY_DIGEST_GEMMA_INSTRUCTIONS`, `ASK_SYSTEM`, `MONTHLY_REPORT_SYSTEM`, `MONTHLY_REPORT_GEMMA_INSTRUCTIONS`, `EMOTION_DETECT_SYSTEM` (`DAILY_NUDGE_LEGACY_SYSTEM` is retired: never sent, kept so "How this was generated" can show it for older reflections). Edit there, not here.

**Daily nudge, weekly digest and monthly report on Gemma are grammar-constrained (since 2026-09-26/27)**: English ones that run on Gemma use `*_GEMMA_INSTRUCTIONS` plus a GBNF grammar (`groundedNudgeGrammar` / `groundedDigestGrammar` / `groundedMonthlyGrammar`) that forces `You wrote, "<verbatim sentence from the entry>" You seem…/That sounds…`. For the daily reflection, Gemma writes only that one feeling sentence (since 2026-09-30). On difficult moods the app appends a fixed tip (`groundedNudgeTips`); good and neutral days get none. With a tip slot, Gemma added a tip ~100% of the time, whatever the mood. About half were breathing or mindfulness, and about a fifth were walk or tea. Don't loosen it back to free prose: with the old free-prose prompt (now `DAILY_NUDGE_LEGACY_SYSTEM`), Gemma 3 1B measured ~0/40 faithful (invented "The rain outside…" openers), and even a faithful free-prose prompt swaps people/turns plans into events. Outside English (de/es/fr/it/pt/ru/ja/ko/zh), Gemma only *picks* the quoted sentence(s) and the app composes fixed translated text around them (`groundedLocales` in InsightService.swift) — edit those strings there. **Follow-up chip on Gemma is grounded too (since 2026-09-28).** Gemma picks one numbered part of the draft under a literal grammar, and the app composes the question around it (`What's underneath "…"?`). The code is `groundedFollowUpPlan` + `FOLLOW_UP_GEMMA_*` in InsightService.swift. The other languages' strings are `pickFollowUp`/`partsLabel`/`followUpQuestion` in `groundedLocales`, generated from `mirror/tools/i18n/grounded_locales.py`. Languages outside the 10 get no chip on Gemma. Talk It Out's guided questions are still free prose (rig: 67/70 invented nothing).

**The daily reflection on Foundation Models is structured, one prompt for every language it supports (since 2026-10-02).** Free prose invented something in ~95% of English FM outputs on a strict pass, so FM fills two `@Generable` fields with `DAILY_REFLECTION_FM_SYSTEM` (`FoundationModelEngine.generateDailyReflection`): a quote and a short insight. *English:* the app finds the quote in today's entries and shows it in the entry's own words, and the insight is checked sentence by sentence by `FMDailyGuard` (feeling words from the entry or its mood, no invented names/scenery/"never before", no "feel missing"); up to 3 attempts (`InsightService.structuredFMNudge`), saved as `You wrote, "…" …` with the fixed `groundedNudgeTips` on hard days; if all fail, a fixed mood line after the verified quote, else the honest card; Gemma never answers there. Measured shown PASS 98% (fallback 3.6%), `mirror/tools/llmrig/fm/RUBRIC_FM.md`; on round 12's 10 fresh held-out cases (2026-10-09) fallback was 19% (81/100 shown), with one case at 10/10, where FM quoted the prompt's `Mood: X. Source: written entry.` line. See RUBRIC_FM.md round 12. *de/es/fr/it/pt/ja/ko/zh:* the same prompt plus the "respond in <language>" line; the model's quote is kept only if `FMDailyGuard.matchOption` finds it among the entry's own quotable sentences (characters, not words; a quote that is the whole entry becomes its first sentence), then the app's fixed translated mood line from `groundedLocales` follows (`InsightService.structuredFMLocalizedNudge`). The model-written insight is NOT shown outside English: `FMDailyGuard` is English word lists and cannot vouch for it. Round 9: 240/240 shown, 0 errors. *Russian* (not on Apple's list) stays on Gemma's grammar path. *Any other language* (nl, sv, da, tr, vi …) gets the honest card: no model runs. Change the prompt, the `@Guide` text, `FMDailyGuard` or the matcher only with a new rig round. Digest/monthly/Ask on FM are unchanged. A longer FM insight (2-3 sentences, V1f) FAILED rig round 10 (2026-10-04): it rewrote quotes and the extra sentences were mostly recitation or nonsense, so the guard still keeps at most 2. **FM declines ordinary days set at a hospital, clinic, ICU, funeral home, therapist, court or police station** (round 11; arrives as `LanguageModelError.refusal`, see `FoundationModelEngine.isSafetyRefusal`): when all 3 attempts are declined, `refusedDayNudge` shows the day's first sentence and the fixed mood line, with no tip. Round 12 lead (untested as a fix): two prompts that changed only the insight wording got through on the hospital case 10/10 while the shipped one was refused 10/10.

**English reflections are shown with an app-picked second quote (since iOS 3.0.8 / Mac 1.0.1).** Where the app renders today's reflection (iOS card in both themes, Mac board, "How this was generated"), an English grounded reflection gets `You also wrote, "<sentence>"` before any hard-day tip: another whole sentence from the same day's entries, word for word, chosen by `InsightService.secondGroundedQuote` (longest whole sentence of at least 4 words ending in .!?…, no quote marks, not overlapping the main quote; nothing when there isn't one). No model writes or picks it. **It is never stored in `Insight.content`**: `reflectionWithAlsoQuote` builds it at display time, because reflections sync and 3.0.7 / Mac 1.0 and earlier would read a stored second quote with their old parsers (leaking it to the widget and lock screen). The widget, notifications and past-reflection rows show the stored text unchanged.

**Reflection styles (since 3.1.0, branch `3.1.0`).** Settings > Journal > Reflection (Core only) picks how *today's* reflection reads in the app: Gentle (today's shape), Quiet (the verified quote only, plus the English second quote), Curious (the quote plus the app-built follow-up question; falls back to Gentle when the entry has nothing else to ask about). Nothing is model-written. Like the second quote it is display-time only: `InsightService.reflectionForDisplay` (in `ReflectionStyle.swift`) wraps `reflectionWithAlsoQuote`, `Insight.content` stays in the Gentle shape old versions parse, and the widget, notifications, past-reflection rows and "How this was generated" show the stored text. Per device (`@AppStorage("reflectionStyle")`), no CloudKit schema. A model-written style needs an llmrig round first: Plain and Question both FAILED round 12 (2026-10-09), so none is built; "Practical" (a tip on every day) was rejected because good and neutral days get no tip. Design: `mirror/.claude/3.1.0-reflection-styles.md`.

Measure prompt changes off-device with `mirror/tools/llmrig` (README has method + numbers) before shipping them.

---

## MVP Scope — Do NOT Build

```
❌ Android / Web
(Mac, then visionOS: on the platform roadmap — see `mirror/.claude/platform-roadmap.md`)
❌ Social features (never — private by design)
❌ Export to Notion/Obsidian (Phase 2)
❌ Multiple journals / folders (Phase 2)
❌ Custom AI personas (Phase 3)
```

> Mood timeline, Monthly deep report, and Mood alerts are now **shipped** as Deep tier features.

---

## Shipped Beyond This Spec (as of 2.0.9)

The app has grown past what the rest of this doc describes. Not exhaustive, but these are load-bearing and not documented elsewhere in this file:

- **Sentinel mode** — an alternate full-app theme (mono/ember visual language, renamed nav: Comms/Briefing/Log/Transmission) toggled in Settings, running parallel to the default theme via `@Environment(\.appDisplayMode)` branches throughout the view layer. Every such branch is a place the two themes can silently diverge — check both when touching a themed view.
- **Brain View** (`Features/Insights/BrainView*.swift`) — a constellation visualization of recurring entry terms, Deep tier only. Backed by `ThemeExtractionService`.
- **Foundation Models engine** — see AI Model section above.
- **`GamificationEngine`** (`Core/Utilities/`) — XP, levels, and `SentinelRank` derived from entry history.
- **Siri App Intent** — `AddJournalEntryIntent` (`Core/AppIntents/`), quick-capture via Siri/Shortcuts.
- **App Store review prompt** — `ReviewRequestManager`, milestone-based, wired into `WriteView+Actions` and `AddJournalEntryIntent`.
- **7 widgets**, not 2 — see `MirrorWidgetExtension/MirrorWidgetExtensionBundle.swift`.

---

## Staged Onboarding (Critical)

Claude gets good with 7+ entries. Showing a weak nudge on Day 2 causes churn.

```
Day 0:   3 onboarding questions + write first sample entry
Day 1-3: No AI. Show "mirror is learning — 3 more entries to first insight"
Day 4-7: First Daily Nudge unlocks
         → Show paywall AFTER first nudge ("this is what you get every day with Core")
Week 2+: Full experience, weekly digest on Sunday
```

Paywall conversion is highest right after the user feels the value. Never before.

---

## Security Rules

```
1. NEVER log journal entry text anywhere
2. Journal text never leaves the device — all AI is on-device
3. Max entry text sent to local LLM: 10,000 chars (truncate oldest entries first)
4. Cache all insights — never regenerate within 24h. One owner-approved exception (2026-09-28): a second daily reflection the same day, only when today's first covered earlier days' writing and the user has written today since (`InsightService.allowsAnotherReflectionToday`) — at most two per day. Second owner-approved exception (2026-09-30): the one-time regrade of the latest weekly digest and monthly report written by pre-grammar Gemma (`PreGrammarInsightRegrade`), which inserts a newer row even inside 24h; once per device, latest period only, never Foundation Models output
```

---

## iOS Project Structure

Layout is derivable via `ls`/`find`. Notable additions not obvious from a first pass: `Settings/` has ~9 screens including Sentinel-specific ones (`ProtocolSettingsView`, `ArchiveSettingsView`, `DiagnosticsSettingsView`, `ManualSettingsView`); `Core/` also has `AppIntents/`, `Utilities/GamificationEngine.swift`, `Services/FoundationModelEngine.swift`.

---

## Data Flow

**Writing**: `WriteView` → `modelContext.insert(Entry)` → SwiftData → CloudKit sync automatic.

**Insight generation**: `InsightService` → `LocalLLMService` (Gemma 3 1B, on-device) → returns insight text → iOS saves `Insight` to SwiftData cache. No network call.

**Search**: `SearchService` — local only, filters SwiftData entries by keyword.

**Weekly Digest trigger**: generation runs only on Sundays, from app-active, the nightly `BGProcessingTask`, or the single app refresh (`com.lokesh.mirror.dailyNudge`, re-armed ~10 min out on every backgrounding), which also runs the digest and monthly report gates before the nudge (since 3.1.2; the separate weekly/monthly refresh requests were never submitted before, and didn't stay pending beside the daily one on device). The digest's week is `DateHelpers.digestWeekIdentifier` — fixed ISO Monday–Sunday — never the locale week (`weekIdentifier`): in Sunday-first locales the locale week put Sunday in a new empty week and digests silently never generated (fixed 2026-09-27).

**Monthly Report trigger** (Deep only): generates during the last 7 days of the month (`DateHelpers.isInLastWeekOfMonth`) once the month has `monthlyReportMinimumEntries` (10) entries, via app-active + `BGProcessingTask` nightly pass — not on the 1st. User can also manually regenerate (respects 24h cache). `periodIdentifier` = `"2025-05"` format.

**Mood Alert** (Deep only): Checked every app-active + nightly. Fires a notification when the most recent 3 days *with a mood reading* are negative (Anxious/Overwhelmed/Frustrated/Drained/Sad/Numb), counting entry moods and mood check-ins with the day's latest reading winning. Days with no reading are skipped, the lookback is 12 days, and the newest reading must be within 2 days (`MoodLog.recentNegativeMoodDays`). It is not "3 consecutive entries".

**Insight caching**: Before generating, check SwiftData for an existing `Insight` with a matching `periodIdentifier` and a `generatedAt` within 24h, and never regenerate inside that window. When today's newest daily reflection is the fallback, automatic triggers retry only after the writing it read changes (a text-free signature in `mirrorApp.fallbackRetrySignatureKey`, since 3.1.2); Try Again always runs. A digest/report regeneration that comes back as the fallback never replaces a real row for its period; the attempt is recorded per device and staleness counts from it (`InsightService.recordKeptRealRow`, 3.1.2).

The one exception is the daily reflection (2026-09-28). If today's reflection used only earlier days' entries and the user writes today, one more is made that day. If that extra attempt comes back as the fallback card, it isn't saved; the next try waits for newer writing (`mirrorApp.extraReflectionFailedAttemptKey`).

How the Today card behaves around this:
- **Next morning.** It keeps showing the latest reflection from yesterday or today while nothing new has been written.
- **Label.** It says "From what you wrote on <day>" when the reflection is about an earlier day (`InsightService.reflectedDay`).
- **Past reflections.** The list keeps one row per (day it was made, day it's about).

---

## Known Gaps in Spec Code

Closed. All four items originally listed here (`VoiceInputManager.swift`, `CalendarHeatmap`, `OnboardingFlow.swift`, `BGAppRefreshTask` setup) are implemented and shipping as of 2.0.9 — `VoiceInputManager.swift`, `Features/Entries/CalendarHeatmap.swift`, `Features/Onboarding/OnboardingFlow.swift`, and the task registration in `mirrorApp.swift` all exist. No open gaps tracked here currently.

---

## Build Order (10 weeks)

Feature ordering rationale: Daily Nudge first (easiest AI, highest emotional impact, creates habit). Ask second (most engineering). Weekly Digest third (premium feel, less urgent).

1. **Weeks 1–2**: WriteView + SwiftData models + CloudKit sync + entry list. No auth.
2. **Week 3**: LocalLLMService (Gemma 3 1B) integrated + Keychain.
3. **Week 4**: Daily Nudge end-to-end — InsightService → LocalLLMService → SwiftData cache. Staged onboarding empty state.
4. **Week 5**: RevenueCat + Apple IAP + PaywallView (shown after first nudge) + subscription gating.
5. **Week 6**: Ask feature — AskView + SearchService (local keyword search) + on-device Ask prompt + usage counter.
6. **Week 7**: Weekly Digest — BGAppRefreshTask Sunday 7AM + on-device digest + digest card UI.
7. **Week 8**: Widgets (WriteWidget + NudgeWidget) + VoiceInputManager + OnboardingFlow + polish.
8. **Weeks 9–10**: TestFlight beta (20 real users). Measure D7 retention + paywall conversion. Fix critical bugs.
9. **Weeks 11–12**: App Store submission — screenshots, description, privacy policy, review.

---

## Commands

**iOS**: Open `mirror.xcodeproj` (there is no `.xcworkspace` — SPM packages resolve inside the `.xcodeproj`). The llama.cpp wrapper is a **local package** at `mirror/Packages/SwiftLlama` (vendored from lokii49/swift-llama-cpp @ a79abb8, patched — see its `PATCHES.md`; never reintroduce a `print` of sampling config or prompts there: grammars contain journal sentences). Build/run via Xcode (iOS 17+ target required for SwiftData; Foundation Models path additionally needs iOS 26+ and an Apple Intelligence-eligible device, else falls back to Gemma).

Command-line build check: `xcodebuild build -project mirror.xcodeproj -scheme mirror -destination 'generic/platform=iOS Simulator' -configuration Debug`
