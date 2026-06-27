# Mirror 2.0 — Design Plan

> Design lead brief: Mirror is the only place your thoughts are truly private. The UI must feel like a room that exists only for you — intimate, atmospheric, intelligent. Not a productivity app. Not a social feed. A sanctuary.

---

## The Problem With 1.x

- `bgBase` = `Color(.systemGroupedBackground)` — identical to the iOS Settings app. No identity.
- 100% SF Pro at every size, every role — zero typographic personality.
- `futureSurface` applied to every card — no visual hierarchy between surfaces.
- `Color.accentColor` purple — same purple as a thousand other apps.
- Write area looks like a text field, not a journal.
- Widgets use two completely different gradient palettes (purple vs amber) with no shared identity.

---

## Color System

Replace all system color tokens with a hard-coded palette. Supports both light and dark.

### Dark mode (primary — journaling is a nighttime activity)

| Token | Hex | Use |
|-------|-----|-----|
| `inkBase` | `#08060F` | Page background |
| `inkMid` | `#110E1C` | Base card surface |
| `inkRaised` | `#1C1830` | Elevated card (modal, sheet) |
| `inkBorder` | `#2A2545` | Subtle dividers, stroke |
| `violet` | `#7C5CE4` | Primary — richer, deeper than current |
| `violetLight` | `#A78BFA` | Secondary labels, borders, tints |
| `violetDim` | `#3D2D8A` | Tint backgrounds (mood chips, etc.) |
| **`ember`** | **`#F97B8B`** | **Second accent — rose/coral. Used in exactly 3 places only.** |
| `textPrimary` | `#EDE9F8` | Body text |
| `textSecondary` | `#7A7098` | Labels, captions |
| `textTertiary` | `#3F3860` | Disabled, placeholder |

### Light mode

| Token | Hex | Use |
|-------|-----|-----|
| `inkBase` | `#F2EEF8` | Lavender-tinted near-white |
| `inkMid` | `#FFFFFF` | Card surface |
| `inkRaised` | `#F8F5FF` | Elevated card |
| `inkBorder` | `#E0D9F5` | Dividers, stroke |
| `violet` | `#6341CC` | Primary |
| `violetLight` | `#7C5CE4` | Secondary |
| `violetDim` | `#EDE8FC` | Tint backgrounds |
| `ember` | `#E05470` | Same 3 places |
| `textPrimary` | `#16112A` | Body text |
| `textSecondary` | `#6B6080` | Labels |
| `textTertiary` | `#A89FC0` | Disabled |

### The Aesthetic Risk

**`ember` (rose/coral) as a warm second accent.**

Every AI journaling competitor uses purple-only or purple+blue. The warmth of rose signals emotion and care — appropriate for a journal. Used in exactly 3 places:
1. Paywall CTA button (the one moment that needs to feel urgent and warm)
2. Mood alert badge (3 consecutive negative moods — the emotional warning)
3. First insight moment in onboarding (the "aha" reveal)

Nothing else uses ember. Its rarity is what makes it land.

---

## Typography

Still SF Pro (no custom font loading, no added dependencies), but use all 4 design variants deliberately instead of defaulting to `.default` everywhere.

| Context | Design | Size | Weight | Notes |
|---------|--------|------|--------|-------|
| Entry text (WriteView editor) | `.serif` | 18pt | `.regular` | Feels like writing in a real journal |
| Nudge / insight content | `.serif` | 17–22pt | `.regular` | Editorial, thoughtful — not a notification |
| Monthly report body | `.serif` | 15pt | `.regular` | Long-form prose needs serif |
| Navigation labels, buttons | `.rounded` | 12–14pt | `.semibold` | Friendly, warm, not clinical |
| Section headers (month groups) | `.default` | 13pt | `.bold` | Tracking +1.5, all caps |
| Data: streak, word count, dates | `.monospaced` | 11–13pt | `.medium` | Precise, distinct from prose |

Currently `.serif` appears in exactly 1 place in the codebase (InsightView line ~497). It belongs in 4.

---

## Signature Element: Ink Bloom

