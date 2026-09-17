# Writing Experience Roadmap — make writing easiest & most convenient

Date: 2026-09-16. Scope: everything upstream of and inside the compose flow — capture
surfaces (widgets, Siri, camera), prompts/templates, and on-device AI assistance while
writing. Explicitly **not** this doc's scope: the editor-internals bugs and polish already
tracked in `writeview-audit.md` (voice note correctness, formatting panel a11y/perf) — that
work stands on its own and isn't duplicated here.

**Axis for ranking**: time-to-first-word and friction-per-entry, not feature-count parity.
mirror's editor is already feature-rich (formatting, block quote, highlights, voice notes,
photos, tags, mood, quick-start prompts). The gap is in *getting to a blank page with
something to say*, and *staying in flow once there*.

**Competitive grounding — stated honestly**: only Day One and Rosebud were actually searched
(2026 web results, see Sources). Journey/Stoic/Daylio/Reflectly claims are **not** included
below — no data gathered on them this pass; treat any claim about them elsewhere as recall,
not verified.

- **Day One (2026)**: Daily Chat (AI-guided conversational prompting), per-entry "go deeper"
  follow-up prompts, smart title suggestions, entry summaries, camera text-scan capture,
  cross-app capture (Photos/Safari/Shortcuts), a "Today Tab" hub (On This Day + Moments +
  Daily Chat entry points). AI features gated to Day One Gold.
- **Rosebud ($12.99/mo, $9.99 annual)**: voice journaling in 20 languages, therapist-designed
  guided prompts, persistent AI memory across full journal history, adaptive AI tone
  (direct/nurturing/Socratic).

**The one place mirror can lead, not catch up**: every AI-forward competitor above runs its
guidance in the cloud. mirror already has on-device guided generation
(`InsightService`/`LocalLLMService`, Foundation Models-first with Gemma fallback) — a
Daily-Chat/Rosebud-equivalent that never leaves the device, at $2.99–4.99/mo against Rosebud's
$12.99. That's not a feature-parity item, it's the differentiator. See Tier 2.

---

## Tier 0 — quick wins (days, no schema, mostly unit-testable)

### 0.1 Fix the prompt widget ↔ in-app prompt mismatch, wire tap-through to prefill
Two independent prompt systems exist and diverge:
- `Features/Write/WritingPrompts.swift` — `WritingPrompts.all` (30 prompts), day-index via
  FNV-1a hash of `DateHelpers.dayIdentifier`. Feeds `WritingPromptCard` in `InsightView`,
  whose "Use this prompt" button already does the right thing:
  `WriteView(autoFocus: true, initialText: WritingPrompts.all[promptIndex])`
  (`InsightView.swift:141`). This mechanism is proven — nothing to build here.
- `Widget/WritingPromptWidget.swift` — its own hardcoded 28-item `writingPrompts` array,
  day-index via `Calendar.ordinality(of: .day, in: .year)`. Different list, different index
  scheme → **on the same day the widget and the in-app card show different prompts.** Tapping
  the widget's "Tap to write →" just opens `mirror://write` with no prefill — the prompt shown
  on the widget is never the one that lands in the editor.

Cost, checked (not guessed): `WritingPrompts.swift` is **not** currently in the widget
extension's build-membership exceptions (`project.pbxproj` — only `DateHelpers.swift` +
`Widget/*.swift` are shared into `MirrorWidgetExtensionExtension`). Fix is one line — add
`Features/Write/WritingPrompts.swift` to that exception list — not a file move.

Fix:
1. Delete the widget's private `writingPrompts` array; use `WritingPrompts.all` +
   `WritingPrompts.indexForToday()` instead (add the file to the widget target membership).
2. Change `.widgetURL` to `mirror://write?promptIndex=N`.
3. `ContentView.onOpenURL` `"write"` case: parse `promptIndex` query item, thread it down to
   `WriteTabView` → `WriteView(autoFocus: true, initialText:)` the same way `InsightView`
   already does.

Effort: S. Schema: none. Verify: unit test on URL parsing + index math (device/hand check only
for the widget tap itself, which is inherently unverifiable in this sim environment).

