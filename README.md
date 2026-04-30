# Mirror

Mirror is a private iOS journaling app built with SwiftUI and SwiftData. It supports quick written entries, mood tagging, voice notes, entry history, and AI-powered reflection features.

## Features

- Write daily journal entries with optional mood labels.
- Attach and play back voice notes from the write view.
- Browse entries grouped by month with search.
- View daily reflections, weekly digests, and Ask Mirror responses.
- Manage onboarding, settings, and subscription screens.

## Requirements

- Xcode 17 or later
- iOS 17.6 or later
- Swift Package Manager access for the Supabase Swift dependencies

## Project Structure

- `mirror/` - main iOS app source
- `mirror.xcodeproj/` - Xcode project
- `mirrorTests/` - unit tests
- `mirrorUITests/` - UI tests
- `mirror/Products.storekit` - local StoreKit configuration for subscription testing

## Backend

Insights are generated through a Cloudflare Worker backed by Supabase auth and subscription state. The app currently points to the deployed Worker URL in `InsightService`.

Required Worker secrets:

- `OPENAI_API_KEY`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_KEY`

The Worker expects active subscribers to have a row in `public.subscriptions` with `status = 'active'`.

## Local Development

Open the project in Xcode:

```bash
open mirror.xcodeproj
```

Build from the command line:

```bash
xcodebuild -scheme mirror -project mirror.xcodeproj -destination 'generic/platform=iOS Simulator' build
```

For local subscription testing, use `mirror/Products.storekit` in Xcode.