On `InsightView`, a `RadialGradient` behind the daily nudge card that shifts color based on today's detected mood:
- No mood detected → violet bloom
- Positive mood → violet-to-teal bloom  
- Negative mood → violet-to-ember bloom

Opacity: `0.15–0.20`. Radius: fills the card edge-to-edge with a soft center focus. Users won't consciously notice it but will feel the card breathe.

This is the element the app will be remembered by. Subtle enough to be tasteful. Specific enough to be owned.

---

## Surface Hierarchy (3 levels, not 1)

Currently `futureSurface` is used for everything. New system has 3 modifiers with clear semantic roles:

```
inkSurface()       → base card (replaces futureSurface for list rows, settings rows)
inkCard()          → elevated card (modal sheets, insight cards)
inkHero()          → the featured moment (daily nudge, paywall hero)
```

All three share the same border treatment (`inkBorder` at 0.06 opacity) but differ in fill depth, shadow, and corner radius.

---

## Screen-by-Screen

---

### WriteView — "The blank page"

**Goal:** Zero friction between thought and text. Nothing should compete with the writing.

**Changes:**
- **Background:** `inkBase` instead of `Color(.systemBackground)`. In dark mode: near-void. In light: warm lavender-cream. The writing area becomes a page floating in atmosphere.
- **Entry text font:** `.serif`, 18pt, `lineSpacing(8)`. One line change. Transforms the feel from notes app to journal.
- **Mood button:** Filled capsule with full `moodColor` background at 20% opacity + 1pt border at 50% opacity. Currently it's text + a tiny dot. New version: the whole button tints to the mood color.
- **Date header:** Smaller, `.rounded` font, recessed — less chrome, more writing room.
- **Toolbar:** Height reduced to 44pt. `.ultraThinMaterial` bar (already has `.bar` — keep). Button spacing tighter.
- **Tags bar:** Reduce tag chip height, softer background.

**What stays:** All the current structure, keyboard handling, undo/redo, voice notes, formatting panel. This is a visual pass, not a rebuild.

---

### EntryListView — "The archive"

**Goal:** The list of entries should feel like an elegant ledger, not a task manager.

**Changes:**
- **Section headers:** Month name in large all-caps `.rounded` font with letter-spacing. Current: plain secondary text. New: big, confident chapter dividers.
- **Entry rows:** Add a **3pt left accent bar** (`moodColor` if mood exists, `violetDim` otherwise). Rounded ends. No other structural change — just that one bar gives every row an identity and makes mood instantly scannable.
- **Heatmap cells:** Increase from current size to 9×9pt squares with `cornerRadius: 3`. Stronger contrast between empty (`inkBorder`) and filled (mood color or `violetLight`). Dot-matrix feel.
- **Search bar:** Background `inkMid`, border `inkBorder`, placeholder in `textTertiary`.
- **Filter chips (mood/tag):** `inkRaised` background when inactive, `violetDim` + `violetLight` text when active.

---

### InsightView — "The letter"

**Goal:** The daily nudge should feel like receiving something personal, not reading a push notification.

**Changes:**
- **Nudge hero card:** Full-bleed card with `inkHero()` modifier. Nudge text: serif 20pt, `lineSpacing(7)`, `textPrimary`. Above it: a small `MIRROR NOTICED` eyebrow label in `.rounded` `.semibold` 11pt `violetLight`. The **ink bloom** radial gradient behind the text.
- **Card height:** Taller than current. The nudge deserves space. Minimum 180pt.
- **Stats strip:** Below the hero — streak, week entries, avg mood — compact horizontal HStack. Monospaced numbers, rounded labels. Not cards — just a clean row.
- **Ask card:** `inkCard()` modifier, tighter than the nudge card. Visually subordinate.
- **Weekly digest card:** Same treatment as Ask — clear hierarchy: nudge > ask > digest.
- **Past nudges accordion:** Slightly inset, `inkMid` background, `.serif` text.

---

### AskView — "The dialogue"

**Goal:** Talking to your journal should not feel like using a chatbot.

