# Mirror

Mirror is a local-first, privacy-first iOS journaling app. All AI runs on-device — no cloud AI backend, no journal data ever leaves the device. No account or sign-in required.

## Features

- Write daily journal entries (typed or voice)
- Browse entries grouped by month with full-text search
- Calendar heatmap view of writing streaks
- **Daily Nudge** — on-device AI reflection after 3+ entries (Core tier)
- **Ask Mirror** — freeform questions answered by local AI (Core: 15/mo, Deep: unlimited)
- **Weekly Digest** — AI summary of the week, delivered Sunday 7AM (Core tier)
- **Monthly Deep Report** — long-form monthly reflection (Deep tier)
- **Mood Timeline** — mood analytics, range selector, distribution chart (Deep tier)
- **Mood Alerts** — notification if 3 consecutive entries show negative mood (Deep tier)
- Home screen and lock screen widgets
- iCloud backup via CloudKit (free, automatic, no account required)
- Localized UI in 10 languages (see [Localization](#localization))

## Subscription Tiers

**Everything is free right now.** All Core/Deep-tier features below (Ask, Daily Nudge, Weekly Digest, Monthly Deep Report, Mood Timeline, Mood Alerts, widgets) are unlocked for every user while mirror grows — no subscription required. The tier structure and RevenueCat/IAP integration stay in the codebase so paid tiers can be re-enabled later; the free-for-everyone behavior is a single flag (`SubscriptionService.allFeaturesFree`).

| Feature | Free | Core ($2.99/mo) | Deep ($4.99/mo) |
|---------|------|-----------------|-----------------|
| Unlimited entries, forever | ✓ | ✓ | ✓ |
| Full history + search | ✓ | ✓ | ✓ |
| iCloud backup | ✓ | ✓ | ✓ |
| Daily Nudge | — | ✓ | ✓ |
| Ask (15×/month) | — | ✓ | — |
| Ask (unlimited) | — | — | ✓ |
| Weekly Digest | — | ✓ | ✓ |
| Widgets | — | ✓ | ✓ |
| Monthly Deep Report | — | — | ✓ |
| Mood Timeline + analytics | — | — | ✓ |
| Mood Alerts | — | — | ✓ |

Annual plans: Core $29.99/yr, Deep $49.99/yr (~16–17% savings, 7-day free trial on all plans) — pricing kept for when tiers are reactivated.

Subscriptions managed via **RevenueCat** + Apple IAP. No external account needed.

## Localization

mirror's UI is localized into **10 languages**: English (base), Spanish, Japanese, Simplified Chinese, German, French, Brazilian Portuguese, Korean, Italian, and Russian. The app follows the device's language setting automatically — no in-app language switcher.

- Implemented via native **String Catalogs** (`Localizable.xcstrings`) — one for the main app target (`mirror/Localizable.xcstrings`), one for the widget extension (`MirrorWidgetExtension/Localizable.xcstrings`).
- Covers onboarding, paywall, settings, entries, write, all insight screens (Nudge/Digest/Report/Mood Timeline), Ask, and all home-screen widgets.
- Journal entry text, AI-generated insight content, and mood-vocabulary values are intentionally left untranslated — they're either the user's own words or persisted data whose raw form must stay stable.

## Local AI

All AI features use **Gemma 3 1B IT** running on-device via llama.cpp (`swift-llama-cpp`).

- Model file: `gemma-3-1b-it-Q4_K_M.gguf` (GGUF, Q4_K_M quantization)
- Context window: 4096 tokens, GPU acceleration enabled
- Mirror creates a fresh llama.cpp context per request and streams output
- System prompts live in `mirror/Core/Services/InsightService.swift`

The model is not bundled in git. Deliver it as an on-demand resource or in-app download. See `LOCAL_AI.md` for full model lookup path and generation behavior.

## Privacy

Journal entry text **never leaves the device**. No cloud AI, no server-side logging of journal content. The local model receives decrypted text only inside the app process.

Entries and insights are encrypted before SwiftData/CloudKit persistence. The content key lives in the local Keychain. Multi-device sync requires a recovery-key import flow (not yet implemented).

## Architecture

```
iOS (SwiftUI + SwiftData)
├── Local storage: SwiftData (iOS 17+)
├── Cloud sync: CloudKit (automatic, private — no account needed beyond iCloud)
├── Subscriptions: RevenueCat → Apple IAP
└── AI: LocalLLMService (swift-llama-cpp) → Gemma 3 1B IT on-device
```

No backend server. No sign-in. No user data on any server.

## Requirements

- Xcode 17 or later
- iOS 17.6 or later
- Swift Package Manager (`swift-llama-cpp`, `purchases-ios`)

## Project Structure

```
mirror/
├── App/                     # @main entry, SwiftData container + CloudKit config
├── Features/
│   ├── Write/               # WriteView, WriteViewModel, VoiceInputManager
│   ├── Entries/             # EntryListView (calendar heatmap), EntryDetailView
│   ├── Insights/            # InsightView, AskView, MonthlyReportView, MoodTimelineView
│   ├── Onboarding/          # OnboardingFlow (Day 0-7 staged), PaywallView
│   └── Settings/            # SettingsView, SubscriptionView
├── Core/
│   ├── Models/              # Entry, Insight, UserProfile (SwiftData @Model)
│   └── Services/            # InsightService, LocalLLMService, SearchService,
│                            # SubscriptionService, NotificationService,
│                            # InsightGenerationCoordinator, LLMGenerationQueue
└── MirrorWidgetExtension/   # WriteWidget + NudgeWidget
```

## Local Development

```bash
open mirror.xcodeproj
```

For subscription testing, use `mirror/Products.storekit` in Xcode's StoreKit configuration.

Build from command line:
```bash
xcodebuild -scheme mirror -project mirror.xcodeproj \
  -destination 'generic/platform=iOS Simulator' build
```

## License

Copyright (C) 2026 Pudari Lokesh

Mirror is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

This means: you can use, study, and modify the source freely — but any modified version you distribute or run as a service **must also be released under AGPL-3.0**. Commercial forks must open-source their entire modified codebase.

See [LICENSE](LICENSE) for full terms.
