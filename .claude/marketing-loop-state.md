# MirrorNotes marketing/distribution loop state

The agent forgets each run. This file does not — read it fully before starting.

## Channel map

MERGED/live already:
- linsa-io/ios-apps
- dkhamsing/open-source-ios-apps#2274
- woop/awesome-quantified-self#141

OPEN unmerged (bump if stale >2wk since last touch logged below, polite one-line comment only):
- pluja/awesome-privacy#879
- dreamingechoes/awesome-mental-health#78
- janhq/awesome-local-ai#131
- tehtbl/awesome-note-taking#89
- lissy93/awesome-privacy#671 — repo-age gate (16wk, ~2026-08-29) has now passed as of this run
  (2026-08-31); moved out of Gated. Still blocked on the same cross-owner GitHub write restriction as
  the rest of this list (see Blocked), so no different in practice, but no longer needs the gate check.

Blocked (do not retry via CLI, org OAuth restriction, needs human click):
- theimpossibleastronaut/awesome-mentalhealth

## Backlog

### opensourcealternative.to — [web-form, needs user]
Directory of open-source alternatives to proprietary software, has a dedicated AGPL-3.0 license
category (https://www.opensourcealternative.to/license/agpl-3-0) — good fit, not yet in channel map.
Submission appears to be via their own web form (not a GitHub PR to the piotrkulpinski/openalternative
repo) — could not confirm exact form fields, WebFetch to the site is blocked in this environment
(see Blocked). Ready-to-paste copy below for whoever fills the form:

- Name: MirrorNotes
- Tagline: Privacy-first journaling app with on-device AI
- Website: https://mirrornotes.org
- Repository: https://github.com/lokii49/mirror
- App Store: https://apps.apple.com/app/id6769007201
- License: AGPL-3.0
- Category: Productivity / Journaling / Note-taking
- Description: "MirrorNotes is a privacy-first journaling app for iOS. All AI features — daily
  nudges, weekly digests, and an 'ask your journal' chat — run fully on-device using a local
  Gemma 3 1B model, so entries never need to leave the phone for AI processing. It's local-first
  with free CloudKit sync, requires no account or signup, and offers unlimited private journal
  entries free forever. The core app is open source under AGPL-3.0."

### schickling/awesome-local-first — [needs GitHub PR, blocked in this env — see Blocked]
Curated list of local-first software (README sections: Awesome Local-first / What is local first? /
Applications / Related projects / About). MirrorNotes is local-first with free CloudKit sync — good
fit for the "Applications" section, not yet in channel map. No CONTRIBUTING.md found via WebFetch;
entries are plain markdown bullets, alphabetized-ish, format confirmed from README:
`*   [Name](url): one-line description` or `*   [Name](url) - one-line description`. Ready-to-paste
entry for whoever/whatever opens the PR (add alphabetically after "Marmalade" or wherever it lands,
check current list order before inserting):

`*   [MirrorNotes](https://mirrornotes.org): A local-first, privacy-first journaling app for iOS with free CloudKit sync. On-device AI (Gemma 3 1B) powers daily nudges and journal search — nothing needs to leave the device for AI features. Open source, AGPL-3.0.`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### AlternativeTo.net — [web-form, needs user, account age gate]
Large software-discovery directory with License/Platform/Tags filters (has a "Journal" category and
an AGPL-3.0 license filter) — good fit, not yet in channel map or backlog. Submission form is at
alternativeto.net/manage/new/ but requires a signed-in account that is **at least 7 days old** before
it's allowed to submit a new listing, and wants a logo + screenshots uploaded (not just text) —
confirmed via WebSearch (site itself is EGRESS_BLOCKED for WebFetch, so exact field list unconfirmed).
Not actionable by this loop even once GitHub scope is fixed, since it needs a human with an aged
account and image assets. Ready-to-paste copy for whoever does it:

- Name: MirrorNotes
- Tagline: Privacy-first journaling with on-device AI
- Website: https://mirrornotes.org
- Category/Tags: Journal / Diary, Privacy, Productivity, Offline
- License: AGPL-3.0
- Platforms: iOS
- Description: "MirrorNotes is a privacy-first journaling app for iOS. Daily nudges, weekly digests,
  and an 'ask your journal' chat all run on-device via a local Gemma 3 1B model — no entries need to
  leave the phone for AI processing. Local-first with free CloudKit sync, no account or signup
  required, unlimited entries free forever. Open source under AGPL-3.0."
- App Store: https://apps.apple.com/app/id6769007201 · Repo: https://github.com/lokii49/mirror

### iAnonymous3000/awesome-privacy-tools — [needs GitHub PR, blocked in this env — see Blocked]
Large curated privacy-tools list (57 categories: Browsers, Notes, Productivity, AI, etc), not yet in
channel map or backlog — distinct from pluja/awesome-privacy (already OPEN) and lissy93/awesome-privacy
(gated). Confirmed via WebFetch (github.com works even though other domains are egress-blocked): no
CONTRIBUTING.md, default branch `main`, entries are plain `#### [Name](URL)` headers followed by a
description paragraph (no table, no strict alphabetical enforcement seen). Best-fit category: "Notes"
(sits alongside Standard Notes, Notesnook). Ready-to-paste entry for whoever/whatever opens the PR:

```
#### [MirrorNotes](https://mirrornotes.org)
A privacy-first journaling app for iOS. Daily nudges, weekly digests, and an "ask your journal" chat
all run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI
processing. Local-first with free CloudKit sync, no account or signup required, unlimited entries
free forever. Open source under AGPL-3.0.
```

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### manishmarahatta/awesome-mentalhealth — [needs GitHub PR, blocked in this env — see Blocked]
Curated mental-health resource list, distinct from dreamingechoes/awesome-mental-health (already OPEN)
and theimpossibleastronaut/awesome-mentalhealth (blocked-on-click). Has a dedicated "Apps" section
(Headspace, Pacifica, etc.) plus a "Selfhosted" subsection — MirrorNotes fits "Apps". Small/lightly
maintained (1 star, 16 commits) but has a real CONTRIBUTING.md with one binding rule confirmed via
WebFetch: "I don't like expensive products, but I won't list prices or mark free/premium resources" —
so the submitted description below is deliberately pricing-neutral (no "free forever" / "paid tier"
language) to comply. Entry format per CONTRIBUTING: `- [Name](url) - Brief description.` Ready-to-paste
entry for whoever/whatever opens the PR (add under "## Apps", alphabetical-ish placement near
"Muse"/"Pacifica"):

`- [MirrorNotes](https://mirrornotes.org) - A privacy-first journaling app for iOS with on-device AI (daily nudges, weekly digests, ask-your-journal) — entries never need to leave the phone for AI processing. No account required, iCloud sync, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### deluks/awesome-ios-apps — [needs GitHub PR, blocked in this env — see Blocked]
Curated consumer iOS-app list (categories: Health, Multimedia, Productivity, Reading, Social Media,
Weather), not yet in channel map or backlog — distinct from vsouza/awesome-ios (developer resources,
already ruled out) and deluks is a different maintainer entirely. No dedicated journaling/diary
category; best fit is "Productivity" (sits alongside Drafts, Things). Confirmed via WebFetch: entry
format `[Name](url) - Description.`, alphabetized within each section, no CONTRIBUTING.md at the
expected path (contribute link in README points to a `contributing.md` that 404s via raw fetch — may
just be a relative-link/case issue, worth a human double-checking before submitting), no pricing/
monetization wording restriction seen in the section itself. Ready-to-paste entry (insert
alphabetically between "Fantastical" and "ScanPro" in the Productivity section):

`[MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app with on-device AI (Gemma 3 1B) for daily nudges and journal search — nothing leaves the device for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### ysyisyourbrother/awesome-on-device-AI — [needs GitHub PR, blocked in this env — see Blocked]
Curated list of on-device/edge AI (Papers/Tutorial, Open Source Projects, Contribute), not yet in
channel map or backlog — distinct from janhq/awesome-local-ai (already OPEN, desktop/server-focused
tools) and stevelaskaridis/awesome-mobile-llm (already ruled out, papers-only Applications section).
Confirmed via WebFetch (raw README): has a genuine "Mobile LLM Apps" subsection under "Open Source
Projects" with one existing entry (Airgap, a local-LLM chatbot framework) — a real fit for a consumer
app running an on-device model, not just papers. No CONTRIBUTING.md beyond "Open an issue or send a
pull request" — no format/pricing restrictions found. Entry format confirmed from the one existing
entry: `**Name**: Description. by Creator. [[code](repo link)]`. Ready-to-paste entry for whoever/
whatever opens the PR (append under "3. Mobile LLM Apps"):

`**MirrorNotes**: Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an "ask your journal" chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0). by Lokesh Pudari. [[code](https://github.com/lokii49/mirror)]`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### awesomelistsio/awesome-ai-edge-computing — [needs GitHub PR, blocked in this env — see Blocked]
Curated edge-AI list (Frameworks and Libraries, Hardware and Accelerators, Deployment Platforms,
Optimization Tools, Applications, Learning Resources, Books, Community, Contributing, License), not
yet in channel map or backlog — distinct from all prior on-device-AI candidates (janhq/awesome-local-ai,
already OPEN; ysyisyourbrother/awesome-on-device-AI, already in Backlog). Strong fit: its own
"Applications" section already lists a directly comparable app — DailyVox, "On-device AI voice diary
app using Apple's native frameworks" — confirming consumer journaling/diary apps are in scope, not
just frameworks/papers. Confirmed via WebFetch (raw README + raw CONTRIBUTING.md): entry format
`- [Name](URL) - Brief description.`, list "alphabetically sorted (if applicable)", no pricing/
monetization wording restriction found, standard fork → branch → PR process, maintainers warn against
self-promotion/early-stage-project submissions but MirrorNotes is a shipped App Store app so this
should be fine. Ready-to-paste entry for whoever/whatever opens the PR (insert into "Applications"
section, alphabetically near "DailyVox"):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an "ask your journal" chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### Axorax/awesome-free-apps (MOBILE.md) — [needs GitHub PR, blocked in this env — see Blocked]
Curated list of free apps for PC and mobile, split into README.md (desktop) and MOBILE.md (mobile) —
not yet in channel map or backlog, distinct from all prior candidates (dev-focused awesome-swift/
awesome-ios lists were ruled out earlier as non-fits since they list libraries, not consumer apps).
Confirmed via WebFetch (raw MOBILE.md + raw contributing.md): MOBILE.md has a real "Note Taking"
category with iOS-tagged entries, plus a "Health and Wellness" category — Note Taking is the better
fit. Entry format confirmed: `- [App Name](url) - Brief description. <platform icons>` using 🍎 for
iOS and 🟢 for open-source (plus ⭐ for maintainer-recommended, not self-assignable). contributing.md
confirms: no pricing/freemium wording restriction, but explicitly "Do not change the order of any
apps like ordering alphabetically" — new entries go to the bottom of their category, not alphabetized.
Submission is a PR editing only MOBILE.md, commit message format "Add: [name]". Ready-to-paste entry
for whoever/whatever opens the PR (append to bottom of "Note Taking" category in MOBILE.md):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app for iOS with on-device AI (daily nudges, weekly digests, ask-your-journal) — entries never need to leave the phone for AI processing. No account required, iCloud sync, unlimited entries free forever, open source (AGPL-3.0). 🍎 🟢`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### naughtyspirit/awesome-ios-apps — [needs GitHub PR, blocked in this env — see Blocked]
Curated consumer iOS-app list (categories: Finance, Education, Catalogs, Music, Books, Medical,
Lifestyle, Weather, Games, Health & Fitness, Photo & Video, Sports, Reference, Social Networking,
Open Source), not yet in channel map or backlog — distinct from vsouza/awesome-ios (dev resources,
ruled out), deluks/awesome-ios-apps (already in Backlog), ThetaApps/ios-app-opensource (ruled out,
redundant fork of dkhamsing/open-source-ios-apps which is already MERGED), and
jogendra/example-ios-apps (beginner example code, not a fit). Confirmed via WebFetch (raw README +
raw CONTRIBUTING.md): has a dedicated "Open Source" section with format `[App Name](github-link) -
Description`, no journaling/notes/productivity category exists so Open Source is the right home.
CONTRIBUTING.md rules: end description with a period, no trailing whitespace, check for duplicates,
one commit per suggestion — no pricing/monetization wording restriction, no alphabetization
requirement. No prompt-injection content found in CONTRIBUTING.md. Ready-to-paste entry for
whoever/whatever opens the PR (append to "Open Source" section):

`[MirrorNotes](https://github.com/lokii49/mirror) - Privacy-first journaling app for iOS with on-device AI (Gemma 3 1B) powering daily nudges, weekly digests, and an ask-your-journal chat — nothing leaves the device for AI processing. Local-first with free CloudKit sync, no account required, unlimited entries free forever, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### alexanderop/awesome-local-first — [needs GitHub PR, blocked in this env — see Blocked]
Curated local-first list, distinct from schickling/awesome-local-first (already in Backlog) — different
maintainer, different structure (Core Resources / Dev Tools & Libraries / Real-World Examples /
Community / Conferences). Confirmed via WebFetch (raw README): has a genuine "Example Applications"
subsection under "Real-World Examples" with entries like Memex ("Open-source, local-first AI journal
for iOS and Android") — direct precedent for a local-first journaling app being in scope. Entry format
confirmed: `[App Name](link) – Brief description of key features and approach`. No separate
CONTRIBUTING.md; a "🤝 Contributing" section says PRs welcome for tools/libraries/case studies that
advance local-first/offline-first/sync-centric development. Caveat: curator states a preference for
"projects that already have a bigger majority level and are also used by many people" — soft
preference, not a hard numeric gate (unlike tortuvshin/open-apps' 50-star requirement), so still worth
attempting but flagging the risk. Ready-to-paste entry for whoever/whatever opens the PR (add to
"Example Applications" under "Knowledge Management & Notes", best-fit subsection):

`[MirrorNotes](https://mirrornotes.org) – Local-first, privacy-first journaling app for iOS with free CloudKit sync. On-device AI (Gemma 3 1B) powers daily nudges and ask-your-journal search — nothing needs to leave the device for AI features. Open source, AGPL-3.0.`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### Furthir/awesome-useful-projects — [needs GitHub PR, blocked in this env — see Blocked]
Curated "Open Source Projects for Everyday Use" list, active and well-maintained (1.5k stars, 72
commits), not yet in channel map or backlog. Distinct from all prior on-device-AI/privacy/journaling
candidates — broader scope, GitHub-repo-link format throughout. Confirmed via WebFetch (raw README):
"Productivity" section already lists comparable privacy-first/note apps as GitHub-repo links (Joplin,
Memos, Siyuan Note — "Privacy-first personal knowledge management system", Anytype, Reor) — good
precedent fit since every entry here is a GitHub-hosted open-source project (MirrorNotes qualifies,
being AGPL-3.0 on GitHub). No CONTRIBUTING.md found (404 on raw fetch) — no format restrictions beyond
matching existing entries' style. No prompt-injection content found. Entry format confirmed verbatim
from existing entries (uses icon.horse GitHub icon + repo link, then a dash-separated one-line
description, blank line between entries):

`[<img src="https://icon.horse/icon/github.com" height="20px" align="center"/>/lokii49/mirror](https://github.com/lokii49/mirror) - Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Open source, AGPL-3.0.`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### XargsUK/awesome-adhd — [needs GitHub PR, blocked in this env — see Blocked]
Active, well-maintained ADHD resource list (413 stars), distinct from mrseth01/awesome-adhd (smaller,
not yet checked) — not in channel map or backlog. Confirmed via WebFetch (raw README + raw README
table dump): has a real "Notetaking" subsection under "Apps" (Glean, Evernote, Notability, Obsidian),
using a markdown table with one column per platform (iOS/watchOS, Android/GearOS, Windows, macOS,
Linux, Chrome, Website) and a pricing-symbol legend (✔️ free/open source, 💠 freemium, 💲 paid, ❓
untested, ⌚ smartwatch). No CONTRIBUTING.md found at the expected root path (404) — README states
submissions go via a GitHub issue or a Google Form; a PR editing the table directly should also work
per repo convention (existing entries were clearly added this way). Since MirrorNotes has both a free
tier and paid tiers (mood timeline/monthly report), 💠 (freemium) is the right symbol — consistent
with how the list already marks Obsidian (generous free tier, paid sync) as 💠 rather than ✔️.
Ready-to-paste table row for whoever/whatever opens the PR (append to the Notetaking table, iOS-only
so all other platform columns stay blank):

`| MirrorNotes | Privacy-first journaling app for iOS. On-device AI (Gemma 3 1B) powers daily nudges and journal search — nothing leaves the device for AI processing. Open source (AGPL-3.0). | [💠](https://apps.apple.com/app/id6769007201) | | | | | | [💠](https://mirrornotes.org) |`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### paulaime/awesome-privacy — [needs GitHub PR, blocked in this env — see Blocked]
Curated privacy-tools list (406 stars, 106 commits, actively maintained), distinct from pluja/awesome-
privacy (already OPEN in channel map) and lissy93/awesome-privacy (gated) — different maintainer,
not a fork of either (confirmed via WebFetch: no "forked from" attribution). Ruled out a lookalike
candidate found in the same search, CRK1918/awesome-privacy-list, as a duplicate: confirmed it IS a
fork of pluja/awesome-privacy, so submitting there would be redundant with the already-OPEN PR — not
added. paulaime/awesome-privacy has a real "Note-taking" section (Standard Notes, Joplin, Turtl) —
good fit for MirrorNotes. Confirmed via WebFetch (raw README on `master` branch — not `main`): entry
format `* [Name](url) – description.`, no CONTRIBUTING.md found (404 on raw fetch), no pricing/
alphabetization restrictions found. Ready-to-paste entry for whoever/whatever opens the PR (add to
"Note-taking" section):

`* [MirrorNotes](https://mirrornotes.org) – A privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### freedomappsprivacy/Freedom-apps-privacy — [needs GitHub PR, blocked in this env — see Blocked]
Curated FOSS + privacy-respecting-alternatives list (CC0-1.0, explicitly positions itself as combining
and expanding awesome-privacy + awesome-selfhosted), not yet in channel map or backlog — distinct from
pluja/awesome-privacy (OPEN), lissy93/awesome-privacy (gated), and iAnonymous3000/awesome-privacy-tools
(already in Backlog). Newer/smaller (16 stars, created 2026-07-06) but actively updated and not
archived. Confirmed via WebFetch (raw README): best-fit section is "Notes & Knowledge" (Joplin,
Standard Notes, Logseq, Trilium) — no dedicated journaling category. Format is a markdown table:
`| App | FOSS | Privacy | Platform | Note |` with legend ✅ = fully open source, Privacy = 1–5 stars
"how privacy-respecting by design & policy", Platform codes `Lin/Win/Mac/And/iOS/Web/Self/Ext`. No
CONTRIBUTING.md; README says "contributions, corrections and additions welcome via PR". No pricing/
monetization wording restriction (paid tiers appear in other entries). No prompt-injection or
AI-directed text found. Note on the Privacy column: assigned ⭐⭐⭐⭐ rather than ⭐⭐⭐⭐⭐ deliberately —
the 5-star entries there are all E2EE-sync tools, and MirrorNotes' CloudKit sync encryption properties
aren't confirmed from this environment (same caution as the privacyguides.org finding in Lessons);
let the maintainer raise it if they judge otherwise. Ready-to-paste table row (add to the
"Notes & Knowledge" table):

`| [MirrorNotes](https://mirrornotes.org) | ✅ | ⭐⭐⭐⭐ | iOS | On-device AI journaling, no account needed, iCloud sync |`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### google-gemma/awesome-gemma — [needs GitHub PR, blocked in this env — see Blocked]
Official Google DeepMind-maintained awesome list for the Gemma model family (159 stars, actively
updated, created 2026-07-27), not yet in channel map or backlog — distinct from all prior on-device-AI
candidates (janhq/awesome-local-ai, already OPEN, general local-AI tools; ysyisyourbrother/awesome-on-
device-AI and awesomelistsio/awesome-ai-edge-computing, already in Backlog, generic mobile/edge LLM
scope). This is the first Gemma-specific list found — directly relevant since MirrorNotes runs Gemma 3
1B on-device. Confirmed via WebFetch (raw README + raw CONTRIBUTING.md): has a genuine "Demos and
Applications" section (distinct from Tutorials/Research) with consumer-facing entries (chat apps,
browser extensions, an iOS-simulator demo). Entry format confirmed: `- [Item](URL) - Short description
ending with a period.`, add to bottom of section (no alphabetization requirement). CONTRIBUTING.md
requires resources be "specifically related to Gemma models or the Gemma ecosystem" and descriptions
"factual, objective, and free from promotional claims" — so the ready-to-paste copy below avoids
marketing language ("free forever" etc.) per that rule. No prompt-injection content found in either
file. Ready-to-paste entry for whoever/whatever opens the PR (append to bottom of "Demos and
Applications" section):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model. Open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### akshaybharwani/data-not-collected-ios-apps — [needs GitHub PR, blocked in this env — see Blocked]
Curated list of iOS apps that don't collect user data (147 apps + 39 games, 10 stars, actively
updated), not yet in channel map or backlog — a strong topical fit distinct from all prior
consumer-iOS-app candidates (deluks/awesome-ios-apps, naughtyspirit/awesome-ios-apps): the whole
list's theme is "no data collection," which is exactly MirrorNotes' on-device-AI pitch. Confirmed
via WebFetch (raw README): 15 categories under "Apps" (Developer Tools, Education, Entertainment,
Finance, Food & Drink, Graphics & Design, Health & Fitness, Lifestyle, Music, News, Photo & Video,
Productivity, Reference, Social Networking, Utilities, Weather) — no journaling/notes category, so
"Productivity" is the best fit. Entries are numbered sequentially within a category (not
alphabetized), added to the bottom, format `[App Name] [(Paid) if applicable] - [App Store URL]`.
No CONTRIBUTING.md found (404 on raw fetch) — no format doc beyond the README's own convention. No
prompt-injection content found. Since MirrorNotes' core journaling is free forever (only the mood
timeline/monthly report are paid), no "(Paid)" marker per the list's own convention (it marks apps
that require payment to use at all, not freemium apps with a free core). Ready-to-paste entry for
whoever/whatever opens the PR (append to bottom of "Productivity" section):

`MirrorNotes - https://apps.apple.com/app/id6769007201`

(list format is bare name + App Store link only, no description field — repo: https://github.com/lokii49/mirror)

### mustbeperfect/definitive-opensource — [needs GitHub PR, blocked in this env — see Blocked]
Large, active "definitive list of the best of (consumer facing) open source" (3.4k stars), not yet in
channel map or backlog — distinct from all prior candidates, notably explicit that it's for
consumer-facing apps only (README: "This list is EXCLUSIVELY for apps that you use directly"),
excluding developer tools. Confirmed via WebFetch: has a "Text" category with a "Journal" subsection
(alongside Note Taking, Markdown Editor) — direct fit. Entry format is a markdown table used
consistently across sections: `| [Name](url) \`tags\` | Description | Platform(s) | **Stars** |`.
Could not fetch the exact existing rows inside the Journal subsection (page truncated on fetch), but
the table format is confirmed from multiple other sections of the same README, and no CONTRIBUTING.md
or pricing/format restriction was found. Caveat: this list includes a live GitHub star count column —
lokii49/mirror currently has 0 stars (confirmed via search_repositories), so the row will show 0 until
the repo gains stars; not a blocker per the list's own rules (no minimum-star gate found, unlike
tortuvshin/open-apps), just a cosmetic note for whoever submits. Ready-to-paste row for whoever/
whatever opens the PR (add to "Journal" subsection under "Text"):

`| [MirrorNotes](https://mirrornotes.org) | Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Open source (AGPL-3.0). | \`iOS\` | **0** |`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### dicktracey909/awesome-adhd-tools — [needs GitHub PR, blocked in this env — see Blocked]
Curated ADHD tools/apps list (53 stars, actively updated 2026-08-20), distinct from XargsUK/awesome-adhd
(already in Backlog, different maintainer/structure) — not yet in channel map or backlog. Confirmed via
WebFetch (raw README): no dedicated journaling section, but "Emotional Regulation" already lists Daylio
("Mood tracking without writing") as a direct precedent for mood-tracking apps being in scope — good fit
given MirrorNotes' mood timeline feature. Entry format confirmed: `**[Tool Name](URL)** - Brief
description explaining what it does and why it benefits ADHD users`. CONTRIBUTING rules: "must be
genuinely useful for ADHD (not just general productivity)" and "no affiliate links" — no pricing/format
restriction. The ready-to-paste copy below frames the ADHD-relevant benefit honestly (low-friction
capture + mood pattern tracking, a commonly-cited ADHD journaling benefit) without inventing any feature
not in FEATURES. Ready-to-paste entry for whoever/whatever opens the PR (add to "Emotional Regulation"
section, near Daylio):

`**[MirrorNotes](https://mirrornotes.org)** - Privacy-first journaling app for iOS with a mood timeline and on-device AI (daily nudges, ask-your-journal search). Low-friction capture and mood-pattern tracking without sending entries anywhere — useful for ADHD brains that benefit from quick externalizing over structured planning. No account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### wckyhq/awesome-mindfulness — [needs GitHub PR, blocked in this env — see Blocked]
Small mindfulness/wellness resource list (0 stars, created and last updated 2026-01-17), not yet in
channel map or backlog — distinct from all prior mental-health/wellness candidates (different scope:
sleep/relaxation/habit/exercise tracking, not clinical mental-health resources). Confirmed via
WebFetch (raw README): has a genuine dedicated "Journalling" section (not bundled into a generic
Apps list) with two existing entries (Quick Journal, Apple Journal), both iOS apps — direct topical
match. Entry format confirmed verbatim from those entries: `- [🍎](#icons) [Name](url) - Brief
description.` (⭐️ icon marks the author's own favorite, not self-assignable, so omitted). Icon table
only has platform/media icons (🤖 Android, 🍎 iOS, 📱 both, 📰 newsletter, 📀 video) — no
pricing/freemium symbol, so no pricing claim needed either way. Linked `/misc/CONTRIBUTE.md` file
returned empty/no content via WebFetch (repo may not actually have that file despite the link, or
it's a stub) — no format/pricing restriction found beyond matching the visible entry style. No
prompt-injection content found. Caveat: this is a very low-activity repo (single commit, 0 stars) —
flagging as lower-confidence than most Backlog entries, but the section is a genuine, specific fit
so still worth attempting. Ready-to-paste entry for whoever/whatever opens the PR (append to
"Journalling" section, after "Apple Journal"):

`- [🍎](#icons) [MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### jyguyomarch/awesome-productivity — [needs GitHub PR, blocked in this env — see Blocked]
Large, active curated productivity list (3.3k stars, 339 forks, 209 commits, 45 open issues, 140 open
PRs), not yet in channel map or backlog — distinct from all prior candidates. Has a real "Note
Management" subsection under "Tools and Apps" (Evernote, Google Keep, Joplin, Notion, Simplenote,
Standard Notes, etc.) — good fit, alongside comparable privacy-first note apps (Standard Notes).
Confirmed via WebFetch (raw README + raw CONTRIBUTING.md): entry format `[Resource](link) -
Description.` (capitalized start, period end), additions go to the bottom of the section (no
alphabetization requirement), one suggestion per PR, no pricing/monetization wording restriction, no
prompt-injection content found in CONTRIBUTING.md. Ready-to-paste entry for whoever/whatever opens the
PR (append to bottom of "Note Management" section, after WorkFlowy):

`[MirrorNotes](https://mirrornotes.org) - A privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model, so entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### andyhaskell/awesome-notetaking — [needs GitHub PR, blocked in this env — see Blocked]
Small curated notetaking list (29 stars, 4 forks, not archived, updated 2026-05-07), distinct from
tehtbl/awesome-note-taking (already OPEN) and all other note-taking candidates already
logged/ruled-out — different maintainer/structure (Videos / Blogs and webpages / Books / Apps).
Confirmed via WebFetch (raw README + raw CONTRIBUTING.md): has a genuine "Apps" section listing real
software products (Notion, Dash), not just techniques/videos — a fit for MirrorNotes as a shipped app.
CONTRIBUTING.md (adapted from awesome-go) requires descriptions "clear, concise, and non-promotional"
ending in punctuation, and entries "sorted alphabetically... of the author" — though the two existing
entries (Notion, Dash) aren't actually in that order, so the alphabetization rule may be loosely
enforced in practice; no pricing/monetization restriction found. No prompt-injection content found in
either file. Ready-to-paste entry for whoever/whatever opens the PR (append to "Apps" section):

`* [MirrorNotes](https://mirrornotes.org) A privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model. Open source, AGPL-3.0.`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### sfermigier/awesome-foss-alternatives — [needs GitHub PR, blocked in this env — see Blocked]
Curated "Awesome FOSS Alternatives to SaaS products for Business Use" list, not yet in channel map or
backlog — distinct from all prior candidates (broader business-SaaS scope, not consumer/privacy/AI
focused). Confirmed via WebFetch (raw README): has a "Note-taking / Personal Knowledge Management
(Evernote alternatives)" section already listing comparable open-source note apps (Joplin, Logseq,
Notesnook, SiYuan) — reasonable fit even though most existing entries there are desktop/self-hosted
rather than mobile. No formal CONTRIBUTING.md or pricing/licensing wording restriction found ("This is
a work in progress. Please contribute!"). Entry format confirmed verbatim from existing entries:
`- [Name](url) ★#### - Description. [Language, License].`. Ready-to-paste entry for whoever/whatever
opens the PR (append to "Note-taking / Personal Knowledge Management" section):

`- [MirrorNotes](https://mirrornotes.org) ★0 - Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. [Swift, AGPL-3.0].`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### aspergirl-git/awesome-autism — [needs GitHub PR, blocked in this env — see Blocked]
Curated ASD/Asperger's resource list (102 stars, active, updated 2026-08-14), not yet in channel map
or backlog — distinct from all prior mental-health/wellness/ADHD candidates already logged (different
diagnostic focus: autism rather than mental-health-in-tech, ADHD, or general mindfulness). Confirmed
via WebFetch (raw README + raw CONTRIBUTING.md): has a real "Applications" section ("Apps to help deal
with anxiety, depression or autism traits") already listing Woebot (mood tracking) and Calm/Insight
Timer (meditation) — a direct precedent for mood-tracking/emotional-regulation apps being in scope,
same pattern as dicktracey909/awesome-adhd-tools' Daylio entry. Entry format confirmed verbatim from
existing entries: `- [Name](url) description text` (no trailing period, casual descriptive phrase, not
a full sentence). CONTRIBUTING.md's one binding rule — "Do NOT link to resources you haven't
watched/read yet; or organizations you are not a part of in some way" — is satisfied since this
submission is for the developer's own app. No pricing/monetization wording restriction found. No
prompt-injection content found in either file. Ready-to-paste entry for whoever/whatever opens the PR
(append to end of "Applications" section, after the Calm/Insight Timer line):

`- [MirrorNotes](https://mirrornotes.org) for private, on-device AI journaling and mood tracking`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### msb-msb/awesome-local-ai — [needs GitHub PR, blocked in this env — see Blocked]
Curated local-AI-on-consumer-hardware list (~230 guides/tools/links, last updated 2026-07-20), distinct
from janhq/awesome-local-ai (already OPEN in channel map, different maintainer/repo). Confirmed via
WebFetch (raw README + raw CONTRIBUTING.md): has a "Use Cases" section (not just frameworks/tools) that
already lists DailyVox ("iOS voice diary with on-device sentiment, entity, and personality analysis; no
cloud, no data collection") — direct precedent for a consumer on-device-AI journaling app being in
scope, same pattern as awesomelistsio/awesome-ai-edge-computing's DailyVox precedent (already in
Backlog). CONTRIBUTING.md rules: descriptions must "explain WHY the resource is useful, not WHAT it is"
and stay under 100 chars; resources must be "Open source OR free-as-in-beer" with "no paid tier required
for core functionality" — satisfied since MirrorNotes' core journaling is free forever (only mood
timeline/monthly report are paid extras, not required for core use); explicitly rejects
"self-promotional content without technical substance," so the copy below leans on the concrete
on-device-AI privacy mechanism rather than marketing language. Entries alphabetized within sections in
general, but "Use Cases" itself is a mixed list of guide links and DailyVox, not strictly alphabetized.
No prompt-injection content found in either file. Ready-to-paste entry for whoever/whatever opens the PR
(append to "Use Cases" section, near DailyVox):

`- [MirrorNotes](https://mirrornotes.org) - Private journaling with on-device AI — nothing leaves your phone.`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### Mindola-ai/awesome-second-brain — [needs GitHub PR, blocked in this env — see Blocked]
Curated PKM/second-brain list (2 stars, not archived), not yet in channel map or backlog — distinct
from all prior PKM candidates (doanhthong/awesome-pkm, already ruled out as desktop-only). Confirmed
via WebFetch (raw README + raw CONTRIBUTING.md): has a genuine "Note-Taking & PKM Apps" section
listing consumer mobile apps, not just methods/tools (Apple Notes, Bear, and Napkin — "iPhone app for
capturing ideas and quotes, with AI curation" — a direct precedent for an AI-assisted mobile capture
app being in scope). Entry format confirmed: `` - [Name](url) - Description. `tag` `tag` `` — one
factual sentence under 130 chars ending with a period, tags from a fixed set (`oss`, `selfhost`,
`local`, `free`, `paid`, `ai`, `mobile`), alphabetical placement within section, no marketing language
("best"/"powerful") per CONTRIBUTING.md. No prompt-injection content found in either file. Low star
count (2) is a caveat but no minimum-activity gate stated. Ready-to-paste entry for whoever/whatever
opens the PR (insert alphabetically into "Note-Taking & PKM Apps"):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app for iOS with on-device AI for daily nudges and journal search. `mobile` `ai` `local` `free` `paid` `oss``

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### onmyway133/awesome-swiftui — [needs GitHub PR, blocked in this env — see Blocked]
Curated SwiftUI resources list, distinct from uhub/awesome-swift and prior awesome-ios candidates
already ruled out (dev-resource lists with no consumer-app section). Confirmed via WebFetch (raw
README): has a genuine "Open source apps" section (iOS subsection) listing shipped consumer apps
built with SwiftUI, not just libraries/tutorials — already includes DailyVox ("AI voice diary using
SwiftUI ... On-device transcription, mood tracking, Digital Twin"), a direct precedent for an
on-device-AI diary app being in scope (same DailyVox precedent seen in awesomelistsio/
awesome-ai-edge-computing and msb-msb/awesome-local-ai, already in Backlog). Entry format confirmed
verbatim from surrounding entries: `- [Name](GitHub URL) - Brief technical description.` — links to
the GitHub repo, not the marketing site, matching this section's convention. No CONTRIBUTING.md
found, no alphabetization or pricing/promotional-language restriction seen, no prompt-injection
content found. Ready-to-paste entry for whoever/whatever opens the PR (append to "Open source apps"
→ iOS subsection):

`- [MirrorNotes](https://github.com/lokii49/mirror) - Privacy-first journaling app for iOS built with SwiftUI. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### brettkromkamp/awesome-knowledge-management — [needs GitHub PR, blocked in this env — see Blocked]
Large, active curated knowledge-management list (868 stars, 80 forks, CC0-1.0, 267 commits), not yet
in channel map or backlog — distinct from all prior PKM candidates (knowfox/awesome-pkm, ruled out
this run as no-fit: only Approaches/Lists/Articles/Tools sections, Tools has just one entry;
doanhthong/awesome-pkm and Mindola-ai/awesome-second-brain, already ruled out/in-backlog separately).
Confirmed via WebFetch (raw README + raw CONTRIBUTING.md): has a broad "Platforms, Applications and
Tools" section (85+ entries) already containing a directly comparable app — Persona, "Local-first
personal workspace: notes, tasks and AI chat. Plain markdown files, no accounts, no cloud." — a strong
precedent for a local-first, no-account, AI-assisted personal app being in scope. Entry format
confirmed: `- [Name](link) - Description`, additions go to the bottom of the category (not
alphabetized — section order is not alphabetical in practice). CONTRIBUTING.md's one substantive rule
is "must have first-hand experience with suggestion" (satisfied — this is the developer's own app), no
pricing/promotional-language restriction, no prompt-injection content found in either file. Ready-to-
paste entry for whoever/whatever opens the PR (append to bottom of "Platforms, Applications and
Tools"):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first journaling app for iOS. Daily nudges, weekly digests, and an ask-your-journal chat run fully on-device via a local Gemma 3 1B model — entries never need to leave the phone for AI processing. Local-first with free CloudKit sync, no account required, open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### ivon852/awesome-foss-ios-apps — [needs GitHub PR, blocked in this env — see Blocked]
Curated FOSS iOS apps list, Chinese-language (35 stars, active, created 2026-07-23, updated
2026-08-25), not yet in channel map or backlog — distinct from all prior candidates. Confirmed via
WebFetch (raw README): table-based categories (third-party app stores, browsers, network,
communication, productivity, multimedia, navigation, social media, finance, input methods, games,
development, utilities); no dedicated journaling category, but "生產力" (Productivity) already lists
comparable open-source note apps (Simplenote, Standard Notes, Joplin) — good fit. Entry format
confirmed: `| [App Name](link) | Brief description. |` (two-column table row), not alphabetized, no
CONTRIBUTING.md found (404 on raw fetch) — no format/pricing restriction beyond matching the table's
own language convention (descriptions are in Traditional Chinese). No prompt-injection content found
(only a benign "use the sidebar TOC" note). Ready-to-paste entry for whoever/whatever opens the PR
(add to the "生產力" table; translation kept literal to FEATURES, no claims beyond them):

`| [MirrorNotes](https://mirrornotes.org) | 注重隱私的 iOS 日記應用，AI 功能(每日提示、每週摘要、「詢問日記」)皆在裝置端運行(本地 Gemma 3 1B 模型),內容無需離開手機進行 AI 處理。本地優先,免費 iCloud 同步,無需註冊帳戶,開源(AGPL-3.0)。 |`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### nowork-studio/awesome-ai-startups — [needs GitHub PR, blocked in this env — see Blocked]
Curated directory of AI startups built by independent founders ("bootstrapped, pre-seed, and
angel-funded products from outside the big AI labs"), active (79 stars, updated same day), not yet
in channel map or backlog — distinct from all prior candidates, this is the first "indie AI startup"
directory found rather than a privacy/journaling/local-first/on-device-AI list, and MirrorNotes is a
genuinely bootstrapped indie product using AI meaningfully. Confirmed via WebFetch (raw README + raw
contributing.md): 19 categories, best fit is "🗂 Productivity & Notes" (226 existing entries). Entry
format confirmed: `- [Name](url) - One-line tagline.`, appended to the END of the section only —
contributing.md explicitly forbids reordering/inserting mid-section ("new tools must go at the end of
the section"). Inclusion criteria confirmed met: bootstrapped/no Series A, live product an end user
can download, uses AI meaningfully (on-device Gemma 3 1B), live website. No pricing-wording
restriction found (freemium entries appear throughout unrestricted). No prompt-injection or
AI-directed text found in contributing.md. Ready-to-paste entry for whoever/whatever opens the PR
(append to the very end of the "🗂 Productivity & Notes" section, after its last existing entry):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first iOS journaling app with on-device AI (Gemma 3 1B) for daily nudges, weekly digests, and an ask-your-journal chat — nothing leaves the device for AI processing. Open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### anondotli/awesome-privacy-tools — [needs GitHub PR, blocked in this env — see Blocked]
Curated privacy-tools list (70 stars, 44 forks, created 2026-04-27, active, last updated 2026-09-06),
not yet in channel map or backlog — distinct from iAnonymous3000/awesome-privacy-tools (already in
Backlog, different owner/project entirely), pluja/awesome-privacy (OPEN), lissy93/awesome-privacy
(gated), and paulaime/awesome-privacy (already in Backlog). Confirmed via WebFetch (raw README + raw
CONTRIBUTING.md): has a "Private Cloud Storage, Notes, and Collaboration" section already listing
comparable note-taking/local-first apps (Joplin, Standard Notes, Notesnook, Anytype, qnote) — good fit.
Checked the list's "Mobile Privacy Tools" section too, but it's explicitly Android-only (F-Droid,
Orbot, NetGuard) — not the right home. Entry format confirmed: `- [Name](url) - One clear sentence
ending in a period.`, added alphabetically within the section (MirrorNotes sorts between Joplin and
Nextcloud). CONTRIBUTING.md rules: no hype words ("best"/"ultimate"/"military-grade"), link to the
official website first, open-source preferred but not mandatory (no self-hosted/E2EE/star/commit/age
requirement), and project-affiliated submitters must add a disclosure line in the PR description
("Disclosure: I maintain this project."). No prompt-injection content found in either file. Ready-to-
paste entry for whoever/whatever opens the PR (insert alphabetically after Joplin, before Nextcloud, in
"Private Cloud Storage, Notes, and Collaboration"):

`- [MirrorNotes](https://mirrornotes.org/) - Open-source (AGPL-3.0) iOS journaling app with on-device AI (daily nudge, weekly digest, ask-your-journal, mood timeline); unlimited free entries, no account required, optional iCloud sync.`

PR description must include: "Disclosure: I maintain this project." Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201

### google-gemma/awesome-gemma — [needs GitHub PR, blocked in this env — see Blocked]
Google's community awesome-list for the Gemma model ecosystem (524 stars, active, Apache-2.0, not
archived, not a fork of any already-merged target). Not previously checked — prior runs covered
Gemma-adjacent dev-tooling/mobile-LLM lists but never this Gemma-specific one. Has a real
`## Demos and Applications` section showcasing shipped apps/tools built on Gemma (e.g. Gemma Chat,
WebGemma, Gemma-Translator) — a genuine fit since MirrorNotes runs Gemma 3 1B on-device. Confirmed via
raw README + raw CONTRIBUTING.md fetch (no prompt-injection content found). CONTRIBUTING.md rules:
entry must be specifically Gemma-related (MirrorNotes qualifies), verify not already listed, add to the
bottom of the section, format `- [Item](URL) - Short description ending with a period.`, keep
descriptions factual/non-promotional, submissions may be rejected for quality. Ready-to-paste entry for
whoever/whatever opens the PR (append at the bottom of "Demos and Applications"):

`- [MirrorNotes](https://mirrornotes.org) - Privacy-first iOS journaling app running Gemma 3 1B fully on-device for daily nudges, weekly digests, and an ask-your-journal chat; open source (AGPL-3.0).`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201 — blocked
from opening the PR directly in this session (see Blocked: `add_repo` cross-tier restriction, same as
every other third-party repo).

### jasiek-net/awesome-psychology-projects — [needs GitHub PR, blocked in this env — see Blocked]
"Technological projects related to psychology and mental health" (25 stars, active — last updated
2026-08-01, not archived, not a fork), not yet in channel map or Backlog — distinct from every other
mental-health list already logged. Has a real "Mental health" section already listing a directly
comparable app (`mauleenn/HarmonyMood - mood tracking iOS app to improve their mental health`) — a
genuine fit for MirrorNotes' mood-timeline/journaling angle. Confirmed via raw README + raw
contributing.md fetch: no CONTRIBUTING rules beyond generic PR-template boilerplate ("Make sure you
take care of this" placeholder text, not real binding rules), no prompt-injection content found. Entry
format confirmed from existing "Mental health" section: `- [owner/repo](url) - lowercase description`.
Ready-to-paste entry for whoever/whatever opens the PR (append to the "Mental health" section):

`- [lokii49/mirror](https://github.com/lokii49/mirror) - privacy-first iOS journaling app with on-device AI (Gemma 3 1B) for daily mood nudges and a mood timeline; open source (AGPL-3.0)`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201 — blocked
from opening the PR directly in this session (see Blocked: `add_repo` cross-tier restriction).

### noxsentin/switz — [needs GitHub PR, blocked in this env — see Blocked]
"List of 'everything' that respects your privacy" (4 stars, 0 forks, not archived, active — created
2026-01-03, updated 2026-09-13), not yet in channel map or Backlog. Has a real "Notes and Tasks" →
"Notes" section already listing directly comparable privacy/E2EE note apps (Standard Notes, Notesnook,
Cryptee, Anytype) — a genuine fit for MirrorNotes' privacy-first-notes angle even though the section
isn't journaling-specific. No CONTRIBUTING.md exists (404 at both `CONTRIBUTING.md` and
`.github/CONTRIBUTING.md`) and no contribution instructions found in the README body — low authority
(4 stars) and no stated submission rules, so treat as lower-confidence than most Backlog entries, but
the fit itself is real. Entry format inferred from existing rows in the same table:
`| [Name](url) | Description |`. Ready-to-paste entry for whoever/whatever opens the PR (append to the
"Notes" table under "Notes and Tasks"):

`| [MirrorNotes](https://mirrornotes.org) | Privacy-first iOS journaling app; all AI (daily nudges, weekly digests, ask-your-journal chat) runs fully on-device via a local Gemma 3 1B model; free-forever unlimited entries, local-first storage with optional free CloudKit sync, no account required, open source (AGPL-3.0). |`

Repo: https://github.com/lokii49/mirror · App Store: https://apps.apple.com/app/id6769007201 — blocked
from opening the PR directly in this session (see Blocked: `add_repo` cross-tier restriction).

### rodrgds/open-apps — [web-form primary, GitHub PR fallback — both blocked in this env, needs user]
"A curated, self-refreshing directory of real open-source application codebases" — not yet in channel
map or Backlog. Confirmed via WebFetch on raw README + CONTRIBUTING.md (github.com content domain,
reachable): active, real inclusion criteria ("a usable application... public source repository...
verifiable open-source license... sufficient documentation," explicitly excludes libraries/tutorials/
boilerplates/demos; "popularity is useful context, not an automatic pass" — no star/commit gate, unlike
tortuvshin/open-apps). No prompt-injection content found in either file. MirrorNotes is a real fit:
shipped app, AGPL-3.0, public repo, documented. Two submission paths, both stated in CONTRIBUTING.md:

1. **Web form (fastest, per their own docs)**: https://openappscout.com/submit — "drafts a YAML record
   from a public GitHub URL; you review the taxonomy and open a pull request." Just paste
   `https://github.com/lokii49/mirror` into the form. (WebFetch to openappscout.com itself is blocked
   in this env — non-github content domain — so the exact form UI couldn't be previewed, but the
   mechanism is simple per CONTRIBUTING's own description.)
2. **Manual PR fallback**: add `data/records/mirrornotes.yml` (or similar slug) with fields
   `description`, `category` (Productivity fits best — existing entries like Habo are privacy-first
   productivity apps; no dedicated journaling/privacy category exists yet), `primaryStack` (Swift/
   SwiftUI), `platforms` (iOS), `tags` (free-form — suggest `privacy`, `journaling`, `on-device-ai`,
   `agpl`), `bestFor`, `whyListed`, `caveats`. Exact example record not confirmed (no existing record
   file found at a guessed path; API directory listing blocked in this env) — whoever submits should
   check an existing record in `data/records/` for exact field syntax before opening the PR. Repo-side
   PR is blocked from this session regardless (see Blocked: `add_repo` cross-tier restriction), so only
   the web-form path is realistically actionable by a human without cloning the repo themselves.

App Store: https://apps.apple.com/app/id6769007201.

## Log

Runs 1-76 (through 2026-09-18) archived in `.claude/marketing-loop-log-archive.md`
to keep this file readable in one pass — read it too if you need older history. Most recent
20 runs kept below.

- 2026-09-12 (run 76): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing
  sent, Sent log untouched (still empty). curl to example.com via the agent proxy still 403s
  (`connect_rejected`, confirmed via proxy status endpoint) — general web egress still blocked
  (github.com and raw.githubusercontent.com still reachable directly via curl; api.github.com for
  non-session repos still rejected). GitHub `pull_request_read` on janhq/awesome-local-ai#131 and
  `add_repo` for janhq/awesome-local-ai both still rejected ("Allowed repositories: lokii49/mirror" /
  "cross-tier adds are not supported in v1") — priority-1 bump and direct third-party PRs remain
  impossible. For priority 2, tried six fresh WebSearch angles (awesome CoreML on-device apps
  showcase, awesome llama.cpp apps showcase iOS, awesome digital-minimalism/slow-productivity apps
  directory, open-source Day One journal alternatives, awesome bullet-journal/gratitude-journal apps,
  awesome on-device-AI privacy apps directory 2026) — surfaced two new candidates, both checked via
  raw README fetch and ruled out: diegoleme/awesome-open-source-alternatives (strictly "alternative to
  [named product]" sections, no Day One/journaling section or category) and ai-collection/ai-collection
  (evolved into a monetized commercial-AI-SaaS directory, no personal-journaling/privacy category) —
  recorded in Lessons. No new candidate cleared the fit bar this run. No PRs opened, no comments
  posted, no emails sent — 76th consecutive run blocked purely on environment/session config (GitHub
  cross-owner scope, general web egress, SMTP egress), all three re-verified fresh this run with
  unchanged evidence; not re-flagging via notification since run 43 (2026-08-29) already flagged this
  exact standing condition and nothing has materially changed since.

- 2026-09-12 (run 77): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing
  sent, Sent log untouched (still empty). curl to example.com via the agent proxy still 403s
  (`CONNECT tunnel failed`) while github.com API calls return 400/403 for non-session repos — general
  web egress still blocked. GitHub `pull_request_read` on janhq/awesome-local-ai#131 still rejected
  ("Allowed repositories: lokii49/mirror") — priority-1 bump and direct third-party PRs remain
  impossible (the github MCP server also disconnected mid-run and did not reconnect in time to retry
  anything else). For priority 2, tried two fresh WebSearch angles (LLM-powered iOS app directories,
  "privacy by design" app directories) — surfaced only already-logged lists, generic dev-facing
  LLM-agent/RAG app collections (Shubhamsaboo/awesome-llm-apps and lookalikes — code samples, not
  consumer-app directories), and one new academic/engineering resource list
  (AbductiveReason/AwesomePrivacyEngineering — books/NIST/PETs libraries, no consumer-app section) —
  all ruled out and recorded in Lessons. No new candidate cleared the fit bar this run. No PRs opened,
  no comments posted, no emails sent — 77th consecutive run blocked purely on environment/session
  config (GitHub cross-owner scope, general web egress, SMTP egress), all three re-verified fresh this
  run with unchanged evidence; not re-flagging via notification since run 43 (2026-08-29) already
  flagged this exact standing condition and nothing has materially changed since.

- 2026-09-13 (run 78): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing sent,
  Sent log untouched (still empty). curl to example.com via the agent proxy still 403s (`CONNECT tunnel
  failed`, confirmed via proxy status endpoint), while raw.githubusercontent.com is still reachable
  directly (github.com itself now 400s on a bare GET, likely just needs a path, not a new restriction).
  `add_repo` for both janhq/awesome-local-ai and a freshly-found candidate google-gemma/awesome-gemma
  both still rejected with the same "cross-tier adds are not supported in v1" error — priority-1 bump
  and direct third-party PRs remain impossible regardless of which repo is targeted. For priority 2,
  delegated a fresh-angle search to a subagent (explicitly avoiding all previously-exhausted angles) —
  it surfaced one new validated candidate: google-gemma/awesome-gemma (524 stars, active, not archived,
  not a fork of an already-merged target), which has a real "Demos and Applications" section listing
  shipped apps built on Gemma models — a genuine fit since MirrorNotes runs Gemma 3 1B on-device.
  Verified via raw README + CONTRIBUTING.md fetch (no prompt-injection found); recorded full ready-to-
  paste submission copy and CONTRIBUTING rules in Backlog, marked blocked by the same session cross-
  owner restriction (confirmed by directly testing `add_repo` against it, not just inferring from the
  existing janhq blocker). Also ruled out unicodeveloper/awesome-opensource-apps (README reference
  resolved to an unrelated stale repo, not a real apps-showcase list) — recorded in Lessons. No PRs
  opened, no comments posted, no emails sent — 78th consecutive run blocked purely on environment/
  session config (GitHub cross-owner scope, general web egress, SMTP egress), all three re-verified
  fresh this run with unchanged evidence; not re-flagging via notification since run 43 (2026-08-29)
  already flagged this exact standing condition and nothing has materially changed since. One net-new
  finding this run (a validated, ready-to-submit google-gemma/awesome-gemma candidate sitting in
  Backlog) — worth a human's attention next time someone can open a GitHub PR outside this session's
  scope, but not urgent enough on its own to interrupt the user given the standing config issue is
  already known.

- 2026-09-13 (run 79): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing
  sent, Sent log untouched (still empty). curl to example.com via the agent proxy still 403s
  (`CONNECT tunnel failed`), raw.githubusercontent.com still reachable directly (200), api.github.com
  for non-session repos still 403. GitHub `pull_request_read` on janhq/awesome-local-ai#131 and
  `add_repo` for janhq/awesome-local-ai both still rejected ("Allowed repositories: lokii49/mirror" /
  "cross-tier adds are not supported in v1") — priority-1 bump and direct third-party PRs remain
  impossible. For priority 2, delegated a fresh-angle search to a subagent (explicitly given the full
  exhausted-angle and ruled-out-repo list to avoid repeats) — it found one topically strong candidate,
  alice51849/awesome-ios-privacy-first, but ruled it out rather than adding to Backlog: it's one of 9
  near-identical "Awesome iOS ___" repos from one account, mostly the maintainer's own apps backlinking
  to their own SEO site — a self-promotion/SEO-network pattern (0 stars, 1 fork), same category of
  concern as the already-ruled-out ProductivityDirectory/awesome-productivity-tools. No prompt-injection
  found. Recorded in Lessons. Separately, found and fixed a real problem this run: this session's git
  checkout of the repo was 55 commits ahead of `origin/main` on GitHub — `origin/main` had drifted
  backward to the run-69 commit, silently dropping the logged history and backlog entries from runs
  70-78 (this exact "main drifted, needs recovery" issue happened before at runs 68-69, and has now
  recurred). Verified the local history was a clean fast-forward ancestor of origin's current tip
  before pushing (no force needed) and pushed to restore origin/main to the full history through run 78
  before adding this run's own commit on top. No PRs opened, no comments posted, no emails sent this
  run. Flagging the recurring main-drift issue via notification since it means work has been silently
  disappearing from the actual GitHub repo between sessions, which is a new/changed condition worth a
  human's attention (unlike the standing env blockers, already flagged and unchanged since run 43).

- 2026-09-13 (run 80): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing
  sent, Sent log untouched (still empty). curl to example.com via the agent proxy still 403s
  (`CONNECT tunnel failed`), raw.githubusercontent.com still reachable directly (200). `add_repo`
  (push access) for janhq/awesome-local-ai still rejected with the same "cross-tier adds are not
  supported in v1" error (session already scoped to lokii49/mirror) — priority-1 bump and direct
  third-party PRs remain impossible. Before this, verified this session's local checkout was NOT
  drifted from origin/main (matched at run-79's commit 5600910) — the run-79 drift-recovery held,
  no repeat of that issue this run. For priority 2, tried five fresh angles: checked
  ggml-org/llama.cpp's own README directly (MirrorNotes' on-device stack is llama.cpp-based) for a
  UI/third-party-apps showcase section — none exists in the current README (ruled out, recorded in
  Lessons); WebSearched "on-device AI iOS apps directory 2026", "small language model apps showcase
  iOS journaling", "private journaling app open source no ads no tracking", "open source mental
  health apps directory PR contributions welcome", and "Gemma-powered apps community showcase" — all
  surfaced only already-logged repos (google-gemma/awesome-gemma re-confirmed, still sitting in
  Backlog from run 78, still blocked the same way) or individual competitor apps, not new directory
  candidates. No new candidate cleared the fit bar this run. No PRs opened, no comments posted, no
  emails sent — 80th consecutive run blocked purely on environment/session config (GitHub
  cross-owner scope, general web egress, SMTP egress), all three re-verified fresh this run with
  unchanged evidence; not re-flagging via notification since this is an unchanged standing condition
  (last flagged for a genuinely new development at run 79's drift-recovery, which itself is now
  resolved and non-recurring this run).

- 2026-09-14 (run 81): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing
  sent, Sent log untouched (still empty). curl to example.com via the agent proxy still 403s (`CONNECT
  tunnel failed`), raw.githubusercontent.com still reachable directly (200). `pull_request_read` on
  janhq/awesome-local-ai#131 and `add_repo` (push) for janhq/awesome-local-ai both still rejected
  ("Allowed repositories: lokii49/mirror" / "cross-tier adds are not supported in v1") — priority-1
  bump and direct third-party PRs remain impossible, now confirmed unchanged across a full calendar
  day since run 80. Verified local checkout matched origin/main (b9f3d4f, run 80's commit) before
  starting — no drift this run. For priority 2, used GitHub code search (`search_repositories` with
  `topic:mental-health`, sorted by stars) as a fresh discovery angle instead of WebSearch — surfaced
  jasiek-net/awesome-psychology-projects (25 stars, active, not archived, not a fork), which has a
  "Mental health" section already listing a directly comparable app (HarmonyMood, an iOS mood-tracking
  app) — a genuine new fit not previously found or ruled out. Verified via raw README + raw
  contributing.md fetch: no binding CONTRIBUTING rules beyond generic PR-template boilerplate, no
  prompt-injection content found. Recorded ready-to-paste submission copy in Backlog, marked blocked by
  the same session cross-owner restriction as every other third-party repo. No PRs opened, no comments
  posted, no emails sent — 81st consecutive run blocked purely on environment/session config (GitHub
  cross-owner scope, general web egress, SMTP egress), all three re-verified fresh this run with
  unchanged evidence; not re-flagging via notification since this remains the same standing condition
  already flagged (run 43) with nothing materially new this run beyond one additional backlog
  candidate.

- 2026-09-15 (run 82): Re-confirmed all three env blockers fresh this run with live tests: `/dev/tcp`
  to smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible, nothing
  sent, Sent log still empty (0 emails sent across 82 runs since 2026-08-15). curl to example.com via
  the agent proxy still 403s (`CONNECT tunnel failed`), raw.githubusercontent.com still reachable
  directly (200). `add_repo` (push) for janhq/awesome-local-ai still rejected ("cross-tier adds are
  not supported in v1") — priority-1 bump and direct third-party PRs remain impossible, unchanged
  since run 43. Verified local checkout matched origin/main (ed897d5, run 81's commit) before
  starting — no drift this run. For priority 2, tried a new discovery technique: code-searching
  GitHub for competitor-app-name mentions inside README.md files (started with "Reflectly") instead
  of searching list names/topics — surfaced fluttergems/awesome-open-source-flutter-apps (has a real
  journaling-apps precedent) but ruled it out as Flutter-only scope, wrong tech stack for MirrorNotes
  (Swift/SwiftUI). Also checked Dieterbe/awesome-health-fitness-oss and Kailash-Way/awesome-meditation
  (topic:mindfulness/topic:self-improvement hits) — both ruled out, no journaling/diary section in
  either. topic:diary and topic:journaling searches returned zero results. No new candidate cleared
  the fit bar this run; all findings recorded in Lessons so future runs don't re-check them. No PRs
  opened, no comments posted, no emails sent — 82nd consecutive run blocked purely on
  environment/session config. Flagging via notification this run: it has now been a full calendar
  month (since 2026-08-15) and 82 runs with these same three blockers unresolved, zero emails ever
  sent, and zero third-party PRs ever opened by this loop directly (the three MERGED entries and one
  OPEN-when-last-checked set predate or were arranged outside this specific session/environment
  restriction) — the Backlog has grown to ~30 fully-drafted, ready-to-paste submissions sitting idle.
  Re-flagging now since a month of silence on an unresolved blocker is itself worth a fresh nudge,
  even though the underlying condition hasn't changed since run 43.

- 2026-09-15 (run 83): Re-confirmed env blockers fresh this run (same day as run 82, but a genuinely
  separate invocation — verified local checkout matched origin/main at 0e8c186, run 82's commit,
  before starting): `/dev/tcp` to smtp.mail.me.com:587 still times out — priority-3 email still
  impossible, nothing sent, Sent log still empty (0 emails across 83 runs). curl to example.com via
  the agent proxy still 403s (`CONNECT tunnel failed`). GitHub scope reconfirmed via a new signal
  this run: `get_file_contents` on argit2/awesome-self-care (a third-party repo) was rejected with
  "not configured for this session" — same restriction as `add_repo`/`pull_request_read`, now shown
  to cover read-only content fetches too, not just writes. Priority-1 bump and direct third-party PR
  creation remain impossible. For priority 2, tried the competitor-app-name code-search technique
  again with "Daylio", "Grid Diary", "Stoic" — no new directory candidate (see Lessons); also checked
  argit2/awesome-self-care (topic-name hit) and ruled it out as a 6-year-abandoned personal tips list,
  not a product directory. No PRs opened, no comments posted, no emails sent — 83rd consecutive run
  blocked purely on environment/session config, unchanged since run 43. Not re-flagging via
  notification this run: run 82 already surfaced the month-long-blocker status a few hours earlier
  today and nothing material changed since (same three blockers, same evidence) — repeating the same
  notification same-day would be noise, not signal.

- 2026-09-15 (run 84): Re-confirmed all three env blockers fresh this run with live tests: GitHub
  `get_file_contents` on janhq/awesome-local-ai rejected ("not configured for this session, allowed:
  lokii49/mirror"), `add_repo` for janhq/awesome-local-ai (push) rejected ("cross-tier adds are not
  supported in v1") — priority-1 bump and priority-2 direct third-party PRs remain impossible, unchanged
  since run 43 (note: `list_repos` shows several `lokii49/*` forks of target repos already attached
  with push access, but that's a separate tool-scope from the GitHub MCP tools actually used for
  PRs/comments, which stayed locked to lokii49/mirror only). `/dev/tcp` to smtp.mail.me.com:587 timed
  out (exit 124) — priority-3 email still impossible, nothing sent, Sent log still empty (0 emails
  across 84 runs). curl to example.com via the agent proxy still 403s. For priority 2, tried the
  competitor-app-name code-search technique with "Presently", "Diarium", "Journey", "Pixels",
  "Journalize", "DabbleMe" — found and ruled out two candidates (jaywcjlove/awesome-mac: Journaling
  section requires a Mac app, MirrorNotes is iOS-only; everestpipkin/tools-list: wrong scope, dev-tool
  list, and no longer accepts GitHub PRs) — see Lessons. No new candidate cleared the fit bar. No PRs
  opened, no comments posted, no emails sent — 84th consecutive run blocked purely on
  environment/session config, all three re-verified fresh with unchanged evidence. Not re-flagging via
  notification: run 82 already surfaced the month-long-blocker status earlier today and nothing
  material has changed since (same three blockers, same evidence, one more Backlog candidate ruled
  out) — a same-day repeat notification would be noise, not signal.

- 2026-09-16 (run 85): Re-confirmed all three env blockers with fresh live tests this run: session
  GitHub scope still shows only `lokii49/mirror` (per environment repo-scope banner, no need to burn
  an `add_repo` call to re-prove it — unchanged since run 84), `/dev/tcp` to smtp.mail.me.com:587
  timed out (SMTP_BLOCKED), and `curl` through the agent proxy to example.com returned a 403 CONNECT
  tunnel failure — priorities 1 and 3 remain impossible, nothing sent, Sent log still empty. For
  priority 2, tried a new discovery angle instead of repeating prior competitor-name searches:
  `search_repositories` for "awesome journaling"/"awesome diary" sorted by most-recently-updated
  (to catch anything created/changed since the last sweep) — all results were either academic-journal
  lists, unrelated toy/personal repos, or noise matches on the word "diary"/"awesome" in unrelated
  projects; no new curated consumer-app directory surfaced. No PRs opened, no comments posted, no
  emails sent, no new Backlog entry added — 85th consecutive run blocked purely on environment/session
  config, all three re-verified fresh with unchanged evidence. Not notifying: identical standing
  blocker already surfaced in prior runs' notifications, nothing material changed.
- BrethofAI/awesome-private-ai and BrethofAI/awesome-local-ai (companion lists, active, well-maintained,
  real inclusion criteria) are not fits: both are strictly dev/infra tool catalogs (inference runtimes,
  self-hostable stacks, desktop chat apps, privacy-auditing utilities, open-weights models) — no section
  for consumer-facing mobile/journaling apps in either. Confirmed 2026-09-16 via raw README fetch on
  both; do not re-add unless either gains a consumer-apps section.
- topic:journal-app and "awesome mental-wellness" searches this run surfaced only individual competitor
  journal apps (memex, June, storypad, ReJournal, memlore, etc. — not directories) or a single unrelated
  toy repo — no new curated-directory candidate. Confirmed 2026-09-16; do not re-try these exact angles
  again.

- 2026-09-16 (run 86): Re-confirmed the standing blockers with fresh/cheap checks this run rather than
  the full 3-way re-verification (per Lessons guidance not to burn a diagnostic every single run):
  session GitHub repo scope confirmed still `lokii49/mirror`-only directly from this session's own
  environment banner (no tool call needed — unchanged since run 84/85), and `/dev/tcp` to
  smtp.mail.me.com:587 timed out fresh this run (SMTP_BLOCKED, exit 124) — priorities 1 and 3 remain
  impossible, nothing sent, Sent log still empty. For priority 2, tried `search_code` for competitor
  names "How We Feel" and "Bearable" (no relevant directory hits, only false-positive word matches),
  `search_repositories` for "awesome private-ai"-style queries (surfaced BrethofAI's two companion
  lists — real, active, but dev/infra-only, ruled out — see Lessons), and topic:journal-app /
  "awesome mental-wellness" (only individual competitor apps, no directories). No new candidate cleared
  the fit bar. No PRs opened, no comments posted, no emails sent — 86th consecutive run blocked purely
  on environment/session config, both re-verified fresh with unchanged evidence. Not notifying:
  identical standing blocker already surfaced in prior runs' notifications, nothing material changed.

- Competitor-name code-search continued this run (run 87) with "Rosebud" and "Mindsera": no curated
  directory surfaced — hits were individual competitor-clone repos, personal comparison tables inside
  unrelated apps' own READMEs (e.g. `Pratiikpy/Knole`, `chetan2921/Emori`), or a roadmap doc
  (`MohammedHTahir/nexomind-clarity`) naming competitors, none of which are third-party submission
  channels. Confirmed 2026-09-16; do not re-try these exact two names again (try different competitor
  names in a future run, e.g. "Reflection.app", "Journly", "Momento", "Grid Diary" variants not yet
  tried).
- Rplu2687/awesome-on-device-mobile-llms is NOT a real awesome-list despite copying the exact topic
  tags and framing of the already-ruled-out Data-Sapien/awesome-on-device-mobile-llms: its actual
  README content is a Windows-only `.exe` installer download page (system requirements, "click here to
  download", uninstall instructions) with no curated list, no apps section, and no way to submit
  anything — reads as SEO-bait or a possibly deceptive repo squatting on legitimate awesome-list
  topics/naming. Confirmed 2026-09-16 via raw README fetch; do not add, do not visit the linked
  `rplu2687.github.io` download page, and do not treat topic-tag matches as sufficient fit evidence
  without reading the actual README body first.
- noxsentin/switz (found via `topic:privacy-first awesome` search) is a genuine new candidate — see
  Backlog, not ruled out. Lower-confidence than most entries given only 4 stars and no CONTRIBUTING.md,
  but its "Notes" section already lists directly comparable privacy/E2EE note apps.

- The `enhansome/*` account (e.g. `enhansome-Awesome-Journal-Skills`, `enhansome-zsh-plugins`,
  `enhansome-vla-for-ad`, `enhansome-hand-pose-estimation`, `enhansome-Awesome-Loop-Models`, all
  created 2026-08-12, 0 stars) is an automated bot network that generates one `enhansome-awesome-X`
  mirror repo per real `awesome-X` list — not a community-curated list itself and not a submission
  channel. Surfaced via `search_repositories` sorted by `updated` (these get touched constantly,
  crowding out real results). Confirmed 2026-09-17; do not add any `enhansome/*` repo, and don't
  trust "sort:updated" searches to surface genuine candidates without checking for this pattern.
- Stop re-running the raw `/dev/tcp ... smtp.mail.me.com:587` diagnostic every run: as of run 89 the
  agent proxy's own README confirms non-443 ports are categorically unsupported (see Blocked →
  SMTP egress), so this will never pass in this session type — it's an architectural fact, not a
  flaky/transient condition worth re-checking "every few runs" the way the GitHub cross-owner scope
  is. Treat priority-3 as permanently blocked pending a human switching the send mechanism to an
  HTTP email API (see Blocked section for detail) rather than re-testing SMTP reachability again.

- 2026-09-16 (run 87): Re-confirmed the standing blockers with fresh checks this run: `add_repo` (push)
  for janhq/awesome-local-ai still rejected with the same "cross-tier adds are not supported in v1"
  error — priority-1 bump and direct third-party PRs remain impossible, unchanged since run 43.
  `/dev/tcp` to smtp.mail.me.com:587 timed out (exit 124, SMTP_BLOCKED) and `curl` through the agent
  proxy to example.com returned a 403 CONNECT tunnel failure, while raw.githubusercontent.com remained
  reachable directly (200) — priority-3 email still impossible, nothing sent, Sent log still empty (0
  emails across 87 runs). For priority 2, ran the competitor-name code-search technique with "Rosebud"
  and "Mindsera" (no new directory, see Lessons) and a topic-based sweep (`topic:privacy-first awesome`)
  which surfaced one genuine new candidate, noxsentin/switz — recorded ready-to-paste submission copy in
  Backlog, blocked by the same session cross-owner restriction as every other third-party repo. Also
  found and ruled out a repo squatting on awesome-list conventions
  (Rplu2687/awesome-on-device-mobile-llms — actually a Windows .exe downloader page, not a list; see
  Lessons) — no prompt-injection attempt found in it, just deceptive packaging; did not download or run
  anything from it. Separately, caught and corrected a local git issue before it could cause harm: this
  session's working-tree checkout of `main` had a stale `origin/main` remote-tracking ref (pointing to
  an old pre-run-84 commit); running `git checkout -B main origin/main` without fetching first briefly
  reset the local working copy backward, which would have silently dropped runs 84-86 from a naive
  commit-on-top. Caught it via a line-count/section mismatch before committing, confirmed via
  `git fetch` that the real `origin/main` on GitHub was untouched and still at run 86's commit, reset
  the local checkout to match, and reapplied this run's edits on top of the correct base — no data was
  actually lost upstream, this was a local-checkout artifact only, but the same pre-fetch
  `checkout -B branch origin/branch` pattern should be avoided in future runs (always `git fetch`
  explicitly first, or use `git reset --hard origin/main` after fetching, before trusting a local
  checkout's line count or content). No PRs opened, no comments posted, no emails sent — 87th
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general web
  egress, SMTP egress), all three re-verified fresh this run with unchanged evidence. Not notifying:
  identical standing blocker already surfaced in prior runs' notifications (most recently the
  month-long-blocker status at run 82), and nothing material has changed since — one more Backlog
  candidate, one more ruled-out repo, and a self-caught local git scare (no actual data loss) are
  routine incremental progress, not a new development.

- meichthys/foss_note_apps uses a lowercase `readme.md` (not `README.md`), which is why raw fetch
  404'd on runs 91 and earlier — use `search_code` with `repo:` qualifier to find the real filename
  before concluding a repo is unreachable. Read in full this run: it's a desktop/self-hosted FOSS
  note-app feature-comparison matrix (Joplin, TriliumNext, QOwnNotes, etc.) that explicitly warns new
  entries need significant hands-on testing time — not a fit for a single mobile-only app, and not
  worth the effort/accuracy risk. Confirmed 2026-09-18; do not re-add.
- zetic-ai/awesome-on-device-ai-apps is not a listing directory: every "entry" is a full runnable app
  folder committed into its own monorepo (clone-and-run demos), not a link-to-your-app format — no
  submission path exists for an external app like MirrorNotes. Confirmed 2026-09-18; do not re-add.
- pedramnj/awesome-local-ai (distinct from the already-OPEN janhq/awesome-local-ai) is not a fit: its
  "Mobile & On-Device" section lists only generic chat-frontend/SDK tooling (PocketPal, LLMFarm, Maid,
  Layla, picoLLM), not consumer apps. Confirmed 2026-09-18 via raw README fetch; do not re-add unless
  it gains a consumer-apps section.

- 2026-09-17 (run 88): Re-confirmed all three standing env blockers with fresh live tests this run:
  session GitHub repo scope still shows only `lokii49/mirror` (per environment repo-scope banner,
  matches runs 84-87, no tool call burned to re-prove it), `/dev/tcp` to smtp.mail.me.com:587 timed
  out fresh (SMTP_BLOCKED, exit 124), and `curl` through the agent proxy to example.com returned a
  403 CONNECT tunnel failure while raw.githubusercontent.com stayed reachable (200) — priorities 1
  and 3 remain impossible, nothing sent, Sent log still empty (0 emails across 88 runs). For
  priority 2, tried `search_code` for untried competitor names ("Grid Diary", "Journly", "Momento")
  and `search_repositories` for "awesome journaling"/"awesome privacy iOS apps" sorted by most-
  recently-updated: no new curated-directory candidate — hits were individual competitor apps/
  clones/UI mockups, an unrelated `reflectionapp` import-tool utility repo, already-logged repos
  (akshaybharwani/data-not-collected-ios-apps), or a bot-generated `enhansome/*` mirror network (see
  Lessons, new finding this run). No PRs opened, no comments posted, no emails sent, no new Backlog
  entry — 88th consecutive run blocked purely on environment/session config, all three re-verified
  fresh with unchanged evidence. Not notifying: identical standing blocker already surfaced in prior
  runs' notifications (most recently the month-long-blocker status at run 82), and nothing material
  changed this run beyond one more ruled-out search pattern.

- 2026-09-17 (run 89): Re-confirmed priority-1/2 GitHub cross-owner block fresh (`add_repo` push
  for janhq/awesome-local-ai still rejected, identical "cross-tier adds are not supported in v1"
  error, unchanged since run 43). For priority-3, did NOT re-test raw SMTP reachability again —
  instead read `/root/.ccr/README.md` (the agent proxy's own docs) directly, which confirms
  non-443 ports are categorically, permanently unsupported through this proxy (not a flaky
  timeout) — see updated Blocked and Lessons entries. This is the first run with a documented root
  cause rather than an empirical "still times out" result, and it means priority-3 cannot be fixed
  by retrying; only a human switching to an HTTP-based email API (and allowlisting its domain) can
  unblock it. For priority 2, tried competitor-name code-search on "Grid Diary" (0 hits), "Journly"
  (7 hits, all individual apps/UI-mockups/unrelated backend repos, no directory), and
  "Momento"+journal (1476 hits, all noise/false-positive language matches) — no new candidate
  cleared the fit bar. No PRs opened, no comments posted, no emails sent, no new Backlog entry —
  89th consecutive run blocked purely on environment/session config. Notifying this run despite the
  standing-blocker pattern: the SMTP root-cause finding is new and changes the recommended fix
  (stop retrying SMTP; switch send mechanism), which the user should know given ~90 runs and 0
  outreach emails / 0 new PRs sent to date.

- 2026-09-17 (run 90): Re-confirmed the GitHub cross-owner block via this session's own environment
  repo-scope banner (still `lokii49/mirror` only, unchanged since run 43 — no tool call burned to
  re-prove it, per Lessons guidance). Did NOT re-test raw SMTP reachability (per run 89's finding
  that this is an architectural, permanent proxy limitation, not worth re-testing). For priority 2,
  tried four new discovery angles: competitor-name code-search on "Moodnotes" and "Exist.io" (only
  hits were the already-MERGED woop/awesome-quantified-self, mirrored/cloned copies of the same list,
  or unrelated noise — no new directory), `search_repositories` for `topic:ai-journal` (27 results,
  all individual competitor apps/toy projects, not curated directories — confirms
  reflectionapp/ai-journal-import-tools is a migration-tool repo, not a submission channel, matching
  the existing "not a fit" pattern for tool repos), and `"awesome" "on-device" ios in:readme`
  sorted by most-recently-updated (2774 results, dominated by noise/star-list repos and the
  `enhansome/*` bot network already flagged in Lessons — no genuine new candidate surfaced). No PRs
  opened, no comments posted, no emails sent, no new Backlog entry — 90th consecutive run blocked
  purely on environment/session config (GitHub cross-owner scope, SMTP egress), both re-verified or
  intentionally not re-tested per standing Lessons guidance. Not notifying: identical standing
  blocker already surfaced in prior runs' notifications (most recently run 89's SMTP root-cause
  finding), and nothing material changed this run beyond four more ruled-out search angles.

- 2026-09-17/18 (run 91): Re-confirmed the GitHub cross-owner block via this session's own environment
  repo-scope banner (still `lokii49/mirror` only, unchanged since run 43 — no tool call burned to
  re-prove it, per Lessons guidance). Did NOT re-test raw SMTP reachability (per run 89's finding that
  this is an architectural, permanent proxy limitation, not worth re-testing every run). For priority 2,
  tried several new discovery angles: competitor-name code-search on "Reflection.app" and "Stoic" (no
  directory hits, only false-positive word matches — see Lessons for the one useful non-hit,
  `IAmCoder/awesome-lucid-dreams`, found via a follow-up search and ruled out as scope-mismatched),
  `topic:mood-tracker awesome` and `topic:self-reflection awesome` (zero/irrelevant results),
  `awesome journal in:name` and `awesome note-taking in:name` name-searches (surfaced
  `santiagoxlopez/awesome-note-taking`, ruled out as an empty stub README — see Lessons; also
  re-surfaced `meichthys/foss_note_apps`, a promising FOSS-note-apps list with a "journaling" topic tag,
  but its README could not be fetched this run — both `README.md` and common branch names 404'd via raw
  fetch, worth a follow-up with the correct path in a future run rather than guessing). No new candidate
  cleared the fit bar this run; two new repos ruled out and recorded in Lessons so future runs skip
  them. No PRs opened, no comments posted, no emails sent, no new Backlog entry — 91st consecutive run
  blocked purely on environment/session config (GitHub cross-owner scope, SMTP egress), both
  unchanged. Not notifying: identical standing blocker already surfaced in prior runs' notifications
  (most recently run 89's SMTP root-cause finding), and nothing material changed this run beyond a
  couple more ruled-out search angles.

- 2026-09-18 (run 92): Re-confirmed the GitHub cross-owner block with a fresh live call this run
  (`add_repo` push for janhq/awesome-local-ai still rejected, identical "cross-tier adds are not
  supported in v1" error, unchanged since run 43). Did not re-test SMTP (architectural, per run 89).
  For priority 2: solved the run-91 mystery on `meichthys/foss_note_apps` — its comparison file is
  lowercase `readme.md`, not `README.md`, which is why raw-fetch 404'd twice; found via `search_code`
  instead of guessing paths. Read it in full: it's a large multi-column FOSS-note-app *feature
  comparison matrix* (Joplin, TriliumNext, QOwnNotes, SilverBullet, Nextcloud Notes, etc.), explicitly
  scoped to desktop/self-hosted apps with plugin ecosystems, and the README itself warns that adding a
  new column "will likely need... significant [testing] time" — a poor fit for a single mobile-only
  iOS app with no plugin system, and disproportionate effort for what this loop can respons‑ibly claim
  without hands-on testing. Ruled out, not added to Backlog (see Lessons). Also checked two repos
  surfaced by a `topic:on-device-ai awesome` sweep: `zetic-ai/awesome-on-device-ai-apps` is not a
  listing directory at all — every "entry" is a full runnable app folder inside its own monorepo
  (clone-and-run, not a link-to-your-app format), so there's no submission path that fits; and
  `pedramnj/awesome-local-ai`'s "Mobile & On-Device" section (distinct from the already-OPEN
  janhq/awesome-local-ai) lists only generic chat-frontend/SDK tooling (PocketPal, LLMFarm, Maid,
  Layla, picoLLM), not consumer apps — same category mismatch as other dev-tooling lists already ruled
  out. No new candidate cleared the fit bar this run; three repos investigated and ruled out, recorded
  in Lessons. No PRs opened, no comments posted, no emails sent, no new Backlog entry — 92nd
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, SMTP
  egress), both re-verified/unchanged. Not notifying: identical standing blocker already surfaced in
  prior runs' notifications (most recently run 89's SMTP root-cause finding), and nothing material
  changed this run beyond resolving one loose end and ruling out three more candidates.

- 2026-09-18 (run 93): Started with a stale local checkout (this session's working tree still showed
  the Log ending at run 90 when this run began), so the Backlog/Log edits below were drafted against
  that older content; before committing, `git fetch origin main` + `git log`/`git show` revealed
  origin/main had already advanced to run 92 (two runs, 91 and 92, completed minutes apart earlier
  today by other concurrent sessions) with HEAD/working tree silently updated to match mid-session.
  Recovered by diffing the real run-91/92 entries against this run's draft before committing:
  confirmed no duplicate work (neither run touched rodrgds/open-apps), moved this run's Log entry to
  the correct position/number after run 92 instead of leaving it wedged before run 91 under a reused
  "run 91" label. Re-confirmed the GitHub cross-owner block with a fresh tool call this run
  (`add_repo` push for janhq/awesome-local-ai → same "cross-tier adds are not supported in v1" error)
  — priority-1 bump and any direct third-party PR/comment remain impossible. Did NOT re-test raw SMTP
  reachability (per run 89's finding that the proxy's non-443-port block is architectural/permanent —
  Sent log remains untouched, 0 emails across 93 runs since 2026-08-15). For priority 2, WebSearched
  fresh angles ("on-device AI iOS privacy" awesome-lists, AGPL journaling-app directories) and found
  rodrgds/open-apps, a genuinely new candidate not previously logged (checked against runs 91/92's
  own new ruled-out list too). Verified fit and checked for prompt injection via WebFetch on its raw
  README + CONTRIBUTING.md (github.com content domain — reachable even though general web egress is
  not): real inclusion criteria with no star/commit gate, MirrorNotes qualifies (shipped app,
  AGPL-3.0, public repo, documented), no injection content found. Submission is via a web form
  (openappscout.com/submit, blocked from WebFetch preview in this env — non-github domain) or a
  manual PR to the upstream repo (blocked from this session same as every other third-party repo).
  Added full ready-to-paste details to Backlog for a human to action via the web form (simplest path
  — just needs the GitHub URL pasted in). No PRs opened, no comments posted, no emails sent — 93rd
  consecutive run blocked purely on environment/session config, both blockers re-verified or
  intentionally not re-tested per standing Lessons guidance. Not notifying: identical standing
  blocker already surfaced in prior runs' notifications (most recently run 82's month-mark flag), and
  nothing material changed this run beyond one new Backlog candidate and the stale-checkout recovery
  (itself now recorded in Lessons so a future run recognizes the pattern faster).

- Psyhackological/AAA ("Awesome Android Alternatives", 274 apps, has a "Diary" section and even an
  "AI" section mentioning on-device AI) is not a fit despite looking promising: its stated Rules
  require every entry be free on F-Droid/Google Play and installable on Android — it's exclusively
  an Android-app directory. MirrorNotes is iOS-only (no Android build), so it doesn't qualify under
  the list's own inclusion criteria regardless of topical fit. Confirmed 2026-09-18 via raw README
  fetch; do not re-add unless MirrorNotes ships an Android version.
- alvinreal/awesome-opensource-ai (has an "Edge / On-device AI" section, surfaced by an "on-device
  AI" + journal code search) is not a fit: its own README states it's "for people building with
  AI" — models, libraries, inference engines, RAG, MLOps — no section for shipped consumer apps.
  Confirmed 2026-09-18 via raw README fetch; do not re-add.
- topic:journaling-app search (new angle this run) surfaced only individual competitor/hobby apps
  (journiv-app, memex, journedge, LockIn, inkwell, journaler, nebline, etc.) via GitHub's topic
  index, not curated directories — GitHub topic pages remain a discovery dead-end for finding new
  awesome-lists (consistent with the 2026-08-23 finding for github.com/topics/journaling-app).
  Confirmed 2026-09-18; do not re-try bare topic:journaling-app / topic:diary-app / "awesome diary
  in:name" again.

- 2026-09-18 (run 94): Re-confirmed the GitHub cross-owner block via this session's own environment
  repo-scope banner (still `lokii49/mirror` only, unchanged since run 43 — no tool call burned to
  re-prove it). Did NOT re-test raw SMTP reachability (per run 89's finding that this is an
  architectural, permanent proxy limitation). For priority 2, tried three new discovery angles:
  `awesome diary in:name` (only toy/personal repos, no directories), `topic:journaling-app` (only
  individual competitor apps via GitHub's topic index, not curated lists — see Lessons), and an
  "on-device AI" + journal code search across READMEs, which surfaced two candidates with real
  matching sections — both investigated and ruled out: Psyhackological/AAA ("Awesome Android
  Alternatives", has a Diary section) requires every entry be Android/F-Droid-installable, and
  MirrorNotes is iOS-only; alvinreal/awesome-opensource-ai's "Edge / On-device AI" section is
  scoped to dev tooling/models, not shipped consumer apps (see Lessons for both). No new candidate
  cleared the fit bar this run; no PRs opened, no comments posted, no emails sent, no new Backlog
  entry — 94th consecutive run blocked purely on environment/session config (GitHub cross-owner
  scope, SMTP egress), both unchanged. Not notifying: identical standing blocker already surfaced
  in prior runs' notifications (most recently run 89's SMTP root-cause finding), and nothing
  material changed this run beyond two more ruled-out candidates.

- 2026-09-18 (run 95): Re-confirmed the GitHub cross-owner block via this session's own
  environment repo-scope banner (still `lokii49/mirror` only, unchanged since run 43 — no tool
  call burned to re-prove it). Did NOT re-test raw SMTP reachability (per run 89's finding that
  this is an architectural, permanent proxy limitation; this session's own environment
  description still confirms the same proxy scope). For priority 2, tried three new discovery
  angles: WebSearch for digital-minimalism/slow-tech app directories (no curated list found,
  only individual competitor apps and AlternativeTo pages already known to require an aged
  account), WebSearch for on-device-AI consumer-app directories (surfaced only AI-agent/
  tool/framework lists, no new consumer-app-focused directory), and a GitHub code search for
  `"awesome" "iOS" "journal"` across READMEs (all hits were noise, already-logged repos, or
  unrelated false-positive word matches — no new candidate). Also did significant state-file
  housekeeping this run: the Log section had grown to ~2,000 lines (file over 260KB total,
  exceeding this environment's single-read size limit, so a future run could no longer read
  the whole file in one pass as this file's own header instructs) and had accumulated real
  structural drift — entries for runs 84-89 and 91-94 had been misplaced into the Lessons
  section by earlier concurrent-session races instead of appearing in Log. Recovered full
  chronological order for all 94 prior entries programmatically (verified by date/run number,
  no content altered or deleted), moved the misplaced entries back into Log, and archived all
  but the most recent 20 runs into `.claude/marketing-loop-log-archive.md` (linked from the Log
  section header) so the live state file stays readable in a single pass going forward. No PRs
  opened, no comments posted, no emails sent — 95th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, SMTP egress), both unchanged. Not
  notifying: identical standing blocker already surfaced in prior runs' notifications; the
  file-structure fix is maintenance, not a change in the underlying blocker.

- 2026-09-19 (run 96): Re-confirmed the GitHub cross-owner block, this time with a live probe
  rather than just reading the scope banner: add_repo(XargsUK/awesome-adhd, access: push) still
  rejected with "cross-tier adds are not supported in v1" (session locked to lokii49-owned repos).
  That repo turned out to be a known duplicate already in Backlog (line 230), so no PR would have
  been possible anyway — but the block itself is now freshly confirmed rather than assumed. Did NOT
  re-test raw SMTP reachability (per run 89's permanent-architectural-limit finding, still
  unchanged). For priority 2, tried three new discovery angles: code search for "Daylio"/"Moodnotes"
  mentions in README.md (only turned up mirrors/clones of the already-MERGED
  woop/awesome-quantified-self), code search for "Journalytic"/"Clarity Journal"/"Diaro" (zero
  hits), and a repo search for privacy-first iOS app directories which surfaced the enhansome/*
  GitHub org — investigated and ruled out as a class: it's 2,300+ near-identical
  enhansome-<topic> repos (e.g. enhansome-macos-apps, enhansome-privacy, enhansome-ncnn,
  enhansome-pascal), all created within the same few hours on 2026-08-12, 0-3 stars each, covering
  every conceivable topic — pattern strongly indicates an automated content-farm generator, not
  human-curated awesome-lists with real maintainers/CONTRIBUTING processes, so not a legitimate
  outreach target (see Lessons). No new candidate cleared the fit bar this run; no PRs opened, no
  comments posted, no emails sent — 96th consecutive run blocked purely on environment/session
  config (GitHub cross-owner scope, SMTP egress), both unchanged. Not notifying: identical standing
  blocker already surfaced and explained in prior runs' notifications, and nothing material changed
  this run beyond a live re-confirmation and one ruled-out repo family.

- 2026-09-19 (run 97): Re-confirmed the GitHub cross-owner block via a live `add_repo` probe against
  a new target (pluja/awesome-privacy, access: push) rather than just reading the scope banner —
  still rejected with "cross-tier adds are not supported in v1" (session locked to lokii49-owned
  repos). Checked the agent proxy's own status endpoint directly for the first time
  (`$HTTPS_PROXY/__agentproxy/status`) instead of re-testing `/dev/tcp`: confirms the noProxy
  allowlist is unchanged (github.com/api.github.com, package registries, anthropic.com only — no
  smtp.mail.me.com or any mail host), consistent with run 89's finding that SMTP on port 587 is an
  architectural proxy limitation, not a retryable outage — did not attempt a raw SMTP connect test
  again. For priority 2, tried three new discovery angles: GitHub code search for "Rosebud"/
  "RoseBudThorn" journal-app mentions in READMEs (only individual apps/toy projects, no curated
  directory), "Mindsera" mentions (same), and `"privacy-first" journal awesome filename:README.md`
  (surfaced only already-logged/ruled-out lists — jaywcjlove/awesome-mac, jyguyomarch/
  awesome-productivity — plus dev-tooling lists with no consumer-app fit, e.g. ripienaar/free-for-dev,
  hemanth/awesome-pwa). No new candidate cleared the fit bar; no PRs opened, no comments posted, no
  emails sent — 97th consecutive run blocked purely on environment/session config (GitHub cross-owner
  scope, SMTP egress), both freshly reconfirmed via live checks this run rather than assumed. Not
  notifying: identical standing blocker already surfaced and explained in prior runs' notifications,
  nothing material changed.

- 2026-09-19 (run 98): Re-confirmed both standing blockers with fresh live probes rather than
  assuming: `add_repo(janhq/awesome-local-ai, access: push)` still rejected with "cross-tier adds
  are not supported in v1"; `pull_request_read` (method get) on tehtbl/awesome-note-taking#89
  (one of our own OPEN PRs) also rejected with "repository ... is not configured for this session"
  — confirms even read-only PR-status checks on third-party repos are out of reach, not just writes,
  so bump/stale-check on priority 1 remains impossible from this session. Checked
  `$HTTPS_PROXY/__agentproxy/status` again: noProxy allowlist unchanged, still no mail host — SMTP
  outreach (priority 3) remains architecturally blocked, consistent with run 89/97. For priority 2,
  tried GitHub code search for "Presently"/"Reflectary" journal mentions (zero hits) and `"on-device"
  "journal" awesome filename:README.md` (105 hits, all noise/already-ruled-out lists or Flutter/Mac-
  scoped lists already excluded — jaywcjlove/awesome-mac, Solido/awesome-flutter). One incidental
  observation while reading tehtbl/awesome-note-taking's current README via search snippet: a
  competing app "DailyVox" is now listed there with a very MirrorNotes-like pitch ("on-device
  transcription, mood tracking, Digital Twin... 100% offline, optional iCloud sync") — not
  actionable (can't compare further without repo access), just logged for awareness. No new
  candidate cleared the fit bar; no PRs opened, no comments posted, no emails sent — 98th
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, SMTP
  egress), both freshly reconfirmed via live checks this run. Not notifying: identical standing
  blocker already surfaced and explained in prior runs' notifications, nothing material changed.

- 2026-09-20 (run 99): Re-confirmed the GitHub cross-owner block with a fresh live probe:
  `pull_request_read` (method get) on tehtbl/awesome-note-taking#89 rejected with "repository ...
  is not configured for this session. Allowed repositories: lokii49/mirror" — priority-1 bump
  remains impossible. Did NOT re-test raw SMTP reachability (per run 89's permanent-architectural-
  limit finding, still unchanged; this environment's own proxy allowlist description in this
  session matches prior runs exactly). For priority 2, tried three discovery angles: GitHub code
  search for `"Day One" alternative journal awesome filename:README.md` (90 hits, all either
  already-logged/ruled-out lists — jaywcjlove/awesome-mac — or unrelated noise matching "day one"/
  "journal" as incidental words, e.g. Lisp/agent-framework READMEs); a WebSearch for "awesome"
  github journaling/privacy/on-device-AI lists (surfaced only individual competitor apps and
  GitHub topic pages, both already-established discovery dead ends, no curated directory); and a
  `search_repositories` query combining journal/diary/privacy-first keywords with a recent
  `created:>2026-08-01` filter sorted by `updated` (returned pure noise — unrelated game-download
  repos, portfolio sites, and `enhansome/*` bot-network entries already flagged in Lessons — the
  `sort:updated` + broad keyword-OR combination surfaces recently-touched junk repos, not curated
  lists; do not repeat this exact query shape). No new candidate cleared the fit bar this run. No
  PRs opened, no comments posted, no emails sent — 99th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, SMTP egress), both reconfirmed unchanged.
  Not notifying: identical standing blocker already surfaced and explained in prior runs'
  notifications (most recently run 89's SMTP root-cause finding and run 82's month-mark flag),
  and nothing material changed this run beyond one more ruled-out search-query shape.

## Blocked

### [env] GitHub write access restricted to lokii49-owned repos only (this session)
`add_repo` refuses cross-owner adds ("cross-tier adds are not supported in v1") once the session
already holds `lokii49/mirror`. Forks of the four target repos exist under `lokii49/*` and CAN be
added/cloned, but `add_issue_comment`, `pull_request_read`, `create_pull_request`, etc. against the
upstream repos (janhq/awesome-local-ai, pluja/awesome-privacy, dreamingechoes/awesome-mental-health,
tehtbl/awesome-note-taking) are all rejected with "repository ... is not configured for this
session" even though the fork is in scope. This blocks BOTH bumping existing PRs (priority 1) and
opening new PRs to third-party repos (priority 2), for every run using this session/environment
tier. Confirmed 2026-08-15. Needs a session/environment where the initial repo source is one of
these target repos (or an environment with broader cross-owner GitHub scope), OR a human to run
the PR bump/creation manually using the ready copy this loop prepares.

### [env] General web egress blocked (WebFetch + local network)
WebFetch to non-github.com content domains (tried opensourcealternative.to, journaling.guide)
returns `EGRESS_BLOCKED`. Local `curl` through the environment's HTTPS proxy also returns 403 for
arbitrary domains (example.com, journaling.guide) — only github.com/api.github.com and a short
noProxy allowlist (npm, pypi, jsr, crates, golang proxy, anthropic.com) go through. WebSearch still
works (returns real snippets) so light research is possible, but can't verify exact submission-form
fields on a target site. Confirmed 2026-08-15.

### [env] SMTP egress unreachable (smtp.mail.me.com:587)
`/dev/tcp` connect to smtp.mail.me.com:587 times out from this environment — same network policy
as above, ports/hosts beyond the allowlist are blocked. This makes priority-3 outreach email
impossible from this session/environment as currently configured. Confirmed 2026-08-15. Did NOT
attempt to fabricate a send — no email was sent, nothing added to Sent log.

**Root cause confirmed 2026-09-17 (run 89), and this is now a PERMANENT/architectural limit, not a
retryable timeout**: `/root/.ccr/README.md` (the agent proxy's own documentation) explicitly lists
"non-443 HTTPS ports, raw-TCP databases" under "Not supported through the proxy (report, do not
work around)". SMTP submission on port 587 falls squarely in that category — this proxy will never
carry it, in this run or any future one, regardless of org policy changes. Re-testing
`/dev/tcp ... 587` every run is no longer informative and should stop (see Lessons). The only way
to get automated outreach email working from this environment is to stop using raw SMTP entirely
and switch to an HTTP-based transactional email API (e.g. a provider with a REST endpoint on port
443, such as Postmark/Resend/SendGrid) — which would still require a human to (a) set up an account
and API key for hello@mirrornotes.org, and (b) confirm that provider's API domain is on this
session's egress allowlist (currently only github.com/api.github.com plus a short package-registry
noProxy list pass through). Neither is something this loop can do autonomously.

## Lessons
- Before assuming a target action is achievable, sanity-check network reachability early
  (`curl -sS -o /dev/null -w "%{http_code}" <domain>`, `/dev/tcp` for SMTP) — this environment's
  network policy is scoped tightly to coding-related domains and does not (currently) allow the
  general web browsing + SMTP this routine's instructions assume.
- Session repo scope only allows adding repos owned by the same account as the first-added repo
  (`lokii49`). Forks under `lokii49/*` can be added even when the upstream can't — useful for
  reading/staging changes, but not for commenting on or opening PRs against the upstream, since
  those operations are scoped to the base repo (owner not in session).
- Don't re-run the same blocked diagnostic every single run once confirmed — check whether the
  environment's network policy or session config has changed (e.g. try once every few runs) rather
  than burning an action on it every time, but log every run whether primary actions were possible.
- Multiple runs of this loop can execute close together (minutes apart) in different concurrent
  sessions, each starting from its own checkout. A session's working tree can also get silently
  resynced to a newer origin/main mid-session (observed run 93: local file still showed the Log
  ending at run 90 partway through the run, but `git log`/`git show HEAD:...` moments later showed
  HEAD already at run 92's commit with no explicit `git pull` run). Always `git fetch origin main`
  and diff/inspect the real current HEAD content right before committing — not just at the start of
  the run — and re-derive the next run number and Log insertion point from that fresh fetch, not from
  whatever was read earlier in the session. Never trust an early-session read of this file's Log
  section as still being the tip by the time you're ready to commit.
- The account has a pre-existing fork `lokii49/awesome-ios` (of vsouza/awesome-ios). Do NOT use it —
  it's a curated list of iOS *developer* resources (SDKs, libraries, analytics/tooling), not an
  app/consumer directory, so MirrorNotes doesn't fit anywhere in it. Confirmed 2026-08-17 by cloning
  and reading the README's table of contents (Analytics, ARKit, Authentication, etc — no Apps section).
- Not every "awesome-X" search hit is worth adding to Backlog. Check actual fit before adding: repo
  activity/commit count, whether it's about the right underlying tech (e.g. Gemini ≠ Gemma — cloud
  API vs on-device open-weights model, a real mismatch despite both being Google), and any explicit
  stated selection criteria (e.g. console.dev requires the primary user to be a developer;
  awesome-selfhosted requires self-hostable server software). A rejected/spam-flagged submission
  costs more than skipping a weak candidate for a run.
- Check whether a candidate repo is archived before adding it to Backlog, not just star count —
  areknawo/awesome-productivity-software (43 stars, has a "Notes" section) looked like a fit but was
  archived by its owner on 2026-03-12 (read-only, no new PRs possible). Confirmed 2026-08-20; do not
  re-add.
- Some directories gate submissions on the *submitting repo's* own popularity, not just topical
  fit: tortuvshin/open-apps requires ≥50 stars and ≥50 lifetime commits on the source repo before
  it'll list an app. lokii49/mirror has 0 stars, so it doesn't qualify yet — skip this target until
  the repo has enough stars, don't re-add it to Backlog until then. Confirmed 2026-08-19.
- privacyguides.org's Notebooks recommendation page requires "any cloud sync functionality must be
  E2EE" as a hard stated criterion. MirrorNotes uses CloudKit sync, but this loop cannot confirm from
  this environment whether that sync is end-to-end encrypted in the sense Privacy Guides means — do
  not submit or claim E2EE there until a human confirms the actual encryption implementation matches
  the criterion. Confirmed 2026-08-20.
- madimalo/awesome-swiftui is not a fit: 0 stars, 1 fork, and its ~12 entries are SwiftUI clone/demo
  projects (e.g. "Reminders Clone", social-media clients) rather than shipped consumer apps — wrong
  category for MirrorNotes even though it nominally has no sections to place things in. Confirmed
  2026-08-20; do not re-add.
- yangwao/awesome-offline is not a fit: it's a developer-resources list (articles, talks, libraries,
  podcasts about the offline-first movement), not a directory of consumer apps/products — no section
  to place MirrorNotes in. Confirmed 2026-08-21 via WebFetch on the raw README; do not re-add.
- CRK1918/awesome-privacy-list is a fork of pluja/awesome-privacy (confirmed via WebFetch, "forked
  from" attribution present, 0 stars). Submitting there would be redundant with the already-OPEN
  pluja/awesome-privacy#879 PR — do not add. Confirmed 2026-08-21.
- nicknickel/awesome-notes is a weak fit: explicitly desktop-focused ("work on a desktop, though many
  do have mobile versions"), no journaling/mobile section, only 6 commits total (minimal
  maintenance). Confirmed 2026-08-21; do not re-add unless it gains a mobile/journaling section.
- nikivdev/privacy-respecting (2k stars, active) is not a fit: no note-taking/journaling/diary/
  productivity section exists at all — only Search Engines, Social Networks, Messengers, Cloud
  Storage, VPN, Hosting, Email, OS, Browsers, Video Sharing, AI Assistants, Maps. Confirmed
  2026-08-23 via WebFetch; do not re-add unless it gains a relevant section. Also: GitHub topic pages
  (e.g. github.com/topics/journaling-app) only surface individual apps, not curated directories —
  not a useful discovery channel for finding new awesome-lists.
- megan201296/awesome-mental-health is not a fit: only Articles/Books/Talks sections (no apps
  section at all), no CONTRIBUTING.md or stated submission format beyond "submit a PR", and appears
  inactive (12 commits total). Confirmed 2026-08-24 via WebFetch; do not re-add.
- jiejuefuyou/awesome-indie-ios (0 stars) is not a fit: it's a resource list for solo devs *building*
  iOS apps (build tools, monetization, marketing links), not a directory of consumer apps. Its one
  section that could plausibly hold a shipped app — "Open Source Reference Portfolios" — only
  contains the maintainer's own toy demo repos (autoapp-hello, autoapp-days-until, etc.) used to
  teach build patterns to other devs, not a genuine third-party-app submission channel. Confirmed
  2026-08-27 via WebFetch on the raw README; do not re-add.
- stevelaskaridis/awesome-mobile-llm is not a fit despite the on-device-AI angle: it's a
  developer/research resources list (papers, frameworks, benchmarks, leaderboards on mobile LLM
  deployment) with no section for consumer apps — same category of mismatch as other dev-resource
  lists already ruled out. Confirmed 2026-08-24 via WebFetch; do not re-add.
- frechdi/awesome-self-hosted-ai is not a fit: exclusively server-side LLM infra (inference engines,
  RAG, VPS/GPU hosting) — no section for consumer mobile apps at all. Confirmed 2026-08-25 via
  WebFetch; do not re-add.
- DasterProkio/awesome-ai-companion (525 stars, active) is not a fit: scoped specifically to
  long-term AI-companion-persona tools (memory/identity/emotion state, virtual phones, embodiment) —
  even its closest section ("Shared Activities & Media" / journaling-together-with-a-companion)
  assumes a companion-relationship feature MirrorNotes doesn't have. Confirmed 2026-08-25 via
  WebFetch; do not re-add unless MirrorNotes gains a companion-persona feature.
- mrseth01/awesome-adhd (322 stars, active, distinct from XargsUK/awesome-adhd already in Backlog)
  is not a fit despite being active: its "Software Tools" section is entirely habit-formation/
  self-control/focus apps (Beeminder, SelfControl, Forest, Habitica, Freedom) with no journaling or
  mood-tracking precedent — a real category mismatch, unlike dicktracey909/awesome-adhd-tools'
  "Emotional Regulation" section which already lists Daylio. Entries there are also bare
  `[Name](url)` links with no description field in current practice (CONTRIBUTING.md nominally asks
  for one, but no existing entry has one) — confirmed via WebFetch on README + CONTRIBUTING.md
  2026-08-26; do not re-add unless the section's scope changes.
- motoon-eg/open-source-ios-apps-1 is a generated mirror/fork of dkhamsing/open-source-ios-apps
  (README explicitly points back to the dkhamsing repo and states it's auto-generated from
  contents.json, "please do not update" the README directly) — MirrorNotes is already MERGED into
  the upstream dkhamsing/open-source-ios-apps#2274, so submitting here would be redundant. Confirmed
  2026-08-29 via WebFetch; do not re-add.
- primaprashant/awesome-voice-typing is not a fit despite the voice-input angle: its scope is
  explicitly "open-source apps, keyboards, menu bar utilities, and CLI tools" for speech-to-text/
  voice typing specifically (transcription engines, dictation keyboards), not journaling apps that
  happen to accept voice as one input method. MirrorNotes doesn't belong in a voice-typing-tool
  directory the way it belongs in note-taking/journaling/privacy lists. Confirmed 2026-08-29 via
  WebFetch; do not re-add.

- piyushkumar-prog/Privacy-friendly-apps-and-services-for-iOS is not a fit: only 4 categories (Best
  Browsers, Best Search Engines, Best Email Providers, Best Instant Messaging Apps), no notes/
  journaling section exists. Confirmed 2026-08-30 via WebFetch; do not re-add unless it gains a
  relevant section.
- hades217/awesome-ai is not a fit: 20 categories, heavily developer-centric (models, coding, agents,
  RAG, inference); consumer apps (Notion AI, Granola, Reclaim.ai) appear scattered across categories
  with no dedicated journaling/notes/personal-productivity grouping to place MirrorNotes in. Confirmed
  2026-08-30 via WebFetch; do not re-add.
- knowfox/awesome-pkm is not a fit: only Approaches/Lists/Articles/Tools sections, and Tools contains
  just one entry (the maintainer's own Knowfox tool) — no consumer mobile/iOS-apps section exists.
  Confirmed 2026-08-30 via WebFetch; do not re-add unless it gains a relevant section.
- ThetaApps/ios-app-opensource ("Collaborative List of Open-Source iOS Apps", 22 stars) is a fork of
  dkhamsing/open-source-ios-apps (confirmed via WebFetch, "forked from" banner present). MirrorNotes
  is already MERGED into the upstream (#2274) — submitting to the fork would be redundant, same
  pattern as motoon-eg/open-source-ios-apps-1. Confirmed 2026-08-31; do not re-add.
- rafska/awesome-local-llm is not a fit: sections are Inference platforms/Inference engines/User
  Interfaces/LLMs/Tools/Hardware/Tutorials/Communities — infra and dev-tooling only, no section for
  consumer mobile/iOS apps. Confirmed 2026-08-31 via WebFetch on the raw README; do not re-add unless
  it gains a consumer-apps section.
- matteocrippa/awesome-swift is not a fit: it's a libraries/frameworks list; its only "apps" content
  is a pointer to dkhamsing/open-source-ios-apps under "Other Awesome Lists" (already MERGED at
  #2274) — no consumer-app section of its own. Confirmed 2026-09-01 via WebFetch on the raw README;
  do not re-add.
- eudk/awesome-ai-tools is not a fit: no journaling, diary, privacy, or on-device-AI section — it's a
  large list of mostly web/SaaS AI tools (productivity tools, Chrome extensions, AI hardware).
- IAmCoder/awesome-lucid-dreams is not a fit despite a real "Apps"/"Open-Source Projects" section
  listing several dream-journal apps (Lucid-Dash, DreamWell, Awoken, etc.): its scope is specifically
  lucid-dreaming/dream-journaling, not general daily journaling — MirrorNotes doesn't fit the list's
  actual theme even though the word "journal" appears throughout. Confirmed 2026-09-17 via raw README
  fetch; do not re-add unless MirrorNotes gains dream-specific features.
- santiagoxlopez/awesome-note-taking (12 stars, distinct from tehtbl/awesome-note-taking already OPEN)
  is not usable: its `readme.md` (lowercase filename — `README.md` 404s) is effectively a stub, just
  the title "# Awesome Note-taking" with no sections or entries yet. Confirmed 2026-09-17 via raw
  fetch; re-check in a future run only if the repo gains real content.
- meichthys/foss_note_apps (62 stars, "journaling" topic tag) could not be fetched this run — both
  `README.md` and `master`/`main` branch raw paths 404'd; the repo may use a different default branch
  or filename. Worth a retry with the correct path/branch in a future run rather than re-adding to
  Backlog blind.
  Confirmed 2026-09-02 via WebFetch on the raw README; do not re-add unless it gains a relevant
  section.
- Data-Sapien/awesome-on-device-mobile-llms is not a fit despite promising topics (privacy-first,
  ios-ai, mobile-ai): it's a vendor (DataSapien) technical resource on runtimes/SDKs/benchmarks, no
  section for consumer-facing apps, no CONTRIBUTING.md — only a GitHub Discussions "Production use
  cases" template for sharing implementation learnings, not an app-listing channel. Confirmed
  2026-09-03 via WebFetch on the raw README; do not re-add unless it gains a real apps section.
- john-rocky/awesome-core-ai is not a fit: CONTRIBUTING.md explicitly requires entries be "specifically
  about Apple's Core AI framework / `.aimodel`" — MirrorNotes runs Gemma 3 1B (not confirmed to be via
  Apple's own Core AI/Foundation Models framework specifically), so it doesn't clearly satisfy that
  scope requirement even though a "Running models in your app" section exists. Confirmed 2026-09-03 via
  WebFetch; do not re-add unless MirrorNotes' on-device stack is confirmed to use Apple's Core AI
  framework specifically.
- awesome.ecosyste.ms (meta-directory of awesome lists) is not github.com, so WebFetch returns
  EGRESS_BLOCKED same as every other non-github content domain — not usable for discovery from this
  environment. Confirmed 2026-09-03.
- jcanfield/awesome-digital-wellbeing is not a fit: its "Apps" section has exactly one entry (Google's
  own Android screen-time-limiting system app), and the list's whole theme is reducing/limiting screen
  use, not journaling or mood tracking. No journaling/diary/mood section exists. Confirmed 2026-09-06
  via WebFetch on the raw README; do not re-add unless it gains a relevant section.
- tdi/awesome-private-ai is not a fit despite mentioning Gemma models: it's entirely server/self-hosted
  AI infrastructure (inference runtimes, model serving, vector DBs, VS Code plugins) with no section
  for consumer-facing mobile/iOS apps that run AI on-device. Confirmed 2026-09-06 via WebFetch on the
  raw README; do not re-add unless it gains a consumer-apps section.
- humanetech-community/awesome-humane-tech is a good topical fit (privacy/mindfulness/wellbeing) but
  archived by its owner — no new PRs possible. Confirmed 2026-09-07; do not re-add.
- piotrkulpinski/open-source-alternatives is the GitHub-side data repo backing opensourcealternative.to
  (already logged in Backlog as a web-form candidate) — same project family, do not add separately.
  Confirmed 2026-09-07.
- mahseema/awesome-saas-directories and theshubh77/awesome-saas-directories are lists of *directories to
  submit a product to*, not app-entry lists themselves — no section where a shipped app's own entry
  would go. Confirmed 2026-09-07; do not re-add.
- anondotli/awesome-privacy-tools's own "Mobile Privacy Tools" section is explicitly Android-only
  (F-Droid, Orbot, NetGuard, etc.) — not a fit for MirrorNotes; used its "Private Cloud Storage, Notes,
  and Collaboration" section instead (added to Backlog). Confirmed 2026-09-07.
- Repeat searches this run ("awesome bullet journal", "awesome self improvement", "awesome digital
  wellbeing", "awesome indie apps showcase", "awesome ADHD apps", "awesome ethical software", "awesome
  offline first apps", "awesome degoogle", "awesome no account apps", "awesome edge ai apps",
  oppoverbakke/awesome-gdpr, asmaier/awesome-gdpr-services, johnjago/awesome-free-software) surfaced only
  already-logged lists, legal/regulatory resource lists with no consumer-app section, or non-directory
  repos. Confirmed 2026-09-07; do not re-try these exact angles again.
- umitkacar/awesome-mobile-ai and ivanvorobei/awesome-ios are not fits: both are developer-resource
  lists (frameworks/libraries/UI components/deployment tooling) with no section for consumer-facing
  shipped apps. Confirmed 2026-09-08 via WebFetch on raw READMEs; do not re-add.
- Searches this run ("journaling/diary iOS privacy directory", "on-device AI iOS apps awesome list",
  "self-reflection/gratitude/personal-growth privacy apps directory", "AGPL/copyleft apps awesome
  list") surfaced only already-logged lists, GitHub topic pages (not curated directories), individual
  competitor apps (not submission channels), or dev-resource lists with no consumer-app section.
  Confirmed 2026-09-08; do not re-try these exact angles again.
- raullenchai/awesome-mlx has a real "Apps & Demos" section with consumer iOS apps, but its
  CONTRIBUTING requires entries be "specifically related to MLX" — MirrorNotes runs Gemma 3 1B via
  llama.cpp, not Apple's MLX framework, so submitting there would be inaccurate. Not a fit unless the
  inference stack changes. Confirmed 2026-09-09; do not re-add.
- cognitivetech/CBT-Cognitive-Behavioral-Therapy (papers/training materials only, no consumer-app
  section) and heartly/awesome-writing-tools (fork, developer/writer tooling only, no journaling/
  consumer-app section) are not fits. Confirmed 2026-09-09; do not re-add.
- Search angles tried this run with no new candidate surfaced (only dev-tool/library lists, blog
  roundups, or individual apps rather than curated awesome-lists with a consumer-app section): awesome
  habit tracker, awesome private journaling, awesome tech/digital minimalism, awesome apple
  intelligence, awesome swift ai/ML, awesome CBT, awesome mood tracker, awesome self-hosted
  alternatives (journaling), awesome-mlx, awesome-llama.cpp. Confirmed 2026-09-09; do not re-try these
  exact angles again.
- ljinkai/awesome-indie-maker is not a fit: its only project-showcase section ("Existing projects") is
  explicitly "for inspiration" and lists only famous examples (NomadList, RemoteOk, ProductHunt), not a
  submission channel for indie apps generally; no CONTRIBUTING guidance found either. Contains one
  motivational turn of phrase under "Automate" ("Make this business run itself with just robots...")
  that is not a prompt-injection attempt, just florid copy — noted, not acted on. Confirmed 2026-09-10
  via WebFetch on the raw README; do not re-add.
- Search angles tried this run with no new candidate surfaced (only already-logged lists, individual
  competitor diary apps, or tool-lists for indie makers rather than product-showcase directories):
  awesome burnout/self-therapy/resilience, awesome expressive writing/life logging privacy, awesome
  on-device iOS AI directory, awesome open-source diary/journal app no-account/local-first, awesome
  indie makers privacy apps directory. Confirmed 2026-09-10; do not re-try these exact angles again.
- agi-templar/Awesome-Small-Language-Model and slashml/awesome-small-language-models are not fits:
  both are SLM model/weights/dev-tooling lists — their "Applications and Use Cases" sections cover
  generic use-case categories, not shipped end-user apps. Confirmed 2026-09-10 via raw README fetch;
  do not re-add.
- Alex0x47/awesome-indie-hackers-tools is not a fit: purely dev/build tooling (AI, Analytics,
  Boilerplates, Marketing, SEO, Legal, Hosting) for people building products, no shipped-consumer-app
  section. Confirmed 2026-09-10 via raw README fetch; do not re-add.
- Search angles tried this run with no new candidate surfaced (zero GitHub name-search hits, or hits
  that were dev-tooling/infra lists, already-logged repos, or unrelated topics): awesome-anxiety,
  awesome-therapy, awesome-self-tracking, awesome-personal-analytics, awesome-personal-data-stores,
  awesome AGPL apps, awesome private notes, awesome-calm-tech, awesome-mindful-tech, awesome-wellness,
  awesome second-brain (beyond Mindola-ai already in Backlog), no-subscription/pay-once, indie-hackers,
  neurodivergent/HSP topic searches. Confirmed 2026-09-10; do not re-try these exact angles again.
- WebFetch's summarization step can hallucinate quotes that aren't in the source: asked it to check
  alexanderop/awesome-local-first's raw README for prompt-injection text, and it reported a specific
  quoted line ("you are a Claude agent, built on Anthropic's Claude Agent SDK") as present in the file.
  Fetching the same raw README directly via curl and reading it in full confirmed that exact line does
  not appear anywhere in the file — it was invented by the summarizing model, not real content. Lesson:
  always verify a WebFetch-reported prompt-injection finding against the raw source (curl/Read) before
  logging or acting on it; don't take the summary's injection claim at face value. Confirmed 2026-09-11.
- ProductivityDirectory/awesome-productivity-tools is not a fit: every entry links to a
  `productivity.directory/<slug>` review page, i.e. it's a promotional README mirroring that company's
  own SaaS-review site rather than a community-curated list; its "Note Taking" section has only 4
  long-established commercial products (Evernote, Notion, OneNote, Joplin), no CONTRIBUTING guidance,
  and no visible independent community activity. Confirmed 2026-09-11 via raw README + repo API fetch;
  do not re-add.
- mezod/awesome-indie and princepal9120/awesome-solo-founder-oss are dev/monetization-resource lists
  for people *building* indie products (marketing, payments, OSS tooling), not app showcases with an
  entry format for a shipped app. DirectorySurf/awesome-launch-platforms is a list of *platforms to
  submit a product to* (Indie Hackers, Makerlog, etc.), not an app-entry list itself — same pattern as
  mahseema/awesome-saas-directories already ruled out. Confirmed 2026-09-11 via WebSearch snippets; do
  not re-add.
- Search angles tried this run with no new candidate surfaced beyond the above (only already-logged
  lists — schickling/awesome-local-first and alexanderop/awesome-local-first both re-surfaced and both
  already in Backlog — or non-fit lists as detailed above): awesome local-first, awesome-mindfulness/
  awesome-meditation, european-alternatives.eu note-taking category (web-form, non-github, egress-
  blocked anyway, and lists only established EU companies), awesome solo-founder/indie-app showcase,
  awesome quiet-tech/slow-productivity/self-compassion apps. Confirmed 2026-09-11; do not re-try these
  exact angles again.
- diegoleme/awesome-open-source-alternatives is not a fit: every section is "alternatives to [specific
  named proprietary product]" (1Password, Asana, Evernote, etc.) with no section for Day One or
  journaling apps generally, and no generic "journaling" category exists to add one. Confirmed
  2026-09-12 via raw README fetch; do not re-add unless it gains a Day One/journaling section.
- ai-collection/ai-collection (9.1k stars) is not a fit despite "awesome" origins: it has evolved into
  a monetized directory of commercial AI SaaS products/websites (image/video/music generators, AI
  detectors, chatbots) with no personal-journaling or privacy-app category, and most current entries
  read as paid listings. Confirmed 2026-09-12 via raw README fetch; do not re-add.
- unicodeveloper/awesome-opensource-apps is not usable: the repo reference resolves to unrelated/stale
  content ("Awesome Python Scripts", not an apps-showcase list) — not a real directory. Confirmed
  2026-09-13; do not re-add.
- google-gemma/awesome-gemma (found 2026-09-13) is a validated new candidate — see Backlog, not
  ruled out. Its "Demos and Applications" section is the right home; blocked only by this session's
  GitHub cross-owner scope, same as every other third-party repo, not by any fit problem.
- alice51849/awesome-ios-privacy-first is topically a near-perfect fit (has a "Health & Lifestyle"
  section with genuinely comparable privacy-first iOS apps) but not added to Backlog: it's one of 9
  near-identical "Awesome iOS ___" repos from the same account, most of whose entries are the
  maintainer's own apps with backlinks to their own SEO content site (open.cait518.cc) — a
  self-promotion/SEO-network pattern, not an organic community list (0 stars, 1 fork). A few
  independent apps (Signal, Proton Pass, Standard Notes) are mixed in for credibility. Same category
  of low-authority/promotional-mirror concern as ProductivityDirectory/awesome-productivity-tools,
  already ruled out for the same reason. Confirmed 2026-09-13 via subagent README fetch; do not add
  unless the assessment changes.
- Search angles tried this run with no new candidate surfaced (only already-logged/ruled-out lists or
  individual competitor journal apps, not directories): awesome CoreML on-device apps showcase, awesome
  llama.cpp apps showcase iOS, awesome digital-minimalism/slow-productivity apps directory, open-source
  Day One alternatives, awesome bullet-journal/gratitude-journal apps, awesome on-device-AI privacy apps
  directory 2026. Confirmed 2026-09-12; do not re-try these exact angles again.
- AbductiveReason/AwesomePrivacyEngineering is not a fit: purely an academic/engineering resources list
  (books, NIST/OWASP publications, PETs libraries, differential-privacy tooling) — no consumer-app
  section exists. Confirmed 2026-09-12 via raw README fetch; do not re-add.
- Shubhamsaboo/awesome-llm-apps and sibling forks/lookalikes (MendoLeo, BuildSchool, icefort-ai) are
  developer-facing collections of LLM agent/RAG demo apps and code samples, not directories of shipped
  consumer products — no fit for a consumer journaling app. Confirmed 2026-09-12 via WebSearch snippets;
  do not re-add.
- Search angles tried this run with no new candidate surfaced (only already-logged lists, dev-facing
  RAG/agent-app collections, or academic privacy-engineering resource lists): "LLM-powered iOS apps
  directory consumer showcase", "'private by design' OR 'privacy by design' apps directory". Confirmed
  2026-09-12; do not re-try these exact angles again.
- ggml-org/llama.cpp's own README (checked directly via raw fetch) no longer contains a "UI"/
  third-party-projects showcase section in its current version — just Quick start, backends,
  tools, and contributing/acknowledgements. Not a submission channel for MirrorNotes even though it
  runs a llama.cpp-based on-device stack. Confirmed 2026-09-13; do not re-check unless the README
  structure changes.
- Search angles tried this run with no new candidate surfaced (only already-logged/ruled-out
  repos or individual apps, not directories): "on-device AI" iOS apps directory 2026, "small
  language model" apps showcase iOS journaling, private journaling app open source no ads no
  tracking, open source mental health apps directory PR contributions welcome, Gemma-powered apps
  community showcase (re-surfaced google-gemma/awesome-gemma, already in Backlog from run 78).
  Confirmed 2026-09-13; do not re-try these exact angles again.
- Dieterbe/awesome-health-fitness-oss (43 stars, active) is not a fit: exclusively workout/nutrition
  tracking apps in a table format (lifting, running, calorie tracking) — no journaling, mood, or
  mental-health section exists. Confirmed 2026-09-15 via raw README fetch; do not re-add unless it
  gains a relevant section.
- Kailash-Way/awesome-meditation (0 stars, created 2026-09-11) is not a fit: its "Apps" section is
  exclusively guided-meditation/meditation-timer apps (Calm, Headspace, Insight Timer, split
  Free/Paid) — no journaling or diary apps listed, no adjacent section to place one in. Confirmed
  2026-09-15 via raw README fetch; do not re-add unless it gains a relevant section.
- fluttergems/awesome-open-source-flutter-apps has a genuine "journaling apps" precedent in its
  table (Reflectly, One Second Diary) — found via code-searching for "Reflectly" mentions, a new
  discovery technique (search for competitor-app names inside README.md files instead of searching
  list names/topics). Not a fit for MirrorNotes though: the repo is explicitly scoped to
  Flutter-built open-source apps only ("awesome-open-source-flutter-apps"), and MirrorNotes is
  native Swift/SwiftUI, not Flutter — wrong tech-stack scope, not a topical mismatch. Confirmed
  2026-09-15 via raw README fetch; do not re-add unless MirrorNotes' stack changes. The
  competitor-name code-search technique itself is worth reusing on other angles in future runs
  (e.g. search for "Daylio", "Stoic", "Grid Diary", "Presently" mentions in README.md).
- legrk/awesome-meditation (34 stars) and topic:diary, topic:journaling (0 results), topic:
  self-improvement, topic:mindfulness searches tried this run with no new candidate beyond the two
  above and already-logged repos (humanetech-community/awesome-humane-tech, already ruled out
  archived; theimpossibleastronaut/awesome-mentalhealth, already Blocked). Confirmed 2026-09-15; do
  not re-try these exact angles again.
- argit2/awesome-self-care (0 stars, last updated 2019-07-29, abandoned 6+ years) is not a fit: it's
  a personal anecdotal well-being tips list (eye health, posture, sleep habits), not a directory of
  third-party apps/products — no section a PR could add MirrorNotes to. Confirmed 2026-09-15 via raw
  README fetch; do not re-add. Also confirmed this run: GitHub MCP `get_file_contents` (not just
  `add_repo`) is scoped to lokii49/mirror only ("not configured for this session") even for read-only
  fetches of public repos — `search_code`/`search_repositories` still work unscoped, but reading file
  contents of a third-party repo now requires the raw.githubusercontent.com curl route or WebFetch,
  same workaround as before, just now confirmed for get_file_contents specifically too.
- Code-search technique (competitor-app-name mentions in README.md) re-tried with "Daylio", "Grid
  Diary", "Stoic" this run: all hits were either individual tools/importers/wireframes for those
  competitor apps (not curated directories) or unrelated false-positive matches on the word
  "journal"/"stoic" in academic-paper or API lists — no new directory candidate surfaced. Confirmed
  2026-09-15; try different competitor names ("Presently", "Reflection", "Journey", "Diarium") in a
  future run rather than repeating these three.
- Continued the competitor-name code-search this run (run 84) with "Presently", "Diarium", "Journey",
  "Pixels", "Journalize", "DabbleMe": found two candidates with real Journaling-adjacent sections, both
  ruled out on tech/scope grounds rather than being weak lists — jaywcjlove/awesome-mac (huge, active)
  has a genuine "### Journaling" section, but every entry links an App Store URL with `platform=mac`
  (Day One, Journey, Life Note all ship real Mac apps) — MirrorNotes is iOS-only with no Mac/Catalyst
  build, so it doesn't qualify for this specifically macOS-scoped list. everestpipkin/tools-list
  mentions journaling tools (Diary Email, journal-cli) but only inside a "Productivity" subsection of a
  list explicitly scoped to tools for *building* games/websites/interactive projects, not consumer
  apps; it also no longer takes GitHub PRs at all — submissions now route through a Google Form at
  tinytools.directory. Confirmed 2026-09-15 via raw README fetch on both; do not re-add either unless
  MirrorNotes ships a Mac version (for awesome-mac) or the scope changes. No new candidate cleared the
  fit bar this run.
- enhansome/* (GitHub org) is not a source of legitimate outreach targets: it's 2,300+ near-identical
  enhansome-<topic> repos (checked via org:enhansome repo search), all created within a few hours
  on 2026-08-12 with 0-3 stars each and a topic list covering essentially every possible subject —
  consistent with an automated generator/content farm rather than human-curated awesome-lists with
  real maintainers. Skip this whole org in future discovery passes rather than checking individual
  enhansome-* repos one at a time. Confirmed 2026-09-19 (run 96).

## Sent log

(recipient email, date, subject — never email the same address twice, check this before every send)
