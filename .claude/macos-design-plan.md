# MirrorNotes for Mac: design plan

Date: 2026-10-01. Design only; nothing built. Companion to `platform-roadmap.md` (engineering path, sync rules, native-vs-Catalyst decision). This doc covers what the Mac app should look and behave like.

**Legend.** **[checked]** means I read it in the repo this pass. **[unverified]** means platform behaviour from memory; confirm before building.

---

## Principles

1. **A Mac journal, not a stretched iPad.** Wide window means more of the journal visible at once (list and entry side by side), not bigger cards.
2. **Writing is the hero.** Keyboard first, a calm editor with a readable line length, no chrome while typing.
3. **Privacy stays visible.** The About/Settings panel says journal text never leaves the Mac.
4. **Same product, same tiers.** Free / Core / Deep gating, entitlements and copy are unchanged. No Mac-only paywall.
5. **Both themes ship.** Default and Sentinel (93 `appDisplayMode` references **[checked]**) each get a Mac pass.

## Starting point [checked]

- Navigation today: iPhone `TabView` (Entries / Write / Insights); iPad `NavigationSplitView` with a four-item sidebar (`AppSidebarItem`: entries, write, insights, settings) and a single detail pane (`ContentView.swift:345`).
- Settings is a sidebar destination on iPad, not a separate surface.
- Search is custom, not `.searchable` (no `.searchable` use found).
- No app lock (no LocalAuthentication use found).
- Theme tokens live in `Core/Utilities/MirrorTheme.swift` (ink/violet palette for default, ember/mono for Sentinel); light and dark both defined.

## Window and navigation

Three columns, standard Mac pattern:

```
┌───────────┬──────────────────┬────────────────────────────────┐
│ Sidebar   │ Entry list       │ Detail                         │
│           │                  │                                │
│ Write     │ Search field     │ Editor (new entry)  or         │
│ Entries   │ Month groups     │ Entry reader/editor  or        │
│ Insights  │ Pinned on top    │ Insight page                   │
│  Today    │ Calendar heatmap │                                │
│  Digest   │ (collapsible)    │                                │
│  Report   │                  │                                │
│  Mood     │                  │                                │
│  Ask      │                  │                                │
│  Brain    │                  │                                │
└───────────┴──────────────────┴────────────────────────────────┘
```

- **Sidebar** (`NavigationSplitView`, collapsible): Write, Entries, Insights with its sub-pages listed (Today, Weekly digest, Monthly report, Mood timeline, Ask, Brain View). Settings leaves the sidebar and moves to the standard Settings scene (⌘,).
- **Entries** uses list + detail side by side. Selecting an entry opens it in the detail pane; double-click opens it in its own window.
- **Write** is the default launch destination, as on iPhone and iPad, with a "New entry" toolbar button and ⌘N from anywhere.
- **Insights** pages use the middle and detail columns as one wide canvas (no list column).
- **Sizes.** Default 1100×720, minimum 820×560. Remember size, position and sidebar state per window.
- Tier-locked pages (Core vs Deep) show the same lock treatment as iOS, in the sidebar row.

## Writing experience

- Editor column max width ~680 pt, centred; serif default retained; font-size control in the toolbar and ⌘+ / ⌘−.
- Native `NSTextView` bridge replacing `NoteEditorTextView` (`UITextView` today **[checked]**): spell check, text substitution, services menu, find (⌘F inside the entry) come for free.
- Formatting panel (`FormattingPanelView`) becomes a toolbar group plus the standard Format menu shortcuts (⌘B, ⌘I, ⌘U).
- Mood and tags: inline bar under the editor, as on iOS; keyboard-navigable.
- Drafts autosave as on iOS (`DraftAttachmentStore`).
- **Attachments.** Photos by drag-and-drop, paste, or an open panel. Scan-a-page (`VNDocumentCameraViewController`) and camera capture are hidden; "Import from iPhone" via Continuity Camera **[unverified]** is an optional later add.
- **Voice.** Dictation (system, fn fn) works in the editor for free. In-app voice notes need an `AVAudioEngine` path, and `AVAudioSession` is iOS-only **[unverified for Mac]**; keep voice notes behind a microphone permission prompt and a record button in the toolbar.
- **Talk It Out** (guided questions) opens as a sheet in the detail pane.

## Insights on a wide screen

- Today card, Weekly digest and Monthly report render as a readable single column (max ~720 pt) with the source-disclosure ("How this was generated") as a right-hand inspector instead of a sheet.
- Mood timeline and Calendar heatmap use the full width; hover shows the day's tooltip; click opens the entry.
- Ask is a chat column with ⌘↩ to send and the remaining-questions counter in the toolbar.
- **Brain View** gets the biggest upgrade: a large canvas, hover highlights, scroll-wheel zoom, trackpad pinch, click to open matching entries. It is Deep tier only and is the strongest candidate for the visionOS spatial version later (see `platform-roadmap.md`).

## Mac-native surfaces