**Changes:**
- **AI response:** Remove the bubble entirely. Full-width, no background card. Just `.serif` text, `textPrimary`, with a thin `violetDim` left border (2pt) — like a block quote. This is the biggest change from current. The AI answer reads like part of a journal, not a chat reply.
- **User question:** Keep the right-aligned pill but switch fill to `violetDim` with `violetLight` text — less solid, more contemplative than the current gradient fill.
- **Input bar:** Stays `.bar` material. Placeholder: `textTertiary`. Border on focus: `violetLight` at 0.4 opacity (already exists, keep).
- **Empty state:** Serif headline "Ask your journal anything." Subhead in `.rounded`.
- **Suggestions:** Horizontal scroll chips with `inkRaised` background, `inkBorder` border.

---

### MoodTimelineView — "The chart"

**Goal:** Mood data should feel meaningful, not like a fitness tracker.

**Changes:**
- **Line chart stroke:** 3pt width, `LinearGradient` from `violet` → `violetLight` along the line (instead of flat accent color).
- **Range picker:** `inkRaised` background segmented control style — 30d / 90d / All.
- **Mood distribution bars:** Use full `moodColor` palette (already exists), rounded ends, taller bars.
- **Average mood number:** Monospaced, large (44pt), `violetLight` — the hero stat.
- **Mood alerts banner:** `ember` background at 0.15 opacity, `ember` left border 3pt. The one place ember appears in analytics.

---

### MonthlyReportView — "The retrospective"

**Goal:** Reading your monthly report should feel like sitting down with a thoughtful letter about yourself.

**Changes:**
- **Report text:** `.serif`, 15pt, `lineSpacing(6)`. Currently plain system font. This single change makes the report feel like prose, not a bullet list.
- **Month nav arrows:** Smaller, `textSecondary` color, minimal chrome.
- **Hero card:** `inkHero()` modifier. Month name as serif display above the report.
- **"Regenerate" button:** `inkRaised` background, `violetLight` text. Low prominence — the report should be read, not regenerated casually.

---

### OnboardingFlow — "The welcome"

**Goal:** The first 3 questions should feel like being invited in, not filling out a form.

**Changes:**
- **Background:** `inkBase` gradient — dark, atmospheric even on first launch.
- **Question text:** `.serif`, 24pt — large, centered, generous.
- **Answer options:** Full-width `inkCard()` buttons with `inkBorder` border. Subtle `violetDim` fill on selection.
- **Progress indicator:** Thin line at top, `violet` fill, no percentage text.
- **"Start writing" CTA:** `violet` fill, full width, `.rounded` font.

---

### PaywallView — "The invitation"

**Goal:** Upgrading should feel like unlocking something worth having, not a software upsell.

**Changes:**
- **CTA button:** `ember` fill — the only `ember` button in the app. This is the second of the three ember moments. Warm, personal, urgent.
- **Hero:** Circular `violet` → `inkBase` radial gradient (the mirror/reflection motif) instead of the current icon layout. No text in the hero — let the gradient speak.
- **Tier toggle (Core / Deep):** `inkRaised` background picker, `violet` fill on selected.
- **Feature rows:** Tighter (44pt row height), left icon in `violetDim` container, single-line description in `textSecondary`.
- **Price:** Monospaced, `textPrimary`, prominent.
- **"Most popular" / "More AI" sublabels:** `ember` text for Core's "Most popular" (the moment that tips conversion). Currently `violetLight`.

---

### SettingsView — "The control room"

**Goal:** Settings should be clearly secondary to the writing experience — functional, not designed to be explored.

**Changes:**
- **Section headers:** Smaller (11pt), `textTertiary`, more letter-spacing. Recede into background.
- **Row backgrounds:** `inkMid` — slightly warmer than current system grouped background.
- **Toggle tint:** `violet` (already system accent, but explicit).
- **Subscription card:** `inkCard()` with `inkBorder` border. Tier pill in `violetDim`/`violetLight`. No glow — settings is not the place for drama.
- **Danger zone rows (delete, reset):** Standard destructive red, no visual change needed.