> **STATUS — shipped 2026-09-16.** `Features/Write/WritingPrompts.swift` added to the widget
> extension's `membershipExceptions` (`project.pbxproj`) — one line, not a file move, confirmed
> cheap as scoped. `WritingPromptCard` (the SwiftUI view, needs `MirrorTheme`/app env) split out
> into its own `WritingPromptCard.swift` so the enum stays widget-safe — first build attempt
> pulled the whole original file into the widget target and failed on missing app-only symbols,
> caught immediately by the build, not shipped broken. `WritingPromptWidget.swift` now reads
> `WritingPrompts.all` + `WritingPrompts.indexForToday()` directly; `.widgetURL` is
> `mirror://write?promptIndex=N`. `ContentView.onOpenURL`'s `"write"` case parses `promptIndex`
> and presents `WriteView` prefilled **as a sheet** (`showWriteFromWidgetPrompt`), not via the
> persistent Write tab — the tab's `WriteView` instance can already be mounted with `onAppear`
> already fired, so a tab-switch wouldn't reliably re-run the `initialText` prefill logic; the
> sheet path matches `InsightView`'s proven "Use this prompt" mechanism exactly.
>
> Verified: `xcodebuild build` green (app + widget extension targets both compile),
> `build-for-testing` green, `mirrorTests` 271/278 that run — 7 failures are the pre-existing
> `PerformanceXCTests`/`ThemeExtractionServiceTests` flakes documented in `writeview-audit.md`,
> not touched by this change. **Not verified**: the actual widget tap → prefilled editor
> on-device. WidgetKit interaction isn't testable in this sim environment — same class of gap as
> the mic-only voice tests elsewhere.

### 0.2 One-tap entry templates (gratitude / 3 wins / quick mood log)
The `initialText` + `textStyleData` prefill path used by 0.1 already exists and works. Add 3–4
named templates (e.g. a 3-item checklist paragraph style for "3 wins today") reachable from
wherever prompts are surfaced — same mechanism, different seed content. This is the cheapest
possible "reduce blank-page friction" lever because it reuses an already-proven code path.

Effort: S. Schema: none. Verify: unit-testable (prefill content + style application), no new UI
surface beyond an entry point (button/menu) to pick a template.

> **STATUS — shipped 2026-09-16, reach narrower than the item implied.** Added
> `WritingTemplate` (3 cases: Gratitude / 3 Wins / Mood Log, plain-text seed only — no
> paragraph-style/checklist encoding, deliberately, to keep this additive and low-risk) and a
> small chip row on `WritingPromptCard` ("Or start from" + 3 tappable pills), wired through a
> new `pendingTemplateText` state in `InsightView` reusing the exact same
> `showWriteFromPrompt` sheet 0.1 already proven correct.
>
> **Caught, not fixed — flagging instead of silently shipping past it**: `WritingPromptCard`
> (and therefore these templates) only renders in `InsightView`'s `.needsMoreEntries` state —
> the cold-start window before enough entries exist for a daily nudge. Past that window there is
> no template entry point in the app (only via the widget, which doesn't offer templates, only
> the daily prompt). So "reachable from wherever prompts are surfaced" is true, but where
> prompts are surfaced turned out to be narrower than assumed — most users past onboarding won't
> see these. Widening that reach (e.g. a persistent "Templates" entry point) is a separate,
> not-yet-scoped decision, not something this pass decided on its own.
>
> Verified: `xcodebuild build` green. Not separately unit-tested — no new logic beyond static
> string content and the already-tested prefill mechanism.

### 0.3 Promote the Siri quick-capture path
`AddJournalEntryIntent` already exists and is close to ideal: voice → transcribed → saved to
`Entry` directly, zero screens, mood auto-detected, fully on-device
(`Core/AppIntents/AddJournalEntryIntent.swift`). This is *already* the fastest capture path in
the app and isn't surfaced anywhere — not in onboarding, not in Settings. Add one line to
onboarding and/or a Settings tip: "Say 'Add a journal entry in mirror' to Siri — no need to
open the app." Zero code risk, pure discoverability.

Effort: XS. Schema: none. Verify: copy review only.

> **STATUS — Settings-only, shipped 2026-09-16; onboarding insertion deliberately skipped.**
> Added a row + caption to `ProtocolSettingsView`'s "Input" group (same group as voice
> transcription language — already the natural home for input-method settings). Onboarding's
> `writeStep` (`OnboardingFlow.swift`) was the other candidate the item's "and/or" allowed, but
> it's a delicate custom-animated first-entry UX and a one-time-only screen (not re-findable
> later) — decided the regression risk / discoverability tradeoff didn't justify touching it for
> an XS item, and the Settings tip is durable and always reachable. Not asked first; flagging
> the call here rather than presenting it as the only option.
>
> Verified: `xcodebuild build` green. Copy-only addition, no logic — no test needed beyond
> build.

---

## Tier 1 — medium bets (no schema, but need device/hand verification)

### 1.1 On-device photo-text capture ("scan a page")
Day One's camera-scan is one of its most-used convenience features. mirror already attaches
photos (`WriteView+Photos.swift`); add VisionKit `DataScannerViewController` /
`VNRecognizeTextRequest` (fully on-device, no CLAUDE.md conflict) to pull text out of a photo
(a handwritten page, a book quote, a whiteboard) directly into the entry instead of just
attaching the image.

