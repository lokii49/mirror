# Platform roadmap: Mac, then visionOS

Date: 2026-10-01. Not scheduled for any release. Nothing here has been built.

**Legend.** **[checked]** means I read the code, project file or binary this pass. **[unverified]** means it comes from memory of Apple's platform behaviour; confirm before building on it.

---

## Where it stands [checked]

- The app is iPhone and iPad only: `TARGETED_DEVICE_FAMILY = "1,2"`, `SDKROOT = iphoneos`, no `SUPPORTS_MACCATALYST` or `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` set anywhere in `mirror.xcodeproj`.
- Deployment target: 17.6 for the app, 26.4 for the project default.
- The iPad layout is already a `NavigationSplitView` (`App/ContentView.swift:345`), the iPhone layout a `TabView`. A Mac sidebar can reuse the iPad branch.
- SwiftData + CloudKit: one container, `iCloud.com.lokesh.mirror`, `ModelConfiguration(schema:, cloudKitDatabase: .automatic)` (`Core/Persistence/MirrorModelContainer.swift:22`). Push `aps-environment = production`. Background modes include `remote-notification`.
- UIKit footprint: 32 files touch UIKit. Counts: `UIColor` 40, `UIFont` 32, `UIImpactFeedbackGenerator` 26, `UIApplication` 21, `UIImage` 18, `UIViewController` 14, `UIImagePickerController` 7 (in `WriteViewHelperTypes.swift` and `WriteView+Subviews.swift`), `UIPasteboard` 3, `UIActivityViewController` 3. Representables: `NoteEditorTextView` (`UIViewRepresentable` over `UITextView`), `DocumentScannerController`, `NativePhotoPicker`, `CameraPickerController`, `InteractivePopGestureDisabler` (`BrainView.swift`). `@UIApplicationDelegateAdaptor` in `mirrorApp.swift`.
- `appDisplayMode` (Sentinel) is referenced in 93 places. Every Mac view must be checked in both themes.
- **llama.cpp b6102 xcframework slices:** `ios-arm64`, `ios-arm64_x86_64-simulator`, `macos-arm64_x86_64`, `xros-arm64`, `xros-arm64_x86_64-simulator`, `tvos-*`. **There is no Mac Catalyst slice.** `SwiftLlama/Package.swift` declares `.macOS(.v14)` and `.iOS(.v17)`, not visionOS (add `.visionOS(.v1)` when needed; the binary already has the slice).

## Why the Catalyst-vs-native decision flips

Catalyst is the cheaper path for 32 UIKit files, but the pinned llama.cpp build cannot link under Catalyst. Gemma is the fallback engine on every device without Apple Intelligence, so a Catalyst app would have no on-device model for many Macs. Options:

1. **Native macOS (SwiftUI multiplatform) target.** The llama slice exists. Cost: `#if os(macOS)` / `canImport(UIKit)` across the 32 UIKit files, an `NSTextView` editor, `NSApplicationDelegateAdaptor`. Recommended, because visionOS (native, slice present) then shares the same abstractions.
2. **Catalyst after bumping llama.cpp** to a release that ships a Catalyst slice **[unverified that one exists]**. Re-run `tools/llmrig`, since a llama.cpp bump can change grammar sampling and the grounded-output numbers.
3. **Designed for iPad only** (Phase 0). No Mac-specific work.

Decision for the owner when Mac work is scheduled. Default: native macOS.

## Phase 0: zero code

- Check App Store Connect > Pricing and Availability: "Make this app available on Apple silicon Macs and Apple Vision" **[unverified: exact wording and default]**. If on, the iPad build already runs on Mac and Vision Pro with the same bundle ID and container.
- Use it as a free test of what breaks: haptics, document scanner, camera picker, background tasks, widgets, notification extension.
- Download size matters: the bundle carries a 769 MB Gemma GGUF (`mirror/LocalModels`).

## Sync across devices (why a Mac or Vision install may not sync)

Sync is keyed on the CloudKit container and environment, not just the iCloud account. For data to move between iPhone, iPad, Mac and Vision:

- Same container `iCloud.com.lokesh.mirror` in every target's entitlements. A native macOS or visionOS target needs its own entitlements file listing it.
- Same Apple ID, iCloud Drive on, iCloud enabled for the app.
- **Same CloudKit environment.** TestFlight and App Store builds use Production. Xcode-run builds use Development. A Mac built from Xcode will not see data from an App Store iPhone, and vice versa.
- Same SwiftData schema, deployed to Production (`project_cloudkit_schema_deploy`). A new platform adds no model, so no new deploy gate unless `Core/Models/` changes.
- Same bundle ID for universal purchase and (for Designed-for-iPad) the same app record. A native Mac target must be added to the same App Store Connect app record to share the bundle ID. A Catalyst default bundle ID is `maccatalyst.`-prefixed **[unverified]**, so unify it.
- Sync is eventual, not instant; it relies on silent push. Remote-notification registration must work on the new platform.
- Cross-platform side effect: `Insight.generatedByEngine` will show a mix of `.foundationModels` and `.gemma`. Reflections generated on a Mac with Apple Intelligence will sync to an iPhone without it. Nothing in the UI depends on the engine, so this is fine.