---

## Widgets

### Unified Widget Identity

Current problem: `DailyNudgeWidget` uses purple gradient, `WritingPromptWidget` uses amber/orange, `EntriesMapWidget` uses `.fill.tertiary` (system grey), `MoodMapWidget` uses `.fill.tertiary`. Four completely different visual languages. They don't look like they belong to the same app.

**New rule:** All widgets share one background system.

| Widget | Background | Rationale |
|--------|-----------|-----------|
| Daily Nudge | `#110E1C` → `#1C1830` dark gradient (violet undertone) | Premium, calm |
| Writing Prompt | Same dark gradient | Unified identity |
| Entry Map | Same dark gradient | Unified identity |
| Mood Map | Same dark gradient + mood-color bloom | Subtle mood atmosphere |
| Lock screen (circular, rectangular) | `.fill.tertiary` — keep, lock screen has its own rules | |

Replace the current warm-amber gradient in `WritingPromptWidget` and the flat system fill in `EntriesMapWidget` / `MoodMapWidget` with the shared dark gradient. The app is recognizable on any home screen at a glance.

---

### Daily Nudge Widget (small + medium)

**Small:**
```
┌─────────────────────────┐
│ ❝                       │
│                         │
│  "You've been carry-    │
│   ing a lot quietly."   │
│                         │
│  ✦ DAILY NUDGE          │
└─────────────────────────┘
```
- Opening quote mark: serif, 72pt, `violetLight` at 0.15 opacity — atmospheric, not structural
- Nudge text: `.serif`, 13pt — matches in-app treatment
- Eyebrow: `.rounded`, 8pt, tracking 2.0, `violetLight` at 0.5

**Medium:**
Same layout, text at 14pt, adds "Read more →" right-aligned in `violetLight` at 0.6 opacity.

**Locked state:**
- `#0F0C18` flat background (darker than active)
- Lock icon: `textTertiary`
- "Core · $2.99/mo": `textSecondary`, `.rounded`
- Remove current "Core required" text — just show the price

---

### Writing Prompt Widget (small)

Current: amber/orange gradient. Replace with shared dark gradient.

```
┌─────────────────────────┐
│ ✏  TODAY'S PROMPT       │
│                         │
│  "What made you smile   │
│   today?"               │
│                         │
│              Tap to write→│
└─────────────────────────┘
```
- Eyebrow: `.rounded` 8pt, `violetLight` at 0.5
- Prompt text: `.serif`, 15pt, `textPrimary`
- "Tap to write →": 10pt, `violetLight` at 0.45, right-aligned

**Locked state:** Same as Nudge locked. Consistent.

---

### Entry Map Widget (small)

Current: `.fill.tertiary` system grey — anonymous. Replace with dark gradient.

```
┌─────────────────────────┐
│ Entries      🔥 14      │
│                         │
│  ▪ ▪ ▪ ▪ ▪ ▪ ▪         │
│  ■ ■ ▪ ■ ■ ▪ ■         │
│  ■ ■ ■ ▪ ■ ■ ■         │
│  ▪ ■ ■ ▪ ▪ ■ ▪         │
│  ▪ ▪ ▪ ▪ ▪ ▪ ▪ □today  │
└─────────────────────────┘
```
- Header: `.rounded`, 11pt, `textSecondary`
- Streak: `.monospaced`, 11pt, `textPrimary`
- Grid cells: larger (8×8pt), `violetDim` for entries, `inkBorder` for empty
- Today cell: `inkBorder` outline stroke, no fill until written

**Locked state:** Same pattern.

---

### Mood Map Widget (small)

Current: `.fill.tertiary` + Deep-only gate (now fixed to Core). Replace background.

```
┌─────────────────────────┐
│ Mood        ↑ trending  │
│                         │
│  ╭──────────────╮       │
│  │  ╭─╮   ╭─╮  │       │
│  │─╯  ╰───╯  ╰─│       │
│  ╰──────────────╯       │
│  2w avg: Peaceful       │
└─────────────────────────┘
```
- Background: dark gradient + very subtle mood-color radial bloom (opacity 0.12) — the ink bloom at widget scale
- Header: `.rounded`, 11pt, `textSecondary`
- Trend: `.rounded`, 10pt, green/red depending on direction
- Chart line: `violetLight` → `violet`, 2pt stroke
- Average label: `.serif`, 12pt — the one serif moment in widgets