Follow the standing rule (`feedback_standalone_features`): new surfaces are decoupled, with their own scene or sheet and entry point, not cards bolted into WriteView or InsightView.

- **Menu bar commands.** File: New Entry (⌘N), New Entry in New Window (⇧⌘N), Export. Edit: standard + Find. View: Show Sidebar, Entries list, Zoom. Go: Write (⌘1), Entries (⌘2), Insights (⌘3). Window and Help standard.
- **Settings scene** (⌘,): General, Appearance (theme, writing font), Subscription, iCloud and privacy, Diagnostics. Reuse the existing Settings sections, regrouped into a tabbed Mac settings window.
- **Quick capture** (later): a small `MenuBarExtra` or global-hotkey window that saves straight to an entry. Reuses the `AddJournalEntryIntent` path **[checked: intent exists]**.
- **Widgets.** The five widgets get Mac sizes in Notification Center and the desktop; they open the app via the existing deep-link URLs (`entry/<uuid>`, `insights`, `upgrade` **[checked]**).
- **Multi-window.** Entry in its own window; one Write window at a time.
- **Notifications.** Standard banners; no rich content extension on Mac (see roadmap).

## Visual language

- **Default theme.** Keep the ink/violet palette but use native materials: sidebar vibrancy, standard toolbar, system dividers. Do not draw custom tab bars; the iPhone tab-bar background (`toolbarBackground(MirrorTheme.inkMid …)`) does not carry over.
- **Sentinel theme.** The mono/ember language fits Mac well: dense list, monospaced metadata, ember accent for selection. Keep the renamed nav (Comms/Briefing/Log/Transmission) in the sidebar. Verify every themed view in both.
- **Type.** Mac baseline is 13 pt body in lists and controls, with the journal editor at 17–18 pt serif. Don't reuse iPhone 15–17 pt control sizes.
- **Density.** List rows ~28–44 pt, hover and keyboard focus states on every row; context menus (pin, delete, copy, open in window).
- **Dark and light.** Follow system, with the existing `mirrorAppearanceMode` override.
- **Accessibility.** Full Keyboard Access, VoiceOver labels on every control, Reduce Motion for Brain View, Increase Contrast.

## Privacy and security on Mac

- Sandbox with the network client entitlement (RevenueCat purchases need it; journal text never goes over the network), user-selected file access, iCloud + app group.
- **Open decision: app lock.** None exists on iOS [checked]. A shared Mac makes an unlocked journal riskier. Options: Touch ID / password lock on launch and after idle (new feature, also valuable on iOS), or rely on macOS login. Needs a decision; see questions below.
- Entries remain encrypted at rest with the iCloud Keychain key; no journal text in logs (unchanged rule).
- Export (Phase 2 in CLAUDE.md MVP scope): the Mac makes it more wanted, but it stays out of scope until the owner schedules it.

## App Store

- Mac screenshots are a separate set: 1280×800 minimum, up to 2880×1800 **[unverified]**. Reuse the poster and screenshot pipeline (`appstore-screenshots`, `ipad-appstore-screenshots`).
- Listing copy: lead with "private, on-device, no account"; mention Apple Intelligence + local model.
- Universal purchase: same app record and bundle ID; see `platform-roadmap.md`.

## Phases

1. **Design spike.** Static mocks of the three-column window in both themes (one Write, one Entries, one Insights, one Settings), light and dark. Pick which Insights sub-pages use the inspector.
2. **Shell.** Native macOS target, three-column window, sidebar, Settings scene, menu commands. Editor still basic.
3. **Editor.** `NSTextView` bridge, formatting toolbar, attachments via drag and open panel, autosave.
4. **Insights.** Wide layouts, inspector for the source disclosure, Brain View canvas.
5. **Polish.** Multi-window, widgets, shortcuts audit, accessibility audit, both-theme audit, screenshots.
6. **Later.** Quick capture, Continuity Camera import, app lock if chosen, export if scheduled.

## Open questions for the owner

1. App lock on Mac (and iOS): yes, no, or defer?
2. Settings as the standard ⌘, window (recommended) or keep as a sidebar item?
3. Quick capture / menu bar extra in v1 or later?
4. Sentinel on Mac at launch, or default theme first and Sentinel in a point release?
5. Native macOS target vs Catalyst after a llama.cpp bump (see `platform-roadmap.md`; recommended: native).

## Decisions 2026-10-01

- App lock: deferred.
- Settings: the standard Cmd-, window (not a sidebar item).
- Theme: default theme first; Sentinel in a later release.
- Quick capture: in. A menu bar item opens a small popover (text, mood chips, dictate, Save with Cmd-Return). Built as a decoupled surface that saves an Entry the same way `AddJournalEntryIntent` does; it runs no reflection. The global hotkey (Option-Cmd-J in the mock) is a placeholder, not a decision.
- Native macOS vs Catalyst: still open (recommended: native).
- UI mocks: https://claude.ai/artifact/1iYZQiUkUhhRSQCYZRbpS2 (six boards). Nothing is implemented until the owner approves them.