## Per-subsystem checklist (verify before build)

- **Haptics** (26 call sites): no-ops on Mac. Wrap behind one helper.
- **Camera / photo / document scanner.** `VNDocumentCameraViewController.isSupported` is already checked at `DocumentScanner.swift:14`; it should report false on Mac **[unverified]**, so hide the entry point. `CameraPickerController` and `UIImagePickerController` camera source: hide on Mac; use `PhotosPicker` or `NSOpenPanel`.
- **Background work (biggest functional risk).** `BGTaskScheduler` call sites, all in `mirrorApp.swift`: `register` (267), `BGProcessingTaskRequest` `com.lokesh.mirror.nightlyInsights` (298), `BGAppRefreshTaskRequest` `dailyNudge` (896), `weeklyDigest` (936), `monthlyReport` (953). The weekly digest, monthly report, mood alert nightly pass and daily reflection all lean on these as a fallback to app-active triggers. `BGTaskScheduler` is not available on native macOS **[unverified]**. Plan: app-active triggers already exist (`mirrorApp.swift:386` region); add `NSBackgroundActivityScheduler` for the nightly pass, and accept that a Mac that is never opened will not generate.
- **Notification content extension** (`MirrorNotificationContentExtension`): likely iOS-only; Mac gets the plain notification.
- **Widgets** (5): WidgetKit runs on macOS 14+ desktop and Notification Center. Each needs a Mac pass; app group `group.com.lokesh.mirror` is shared.
- **Foundation Models**: macOS 26 on Apple Intelligence Macs; Gemma fallback otherwise. Gemma on Mac is a bigger-memory, faster-GPU environment; re-measure with `tools/llmrig`, do not assume the iPhone numbers.
- **Voice**: `VoiceInputManager` / `VoiceTranscriptionService` use Speech and AVAudioSession. `AVAudioSession` is iOS-only; needs an AVAudioEngine path on Mac.
- **RevenueCat + StoreKit**: purchases-ios supports macOS. Entitlements `core` / `deep` unchanged; confirm universal purchase.
- **Siri / App Intents** (`AddJournalEntryIntent`): runs on Mac with Shortcuts.
- **App Sandbox** (native Mac): `com.apple.security.app-sandbox`, network client allowed (RevenueCat needs it; journal text still never leaves the Mac), file access user-selected only, iCloud and app group entitlements.
- **Sensitive-text rule.** CLAUDE.md security rules apply unchanged: no journal text in logs, 10,000-char cap, 24h insight cache.
- **Mac-native polish**: menu bar commands (New Entry, Search), keyboard shortcuts, multi-window, resizable window with a wide-layout version of the entries/write split, pointer hover states, both themes.
- **Screenshots and store listing**: Mac screenshots are a separate set (`fastlane/screenshots`).

## visionOS (far future)

- Phase 0 is the same "Designed for iPad" toggle, tested on a Vision Pro.
- Native visionOS target comes after native macOS shares the platform abstractions. The llama.cpp `xros-arm64` slice exists **[checked]**; add `.visionOS(.v1)` to `SwiftLlama/Package.swift`.
- Open questions: Foundation Models availability on visionOS **[unverified]**; memory budget for a 1B Q4 model alongside the system; whether a spatial journal surface (Brain View as a 3D constellation) is worth building; widgets and Siri on visionOS; voice input as the main entry method.
- Brain View (`BrainView*.swift`, Deep tier) is the obvious spatial candidate.

## Suggested order

1. Phase 0: ASC availability check + test the Designed-for-iPad build on Mac (no code).
2. Decide native macOS vs bumped-llama Catalyst.
3. Extract platform helpers (haptics, pasteboard, image/color/font aliases, share sheet) so UIKit stays out of feature views.
4. Native macOS target: editor, sidebar, background-task replacement, entitlements; test sync in a TestFlight Production build, not from Xcode.
5. Mac polish (menus, shortcuts, windows, widgets, screenshots).
6. visionOS Phase 0, then native.

## Non-goals

No Mac-only features that need a server. No change to the free-tier or subscription structure for Mac. Journal text still never leaves the device.

## Decision: insights stay synced (2026-10-01)

Considered splitting `Insight` into a local-only store so only entries sync. Owner chose to keep one synced store. Reasons: no privacy gain (same key, derived from entries); the Ask cap counts `Insight` rows per month (`AskView.swift:56-60`), so a split would make it per-device; the 24h cache and two-reflections-per-day rules query `Insight` rows; reshaping the live CloudKit store risks the store-open recovery path. If duplicate reflections across devices ever appear, de-duplicate on `periodIdentifier` instead of splitting. Revisit only if per-device insights become a goal, and move the Ask counter somewhere that syncs first.
