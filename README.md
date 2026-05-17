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

## Private AI And Sync

Daily reflections, weekly digests, Ask Mirror, and mood detection run locally through `SwiftLlama` and the configured GGUF model. Journal content is decrypted only on device for the local AI job; generated insights are encrypted again before persistence.

Journal entry content, media payloads, generated insights, and Ask Mirror questions are encrypted before SwiftData/CloudKit persistence. The current implementation uses a random content key stored in the local Keychain.

Important limitation: this is not yet complete multi-device E2E sync. A second device needs a recovery-key or passphrase-based key import flow before it can decrypt synced ciphertext from another device.

## Backend

The Cloudflare Worker remains available for authenticated backend utilities, but journal reflection generation no longer sends plaintext journal context to the Worker.

Required Worker secrets:

- `OPENAI_API_KEY`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_KEY`

The Worker expects active subscribers to have a row in `public.subscriptions` with `status = 'active'`.

The Worker should not log raw journal text; keep logs limited to request metadata, status, and provider failures.

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