Effort: M. Schema: none. Verify: camera/VisionKit needs a real device — same class of
limitation as the mic-only voice tests already flagged in `writeview-audit.md` (sim has no
usable camera input for this either). Build-green + unit tests on the text-insertion logic is
the ceiling of what's verifiable here; the capture UX itself is hands-only.

> **STATUS — shipped 2026-09-16.** `DocumentScannerController` (`Features/Write/DocumentScanner.swift`)
> wraps `VNDocumentCameraViewController` (capture, edge-detection/perspective correction) —
> used `VNDocumentCameraViewController` over the item's originally-guessed `DataScannerViewController`
> because it's the dedicated multi-page document-scan UI (what Notes' "Scan Text" uses), not a
> live-overlay scanner meant for short single-frame reads. OCR is a separate step,
> `recognizedText(from: [UIImage])` (`VNRecognizeTextRequest`, `.accurate`), run in
> `WriteView+TextScan.swift` inside `Task.detached` so `WriteView` (not the picker) owns the
> `isScanningText` loading state — mirrors how `WriteView+Photos.swift` already owns
> `isAttachingPhoto` around the existing photo pickers. Recognized text is appended to
> `viewModel.text` as plain text (same "no paragraph-style encoding" scope call as 0.2's
> templates). New "Scan Text" option in the existing Photo menu, gated on
> `VNDocumentCameraViewController.isSupported`. Reuses the app's existing
> `NSCameraUsageDescription` — no new Info.plist entry needed.
>
> **Closed the "zero tests" gap the item's own verify line left open**: `recognizedText(from:)`
> is a pure function over `[UIImage]`, so `DocumentScannerTests.swift` renders text into a
> `UIGraphicsImageRenderer` image and round-trips it through real on-device Vision OCR (no mock)
> — 3 cases: single-page recognition, multi-page join-with-blank-line, and a blank image
> throwing `TextScanError.noTextFound`. All 3 pass in-simulator (Vision text recognition needs
> no camera hardware, unlike the scanner UI itself).
>
> Verified: `xcodebuild build` green, `build-for-testing` green, `mirrorTests` 278/284 — 6
> pre-existing flakes (same `PerformanceXCTests`/`ThemeExtractionServiceTests` as 0.1), nothing
> new failing; the 3 new `DocumentScannerTests` individually confirmed passing. **Not verified**:
> the scanner UI itself (camera capture, multi-page flow, the "Recognizing text…" loading state)
> — device-only, same limitation the item called out in advance.
>
> **Gap caught by advisor audit, fixed same day**: `recognizedText(from:)` originally set no
> `recognitionLanguages` at all — `VoiceTranscriptionService` already does real locale work (28
> candidate locales, on-device-model checks, a user-set `transcriptionLanguage` preference), and
> this shipped ignoring all of it, so a German or Japanese scanned page would have produced
> garbage (`usesLanguageCorrection = true` under a wrong assumed language makes that worse, not
> better). Fixed: `recognizedText` now takes a `preferredLanguage` param, wired from the same
> `UserDefaults.standard.string(forKey: "transcriptionLanguage")` the voice-transcription
> setting already writes — reuses an expressed preference instead of inventing a second
> language mechanism. Empty (the setting's "Automatic" value) falls back to
> `Locale.preferredLanguages` filtered against `request.supportedRecognitionLanguages()`, so an
> unsupported tag never reaches `VNImageRequestHandler.perform` (which throws on that). Default
> parameter value keeps the existing 3 `DocumentScannerTests` compiling unchanged.
> `xcodebuild build` green after the fix; not re-run against a non-English scanned page (device
> + real multilingual text needed, same verification ceiling as the rest of 1.1).

### 1.2 In-editor "keep writing" follow-up (Day One's "go deeper", on-device)
A single AI-generated follow-up question offered after the user pauses mid-entry, powered by
the existing `LocalLLMService` — same privacy guarantee as everything else, ephemeral (not
persisted, no schema).

**Flagged, not decided — reads against `feedback_standalone_features`.** That memory's rule,
read in full: *"default to a standalone surface... rather than injecting a card or section into
an existing view like WriteView or InsightView."* The concrete precedent (mood check-in) was a
whole independent feature module, not a one-line contextual suggestion — but the rule's text
names WriteView specifically, and a suggestion chip inside the editor is exactly the shape it
warns about. Not resolving this unilaterally. Two honest options:
- **(a)** small dismissible chip inside `WriteView`, appears only after N seconds idle with
  ≥1 paragraph written — genuinely the highest-friction-reduction item on this list, but is a
  "section injected into WriteView."
- **(b)** standalone: a separate "Keep Writing" entry point (e.g. long-press the save button,
  or a distinct sheet) that takes current draft text, generates one on-device follow-up, and
  hands control back — decoupled, more taps, less magical.
Ask before building either.

Effort: M. Schema: none. Verify: prompt-construction logic is unit-testable; the "does it feel
good while typing" part needs hands, not a simulator.

> **STATUS — shipped 2026-09-16 as (a), by explicit user choice (not decided unilaterally).**
> Asked before building; user picked the inline-chip shape knowingly, against the
> `feedback_standalone_features` concern this doc raised.
>
> New `LocalLLMTask.followUp` case (temperature 0.5, 140-char cap) + `FOLLOW_UP_SYSTEM` prompt +
> `InsightService.generateFollowUp(currentText:)`, following the exact `ask`/`detectEmotion`
> pattern — every exhaustive `switch` over `LocalLLMTask` in `InsightService.swift` (cleaning,
> retry constraints, language-instruction, validation) updated, not bypassed. New
> `validateFollowUp` requires exactly one `?`-terminated question, 8–160 chars, no
> journal-writer first person. `WriteView` debounces on `onChange(of: viewModel.text)`: 20+
> words written, 20+ word delta since the last checkpoint (generation or dismissal), 6s idle,
> Core/Deep-gated (`SubscriptionService.shared.tier`, matching every other AI surface in the
> app). Entirely ephemeral — `@State` only, never touches the draft store, SwiftData, or the
> saved `Entry`. Tapping "+" appends the question into `viewModel.text`; "x" dismisses.
>
> **Tier-gating was decided, not asked.** Consistent with every other AI feature in CLAUDE.md's
> subscription table, but it's a product/pricing call inferred from precedent, not something the
> user explicitly signed off on for this specific feature. Flagging plainly rather than letting
> it pass as obviously-correct.
>
> **Layout gap, caught before shipping further but not resolved by testing**: the chip's
> visibility guard originally matched `pendingDelete`'s bottom-banner precedent
> (`!pendingDelete, !showSaved, !isAttachingPhoto`), but `pendingDelete` only shows once the
> keyboard is dismissed — the follow-up chip is meant to show *while actively typing*, a
> different layout state. Added `!isScanningText, !showFormattingPanel` to the guard as a
> defensive fix (the formatting panel occupies the same input-view slot as the keyboard on
> iPhone; showing a bottom-anchored chip underneath it would be visually wrong). **Whether the
> chip actually renders correctly above `toolRow` while the keyboard is up has not been
> hands-verified** — this sim environment can't drive that interaction, and reasoning from the
> `pendingDelete` precedent alone was shown to be an imperfect analogy once examined closer. On
> a device: type 20+ words, wait ~6s, confirm the chip appears above the toolbar, not behind it.
>
> One test bug caught and fixed during verification: the first `followUp_journalWriterFirstPerson_rejected`
> test used "I wonder what I meant by that?" — `containsJournalWriterFirstPerson` only matches
> specific verbs after "I" (feel/need/etc.), not "wonder"/"meant", so the test's premise was
> wrong, not the validator. Rewritten to use a phrase the detector actually catches.
>
> Verified: `xcodebuild build` green, `build-for-testing` green, `mirrorTests` 277/284 — 6
> pre-existing flakes + the one test bug above (fixed, re-verified 71/71 green on
> `InsightValidationTests` alone, including the 5 new `followUp_*` cases). **Not verified**: the
> chip's on-screen layout/timing while typing (see gap above) — reasoned correct, not observed.
>
> **Perf/scheduling gap, flagged by advisor audit, not fixed — needs device measurement, not
> more code.** This is the first LLM consumer triggered directly by typing (every other caller
> fires at save time or on a background schedule). `generateFollowUp` runs through the same
> `LLMGenerationQueue`/`LocalLLMService.generate` path as everything else — `generate()` does
> `await resetContext()` and spins up GPU inference while the user may still be actively editing,
> a materially larger perf event than the keystroke-latency work `writeview-audit.md` 1.8/3.6
> went to the trouble of measuring and bounding. It can also queue ahead of
> `autoDetectMoodIfNeeded` at save time or a background digest pass — the queue serializes
> correctly (no race), but ordering/latency interference between features isn't something any
> test in this repo catches. Cancelling the debounce `Task` sets `isCancelled` but does not abort
> work already inside the queue closure. Left open as a named device-measurement item, not an
> assumption that it's free.

---

## Tier 2 — the big bet: private, on-device guided entry

**"Talk it out" — a conversational on-device entry-starter.** Day One Gold's Daily Chat and
Rosebud's guided prompting are the two clearest signals that AI-guided writing is where
premium journaling is heading — and both run that guidance in the cloud. mirror's entire pitch
is "your journal text never leaves the device." A guided, multi-turn, on-device conversation
that ends by handing the user a drafted entry (edit before saving, same as everything else) is
strictly better on the axis competitors can't match, not a catch-up feature.

Shape (standalone surface, per `feedback_standalone_features` — own sheet/entry point, not a
WriteView card):
- New entry point (e.g. a distinct button next to "Write" or in the prompt card's menu), opens
  a dedicated sheet.
- 2–4 short AI-asked questions (new `InsightService` system prompt, same pattern as
  `ASK_SYSTEM`/`DAILY_NUDGE_SYSTEM`), user answers by typing or voice (existing
  `VoiceInputManager` transcription path).
- On finish, stitches Q&A into draft text, opens the normal `WriteView` (existing
  `initialText` path) for the user to edit/trim before saving — mirror never auto-saves AI-
  authored text as-is, matching how every other AI surface in the app works today.
- Chat turns before the final entry is composed should stay **ephemeral, in-memory only** — no
  new persistence, no CloudKit schema change, and no new place that could accidentally log
  journal-adjacent text (CLAUDE.md security rule 1 applies to this as much as to `Entry`).

Positioning if shipped: "guided journaling, fully private, at a third of Rosebud's price" is a
real marketing line, not just a feature checkbox — worth a `/post-ideas` pass once built.

Effort: L. Schema: none (by design, above). Verify: system-prompt construction and the
stitch-into-draft logic are unit-testable without a device; the conversational feel needs
hands.

> **STATUS — shipped 2026-09-16, entry point changed mid-session (user redirect, not the
> original plan).** First shipped as a "Talk It Out" option in WriteView's existing Camera /
> Photo Library / Scan Text menu — asked explicitly, since the prompt card's
> dead-end-past-onboarding (0.2's STATUS), Siri's no-editor save, and the widget's plain
> deep-link all ruled themselves out as hosts. User then asked for a dedicated tab instead, so
> the entry point moved to a **4th tab bar item** ("Talk" / Sentinel "Comms" — the Sentinel name
> was already reserved in CLAUDE.md's "renamed nav: Comms/Briefing/Log/Transmission" line, which
> only 3 of the 4 named tabs actually existed for before this).
>
> `AppSidebarItem` (`ContentView.swift`) gained a `.talk` case, threaded through the iPhone
> `TabView` (new tag 3), the iPad `NavigationSplitView` sidebar/detail switch, the
> `sizeClass`-change tab↔sidebar sync, and `onOpenURL`'s `mirror://talk` deep link — every switch
> over the sidebar-item/tab-index pair that existed before this change was updated, not
> bypassed. `TalkItOutView` itself was reworked from a self-contained sheet (its own
> `NavigationStack`, title, Cancel-via-`dismiss()`) into embeddable content — it now takes an
> `onCancel` closure instead of assuming a dismissible presentation, since a persistent tab has
> no modal to dismiss. The new `TalkTabView` (`ContentView.swift`) hosts it, owns the
> `NavigationStack`/title/"Start Over" toolbar button, and — since the tab is always visible
> rather than gated at a tap — owns the Core/Deep + `LocalLLMService.isModelAvailable` checks
> directly as locked/not-ready states inside the tab (a small inline card, not a shared
> component — `InsightView`'s `UpgradePromptCard` is `private` to that file, so this duplicates
> ~15 lines rather than plumbing cross-file access for a one-off). `.id(conversationID)` forces
> a fresh `TalkItOutView` (and its `@State`) after finishing, after "Start Over", or after
> saving the composed entry — since unlike a sheet, this view doesn't get torn down and rebuilt
> on its own.
>
> Finishing now composes the raw Q&A pairs (`TalkItOutView.composedText(from:)`, unchanged) and
> opens a **new** `WriteView` sheet prefilled via `initialText` — the same proven mechanism 0.1's
> widget prefill and 0.2's templates use — rather than appending into an already-open editor
> (there usually isn't one; the tab can be reached without ever visiting Write first). Up to 4
> questions (`GUIDED_ENTRY_SYSTEM`) via `InsightService.generateGuidedQuestion`, which
> deliberately **reuses the `.followUp` `LocalLLMTask`** rather than adding a new case — the
> output shape (one short question ending in "?") is identical, so 1.2's already-tested
> validator/cleaning/retry machinery applies unchanged; only the system prompt and conversation
> framing differ.
>
> **Deliberately scoped smaller than the competitors it's answering.** Answers are typed, not
> voice — wiring `VoiceInputManager`'s full recording/permission/transcription flow into a
> second self-contained sheet was judged a real follow-up, not required to prove the on-device
> value. And finishing hands the user the raw Q&A pairs to edit, not a second LLM pass that
> rewrites them into flowing prose — one fewer place for the 1B model's output to need retry
> logic. Both are named scope cuts, not silent gaps.
>
> **Two real gaps found by advisor audit before this was reported done, both fixed same pass**
> (fixed while this was still the WriteView-menu shape; carried forward unchanged into the tab
> rework since the underlying risk — a paying subscriber whose model isn't ready — is identical
> either way):
> - The original gating checked subscription tier only — a paying subscriber whose Gemma model
>   isn't downloaded yet (Foundation Models unavailable) would reach the chat flow and have its
>   very first question generation fail immediately. Now `TalkTabView` checks
>   `LocalLLMService.isModelAvailable` (the same pre-flight check `scheduleFollowUpCheck`, 1.2,
>   already uses) and shows a distinct "not ready yet" state instead of a broken chat.
> - A failed question generation left a genuine dead end: the error alert was OK-only, and after
>   dismissal there was no question (Next stays disabled without one) and no Finish button
>   (hidden while `turns` is empty on a first-question failure) — Cancel was the only way out.
>   Rewrote the alert to always offer "Try Again" (re-generates) plus either "Cancel" (nothing
>   collected yet) or "Finish" (use what's already been answered) — never just "OK" into a wall.
>
> **Not fixed, documented instead**: the shared-LLM-queue perf/scheduling question — see 1.2's
> STATUS addendum above, which applies here identically (guided-question generation runs through
> the same queue whenever the Talk tab is open and generating).
>
> **Model-quality risk, raised by a second advisor audit, partially mitigated — not measured.**
> Neither `generateFollowUp` (1.2) nor `generateGuidedQuestion` (here) has ever been run against
> a real model in this session — every test exercises `validate(_:for:)` against hand-written
> fixtures, not actual Gemma/Foundation Models output (`InsightValidationTests`'s own header
> says this explicitly). The specific risk here, not just general 1B capability: by turn 3, the
> conversation transcript fed back to the model has multiple `?`-terminated lines, and
> `validateFollowUp`'s "exactly one `?`" rule means an echoed or two-part question gets rejected
> — a visible stall, not a silent failure like in 1.2. `GUIDED_ENTRY_SYSTEM`'s "don't repeat a
> question already asked" is also unvalidated — a negative constraint over growing context,
> which small models are worst at; the failure mode there isn't an error, it's the same question
> twice. Both risks scale with transcript length, an axis 1.2 never has.
>
> Two mitigations landed same pass: **question 1 is now seeded from `WritingPrompts.all`**
> (random pick) instead of generated — it's the highest-cost, lowest-need spot for a model call
> (first thing the tab shows; `GUIDED_ENTRY_SYSTEM`'s "broad and welcoming" ask is exactly what
> the 30 hand-authored prompts already are), and it means only turns 2–3 ever call
> `generateGuidedQuestion` now, not all `maxQuestions`. And **`maxQuestions` dropped 4 → 3**,
> capping how far into the degrading-with-length zone a conversation goes.
>
> **Not fixed**: `LocalLLMService.generate`'s Foundation-Models-first-then-Gemma split means
> this feature's actual quality differs across the install base (FM on iOS 26 + eligible
> hardware + Apple Intelligence on; Gemma 3 1B everywhere else), and `generateFollowUp`/
> `generateGuidedQuestion` both discard `result.engine` (copying `detectEmotion`'s pattern) —
> unlike `Insight.generatedByEngine` elsewhere in the app, there's no way to attribute a bad
> guided question to which engine produced it. Not fixed because Talk It Out is deliberately
> unpersisted (see the ephemeral-by-design note above), so there's nowhere to attach that
> attribution without adding the persistence this feature was scoped to avoid — a real tension,
> not an oversight, and worth a decision before this ships further rather than a silent choice
> either way.
>
> **The discriminating test, not yet run**: on a device with Apple Intelligence off (forcing the
> Gemma path), run the guided flow to 3 turns and count validator rejections and near-duplicate
> questions per turn. Needs a real inference pass this environment couldn't do (sim load 40–233
> throughout this session). **Until that check happens, "guided journaling, fully private, at a
> third of Rosebud's price" (this doc's own positioning line, above) should not be used in
> marketing or a `/post-ideas` pass — the quality claim underneath it is unverified, not just
> the UI.**
>
> New tests: `mirrorTests/TalkItOutTests.swift` — 3 cases on `composedText(from:)`, the one pure
> seam in this view (single turn, multi-turn join-with-blank-line, empty input); unaffected by
> the entry-point rework since that function's signature never changed. Everything else is
> either already-tested `.followUp` validation (reused, not duplicated) or live chat/navigation
> UI — device/hands-only, same limitation as every other interactive surface this session
> touched. **Not hands-verified, specifically**: the iPad sidebar/detail routing for `.talk` and
> the `mirror://talk` deep link.
>
> **UI redesign + one real on-device bug, both 2026-09-16, after the initial ship.** First
> version had no `MirrorTheme`/Sentinel branching at all (`Color(.secondarySystemGroupedBackground)`,
> `.background(.bar)`, fixed `.system(size:)` throughout) despite `TalkTabView` around it already
> branching — a CLAUDE.md-flagged defect class (`writeview-audit.md` 3.2/3.3 were filed for
> exactly this). Redesigned as a document-style transcript instead of chat bubbles (the
> transcript *is* a preview of the entry it becomes — matches mirror's serif-prose identity
> instead of the generic cloud-chatbot look), added `@ScaledMetric` Dynamic Type support (the
> `writeview-audit.md` 2.5 pattern), a "1 of 3" progress label, a `TextEditor` placeholder,
> question-swap transitions, and combined per-turn accessibility elements.
>
> **Then a real bug, found by the user testing on an actual device (a screenshot, not this sim
> environment) — not something either advisor audit caught.** With the keyboard up and no
> dismiss affordance, the tab bar sits hidden underneath it indefinitely; from the user's side
> it looked like "no back option or swipe down works." Root cause: the `TextEditor` had no
> keyboard-dismiss path at all. Fixed with `.scrollDismissesKeyboard(.interactively)` (matching
> `WriteView`'s own editor) **and** an explicit "Done" button in a `.keyboard`-placement
> toolbar — the gesture alone isn't reliable here since a swipe starting *inside* a `TextEditor`
> doesn't always propagate to the parent `ScrollView` (a known SwiftUI quirk), so the toolbar
> button is the actual guaranteed fix, the gesture a bonus. This is the first and only part of
> Tier 2 confirmed working on a real device this session — screenshot showed the redesigned
> layout (left accent rule, serif question/answer, "1 of 3", Next button) rendering correctly in
> Classic mode.
>
> Verified: `xcodebuild build` green, `build-for-testing` green after every pass above, real
> on-device screenshot confirming the Classic-mode layout renders as designed. Full `mirrorTests`
> run was disrupted repeatedly by real environment instability — `uptime` showed load averages
> climbing from 40 to 233 across several attempts (matches `feedback_xcode27_beta_sim_instability`),
> with the simulator failing to launch outright (`NSPOSIXErrorDomain Code=3`) more than once.
> Re-run once the machine calmed (load dropped to ~6 after a `Monitor`-based wait rather than
> blind retries); see the commit for the confirmed pass/fail count. **Sentinel mode's rendering
> is now confirmed** — a later on-device screenshot (below) showed "COMMS," the ember accent
> rule, mono "1 OF 3," and the ember "NEXT" pill all rendering correctly; the earlier "remains
> unverified" note is retracted.
>
> **Second real on-device bug, also found by the user (two screenshots: the finished 3-turn
> transcript, then the composed-entry sheet opening blank) — root cause was in shared code, not
> Tier 2 itself.** `WriteView.onAppear` (`WriteView.swift`) called `restoreDraftFromStorage()`
> unconditionally *before* checking `initialText`, so any unrelated leftover autosaved draft
> sitting in `UserDefaults` from an earlier, unrelated Write session silently overwrote an
> explicit `initialText` request. This is the exact same mechanism 0.1's widget prefill and
> 0.2's templates depend on — they had this latent bug too, just less visible than losing a
> freshly-composed 3-answer conversation. Fixed at the shared root: when a caller passes
> `initialText`, that intent wins outright and the stale-draft restore is skipped entirely for
> that session — the old draft is left untouched in storage (not cleared, no data loss), it's
> just not loaded into this particular prefilled one. One `if`/`else` in `WriteView.swift`, no
> new state, no schema. Not covered by a dedicated unit test — the logic is a one-line
> precedence condition inline in `onAppear`, and extracting it into a testable static function
> (the pattern `WriteView.applyTranscription` already established for the same reason) was
> judged more ceremony than a boolean condition warrants; the structural fix itself is the
> real risk reduction here, verified by the user's own follow-up report, not a passing test.
>
> **Third on-device round: a UI regression from fixing the first bug, caught immediately by the
> user, plus a third advisor consult on placement.** The keyboard-dismiss fix above (the
> `.scrollDismissesKeyboard` + toolbar-"Done" pair) added a *second* button that sat visually
> stacked on the bottom bar's own "Next"/"Done" capsule — two near-identical buttons, correctly
> reported as confusing UX. Advisor-reviewed fix: one button, one location — the advance action
> moved *into* the keyboard toolbar itself (submitting an answer clears `currentQuestion`, which
> drops focus and dismisses the keyboard as a side effect of the same tap), and the bottom bar
> now holds only the passive "1 of 3" label plus "Finish." Advisor also flagged that the
> gesture-only dismiss this session nearly shipped (relying solely on
> `.scrollDismissesKeyboard(.interactively)`, which was already flagged as unreliable when a
> drag starts inside the `TextEditor` itself) would likely have reproduced the original "no back
> option" report — caught before that regression landed.
>
> **Placement question, asked explicitly, answered: keep the tab, don't pivot again.** Evidence
> against another move: both on-device bugs were keyboard/draft-precedence issues, not
> tab-architecture issues — the draft-precedence bug lives in shared `WriteView` code and would
> have fired identically from the original menu-sheet shape; a sheet has the identical
> keyboard-over-content problem the keyboard bugs came from. The tab is also the most decoupled
> option on the table, which is what `feedback_standalone_features` actually asks for, and the
> user chose it explicitly after seeing the menu-item version first. One open, low-stakes
> question left for the user, not decided here: whether the Talk tab should sit at index 2
> (next to Write) instead of appended at index 3 after Insights — it was appended only to avoid
> renumbering the existing tabs' `onOpenURL`/`sizeClass`-sync switches, not for a UX reason.
>
> **Fourth round: reordered to index 2, then removed entirely — final placement is inside
> WriteView, not a tab.** The index-2 reorder shipped first (every switch re-threaded again).
> Then, after the keyboard/duplicate-button bugs above, the user asked a third time for a
> different placement: "have Talk it out within WriteView." Advisor consulted again — verdict
> reversed from the earlier "don't pivot" position specifically because this was now a third
> explicit ask, not a design disagreement to push back on. Design: a quiet chip
> (`TalkItOutChip`, `WriteView+Subviews.swift`) shown only when `entry == nil && !hasDraftContent
> && !focusMode` — a genuinely blank new entry — directly above the editor, in the same
> `ScrollView` content stack as the voice-note/recording rows. It disappears the instant there's
> any content, since at that point the user is already writing.
>
> Asked the user explicitly whether to keep the tab as a second entry point or remove it —
> answer was WriteView-only. **Fully reverted**: `AppSidebarItem.talk`, the `TalkTabView`
> struct, every `selectedTab`/`selectedSidebarItem` switch case, the `mirror://talk` deep link
> (confirmed unreferenced elsewhere before deleting), and the tab-index renumbering all removed
> — tabs are back to Entries=0/Write=1/Insights=2, matching the pre-Tier-2 state.
>
> Mechanically this paid off the "no `NavigationStack` inside `TalkItOutView`" refactor from the
> tab work: hosting it as `.sheet { NavigationStack { TalkItOutView(...) } }` from `WriteView`
> needed zero changes to the view itself, only a new `WriteView+TalkItOut.swift` (recreating
> `presentTalkItOut()`'s Core/Deep + `isModelAvailable` gating, deleted once already when the
> tab replaced it) and `appendTalkItOutText` (mirrors `appendScannedText`, 1.1). Advisor flagged
> one thing this shape sidesteps for free: `ce4e63c`'s draft-precedence fix isn't load-bearing
> here, because the chip appends into the *already-open* `viewModel.text` rather than going
> through `initialText` at all.
>
> Not yet hands-verified: this exact shape (chip placement, appearance/disappearance timing,
> both themes) — device-testing this session was already spent on the tab version before the
> pivot.

---

## Explicitly cut from this roadmap
- **On This Day / flashback surface** (Day One's flagship retention feature) — this is a
  *reading* feature, not a writing one. Out of scope for "make writing easier"; revisit under a
  retention-focused pass, not here.
- **Apple Watch quick capture** — no existing Watch target/scaffolding in this project structure
  (checked — no `Watch/` dir, no watchOS target in `project.pbxproj` beyond the widget
  extension). Real convenience win, but it's a new target with no way to verify in this
  environment. Phase-3 candidate, not costed here.

---

## Suggested order of work
1. **0.1** (prompt mismatch + prefill wiring) — cheapest, fixes a real bug, highest
   friction-reduction-per-hour on this list.
2. **0.3** (Siri discoverability) — near-zero cost, the fastest capture path already exists and
   is invisible.
3. **0.2** (templates) — reuses 0.1's proven prefill path.
4. **Decide 1.2's (a) vs (b)** — blocks starting it either way.
5. **1.1** (photo-text capture) — device-verify-only, but self-contained and additive.
6. **Tier 2** ("Talk it out") — the differentiated bet, largest effort, do once 0.x/1.x prove
   out the prefill/voice/on-device-prompt plumbing it all depends on.

---

## Sources
- [Features of Day One App](https://dayoneapp.com/features/)
- [Day One vs Journey: Find The Best Journaling App For You](https://www.reflection.app/best-journaling-apps-compared/day-one-vs-journey)
- [Rosebud: AI Journal & Diary - App Store](https://apps.apple.com/us/app/rosebud-ai-journal-diary/id6451135127)
- [The 6 Best AI Journaling Apps for Mental Wellness (2026)](https://www.rosebud.app/blog/top-6-ai-journaling-app-for-mental-wellness)