**Locked state:** Same pattern, "Core · $2.99/mo".

---

### Lock Screen Widgets (circular + rectangular)

These have their own system rules (accessory backgrounds). Keep `.fill.tertiary`. Only changes:
- **Circular:** Icon uses SF Symbol at 20pt (slightly larger than current 18pt)
- **Rectangular:** Text uses `.rounded` font for the "Written today ✓" / "Write in mirror" labels

---

## What We Are NOT Doing

- No glassmorphism on cards — only on keyboard input bars (already there)
- No gradient text on headlines
- No confetti or celebration animations
- No colored text gradients on every heading
- No skeleton loaders that bounce
- No border radius below 16pt anywhere
- No more than 2 accent colors anywhere on screen simultaneously
- `ember` does not appear in the main app navigation or repeated UI chrome

---

## Implementation Plan

### Commit 1 — Token system
Update `MirrorTheme.swift`:
- Add `inkBase`, `inkMid`, `inkRaised`, `inkBorder`, `violet`, `violetLight`, `violetDim`, `ember`, `textPrimary`, `textSecondary`, `textTertiary` as static Color values
- Update `accentGradient` to use `violet` → `violetLight`
- Add `inkSurface()`, `inkCard()`, `inkHero()` view modifiers
- Deprecate `futureSurface` (keep it as alias to `inkSurface` during transition)
- Update `AccentColor.colorset` to `#7C5CE4` / `#A78BFA`

### Commit 2 — Surfaces + typography
- `bgBase` → `inkBase` across all views
- `futureSurface` calls → `inkSurface()` / `inkCard()` by semantic role
- WriteView: entry text font `.serif`
- InsightView: nudge text `.serif`, ink bloom RadialGradient
- MonthlyReportView: report text `.serif`
- AskView: AI response — remove bubble background, add left border

### Commit 3 — Screen polish
- EntryListView: mood accent bar on rows, month header typography
- PaywallView: `ember` CTA button, hero gradient
- MoodTimelineView: gradient chart line, ember alert banner
- SettingsView: section header typography

### Commit 4 — Widgets
- Shared dark gradient background token in widget files
- `WritingPromptWidget`: replace amber gradient
- `EntriesMapWidget`: replace `.fill.tertiary`, cell size up
- `MoodMapWidget`: replace `.fill.tertiary`, add mood bloom
- `DailyNudgeWidget`: nudge text → `.serif`
- Locked state copy unified across all widgets

---

## Files Changed

| File | What changes |
|------|-------------|
| `MirrorTheme.swift` | All tokens, 3 new surface modifiers |
| `Assets.xcassets/AccentColor.colorset` | `#7C5CE4` / `#A78BFA` |
| `Features/Write/WriteView.swift` | Editor font `.serif` |
| `Features/Insights/InsightView.swift` | Hero card, ink bloom, `.serif` text |
| `Features/Insights/AskView.swift` | AI response style, suggestion chips |
| `Features/Insights/MonthlyReportView.swift` | Report text `.serif` |
| `Features/Insights/MoodTimelineView.swift` | Chart gradient, ember alert |
| `Features/Entries/EntryListView.swift` | Row accent bar, month header type |
| `Features/Onboarding/PaywallView.swift` | `ember` CTA, hero gradient |
| `Features/Settings/SettingsView+Sections.swift` | Section header type |
| `Widget/DailyNudgeWidget.swift` | Background, text serif, locked state |
| `Widget/WritingPromptWidget.swift` | Background (replace amber) |
| `Widget/EntriesMapWidget.swift` | Background, cell size |
| `Widget/MoodMapWidget.swift` | Background, mood bloom |
| `Widget/WriteWidget.swift` | Label font `.rounded` |
