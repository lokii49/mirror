# Mirror

Mirror is a local-first, privacy-first iOS journaling app. All AI runs on-device — no cloud AI backend, no journal data ever leaves the device.

## Features

- Write daily journal entries (typed or voice)
- Browse entries grouped by month with full-text search
- Calendar heatmap view of writing streaks
- **Daily Nudge** — on-device AI reflection after 7+ entries (Core tier)
- **Ask Mirror** — freeform questions answered by local AI (Core: 15/mo, Deep: unlimited)
- **Weekly Digest** — AI summary of the week, delivered Sunday 7AM (Core tier)
- **Monthly Deep Report** — long-form monthly reflection (Deep tier)
- **Mood Timeline** — mood analytics, range selector, distribution chart (Deep tier)
- **Mood Alerts** — notification if 3 consecutive entries show negative mood (Deep tier)
- Home screen and lock screen widgets (Core tier)
- iCloud backup via CloudKit (free, automatic)
- Apple Sign In only

## Subscription Tiers

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

Annual plans: Core $29.99/yr, Deep $49.99/yr (~16–17% savings, 7-day free trial on all plans).

## Local AI

All AI features use **Gemma 3 1B IT** running on-device via llama.cpp (`swift-llama-cpp`).

- Model file: `gemma-3-1b-it-Q4_K_M.gguf` (GGUF, Q4_K_M quantization)
- Context window: 4096 tokens, GPU acceleration enabled
- Mirror creates a fresh llama.cpp context per request and streams output
- System prompts live in `mirror/Core/Services/InsightService.swift`

The model is not bundled in git. Deliver it as an on-demand resource or in-app download. See `LOCAL_AI.md` for full model lookup path and generation behavior.

## Privacy

Journal entry text **never leaves the device**. There is no cloud AI call, no server-side logging of journal content. The local model receives decrypted text only inside the app process.

Entries and insights are encrypted before SwiftData/CloudKit persistence. The content key lives in the local Keychain. Multi-device sync requires a recovery-key import flow (not yet implemented).

## Architecture

```
iOS (SwiftUI + SwiftData)
├── Local storage: SwiftData (iOS 17+)
├── Cloud sync: CloudKit (automatic, private)
├── Auth token: Keychain only
└── AI: LocalLLMService → Gemma 3 1B (on-device)

Apple Sign In only
          ↓
Supabase (Auth + subscription status only — no journal data)
          ↓
RevenueCat (IAP, receipt validation, webhooks → Supabase)
```

## Requirements

- Xcode 17 or later
- iOS 17.6 or later
- Swift Package Manager (Supabase Swift SDK, RevenueCat)

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
│   └── Services/            # AuthService, InsightService, LocalLLMService,
│                            # SearchService, SubscriptionService, NotificationService
└── MirrorWidgetExtension/   # WriteWidget + NudgeWidget
```

## Backend (Supabase)

Supabase stores auth and subscription status only — no journal data ever.

```sql
-- subscriptions table (RLS: users read own row; service role writes via RevenueCat webhook)
user_id uuid, tier text ('free'|'core'|'deep'), status text ('active'|'inactive'|'cancelled'|'expired'),
revenue_cat_id text, current_period_end timestamptz
```

Deploy:
```bash
supabase db push           # apply schema
supabase functions deploy  # deploy RevenueCat webhook handler
```

## Local Development

```bash
open mirror.xcworkspace    # open in Xcode (use .xcworkspace, not .xcodeproj)
```

For subscription testing, use `mirror/Products.storekit` in Xcode's StoreKit configuration.

Build from command line:
```bash
xcodebuild -scheme mirror -workspace mirror.xcworkspace \
  -destination 'generic/platform=iOS Simulator' build
```
