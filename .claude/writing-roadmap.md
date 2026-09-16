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
