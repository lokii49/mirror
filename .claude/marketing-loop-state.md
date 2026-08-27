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

Gated / do not touch yet:
- lissy93/awesome-privacy#671 — blocked on repo-age gate, do NOT touch until repo passes 16wk old (~2026-08-29)

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

## Log
- 2026-08-15: First run. Seeded this state file (it didn't exist yet). Attempted priority-1 PR bump
  (janhq/awesome-local-ai#131, stale since 2026-07-06) — blocked, see Blocked. Attempted priority-2
  new-directory PR — same GitHub scope blocker. Researched via WebSearch (WebFetch to content sites
  is also blocked) and added opensourcealternative.to to Backlog as a web-form candidate since a PR
  route isn't available and WebFetch can't confirm its form. Attempted priority-3 outreach email —
  blocked, SMTP egress unreachable from this environment. No PRs opened, no comments posted, no
  emails sent this run. All three blockers are environment/session configuration issues, not
  exhausted targets — see Blocked and Lessons.
- 2026-08-16: Re-checked all three env blockers per Lessons (test periodically, don't skip): GitHub
  MCP tools (not just add_repo) confirmed scoped to lokii49/mirror only — pull_request_read and
  fork_repository against janhq/awesome-local-ai both rejected with "not configured for this
  session"; no lokii49-owned forks of the four target repos exist (checked via search_repositories,
  contradicts prior run's note — may have been pruned or never existed). SMTP to smtp.mail.me.com:587
  still times out. curl to arbitrary domains still 403s via proxy. Found: WebFetch DOES work for
  github.com/*  URLs specifically (not just api.github.com) even though it fails EGRESS_BLOCKED for
  other domains — useful for researching target-repo README format without needing repo scope.
  Used it to research schickling/awesome-local-first (new candidate, good fit, no CONTRIBUTING.md,
  confirmed entry format from README) and added it to Backlog with ready-to-paste copy. Priority-1
  bump and priority-3 email both skipped again, same env blockers. No PRs opened, no comments
  posted, no emails sent this run.
- 2026-08-16 (run 2): Re-confirmed env blockers with fresh checks (not skipped, since a prior run's
  fork-existence note contradicted itself): pull_request_read on janhq/awesome-local-ai#131 still
  rejected ("not configured for this session", scope = lokii49/mirror only); add_repo confirmed raw
  git clone is possible for public third-party repos but does not unlock GitHub API access, so PR
  bump/creation remains impossible. Direct socket check to smtp.mail.me.com:587 still times out.
  curl to opensourcealternative.to and alternativeto.net both 403 at the proxy. Used WebSearch
  (still working) to find a new candidate directory not yet in channel map/backlog:
  alternativeto.net — has a Journal category and AGPL license filter, good fit, but requires a
  7-day-old account plus logo/screenshots to submit, so it's a [web-form, needs user] backlog entry
  regardless of GitHub scope. Added ready-to-paste copy to Backlog. Priority-1 bump and priority-3
  email both skipped again, same env blockers, both re-verified this run. No PRs opened, no comments
  posted, no emails sent.
- 2026-08-17: Re-confirmed env blockers (periodic check per Lessons): pull_request_read on
  janhq/awesome-local-ai#131 still rejected ("not configured for this session", scope =
  lokii49/mirror only) — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out; proxy status endpoint confirms only a short allowlist passes CONNECT, arbitrary domains
  (tested example.com) still 403 — priority-3 email still impossible. For priority 2, used WebSearch
  + WebFetch (github.com URLs work) to find a new candidate not yet in channel map/backlog:
  iAnonymous3000/awesome-privacy-tools — good fit under its "Notes" category, no CONTRIBUTING.md,
  entry format confirmed (`#### [Name](URL)` + description paragraph). Added ready-to-paste copy to
  Backlog. No PRs opened, no comments posted, no emails sent this run — all three blockers remain
  environment-level (GitHub session scope, general web egress, SMTP egress), not exhausted targets.
- 2026-08-17 (run 2): Re-confirmed all three env blockers fresh (not stale from memory): `add_repo`
  for janhq/awesome-local-ai explicitly rejected with "cross-tier adds are not supported in v1"
  (owner mismatch vs session's lokii49 sources) — priority-1 bump and any direct third-party PR
  remain impossible. `/dev/tcp` to smtp.mail.me.com:587 still times out. curl to example.com via the
  agent proxy still 403s (`connect_rejected`, policy denial) — confirmed via proxy status endpoint.
  Investigated a lead: a pre-existing fork `lokii49/awesome-ios` was in the account's repo list and
  IS addable/clonable (same owner as session). Added it, cloned, inspected README: it's a fork of
  vsouza/awesome-ios, a curated list of iOS *developer* resources (SDKs, libraries, analytics tools)
  with no apps/consumer-directory section — NOT a fit for MirrorNotes. Recorded as a negative finding
  below so future runs don't re-investigate it. For priority 2, searched for a new candidate directory
  across several angles (mental-health apps, on-device/edge-AI showcases, Gemma/Gemini community
  lists, devtool newsletters, awesome-selfhosted) — none were a genuine good fit this run:
  airhorns/awesome-mental-health is a 1-commit, minimally-maintained repo; Curated-Awesome-Lists/
  Awesome-Google-Gemini-AI covers Gemini (cloud API) not Gemma (on-device), a real mismatch;
  console.dev's stated selection criteria require the primary user to be a developer; awesome-selfhosted
  requires self-hostable server software, which MirrorNotes isn't. Declined to force a low-fit
  submission (a prior submission was already rejected once for not matching a list's rules). No PRs
  opened, no comments posted, no emails sent this run — same three env blockers, all re-verified with
  fresh evidence this run, plus one new negative finding (awesome-ios) that prevents wasted future
  effort. Flagging to user via notification: this is now 5 consecutive runs since the loop started
  (2026-08-15) with zero PRs/comments/emails actually sent — the loop is fully blocked on
  session/environment configuration, not on exhausted targets or missing candidates.
- 2026-08-17 (run 3): Re-confirmed all three env blockers fresh this run (not assumed from log):
  `pull_request_read` on janhq/awesome-local-ai#131 still rejected ("not configured for this
  session", allowed repos = lokii49/mirror only) — priority-1 bump still impossible. `/dev/tcp` to
  smtp.mail.me.com:587 still times out — priority-3 email still impossible. curl to example.com and
  opensourcealternative.to via the agent proxy both still 403 (`CONNECT tunnel failed`) — general web
  egress still blocked, confirmed against the proxy status endpoint's unchanged short allowlist. For
  priority 2, searched several new angles (journaling/diary awesome lists, on-device/mobile-LLM
  lists, AGPL/copyleft lists, mindfulness/wellness lists). Ruled out as non-fits or duplicates:
  stevelaskaridis/awesome-mobile-llm (Applications section is academic papers only, no consumer-app
  listings — confirmed via WebFetch on the raw README); ThetaApps/ios-app-opensource (itself a fork
  of dkhamsing/open-source-ios-apps, which is already MERGED — submitting there would be redundant);
  google-ai-edge/gallery (a showcase app you install, not a directory of third-party apps — its
  "skills" mechanism extends the Gallery app itself, doesn't list external apps). Found one genuine
  new fit: manishmarahatta/awesome-mentalhealth — distinct from the two mental-health lists already
  in the channel map, has a real "Apps" section and CONTRIBUTING.md. Note: its CONTRIBUTING.md states
  "I won't list prices or mark free/premium resources," so the ready-to-paste copy added to Backlog
  is deliberately pricing-neutral to comply (per the standing rule about matching each list's exact
  submission rules). Added to Backlog. No PRs opened, no comments posted, no emails sent this run —
  this is the 6th consecutive run with zero direct actions taken, all three blockers remain
  environment/session-level, not exhausted targets.

- 2026-08-17 (run 4): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 explicitly rejected with "Access denied: repository ... is not
  configured for this session. Allowed repositories: lokii49/mirror" — priority-1 bump still
  impossible. `/dev/tcp` to smtp.mail.me.com:587 still times out — priority-3 email still
  impossible. curl to example.com and opensourcealternative.to via the agent proxy both still 403
  (`CONNECT tunnel failed`), proxy status endpoint's allowlist unchanged — general web egress still
  blocked. Checked `list_repos` for lokii49-owned forks of target repos: forks of all four OPEN-PR
  upstreams exist (lokii49/awesome-local-ai, lokii49/awesome-privacy, lokii49/awesome-mental-health,
  lokii49/awesome-note-taking) plus lokii49/awesome-privacy-1 (lissy93 fork) and
  lokii49/awesome-mentalhealth — but per Lessons this doesn't unlock upstream PR/comment API access
  (owner scope, not fork existence, gates the session), so no new attempt was made against them. For
  priority 2, searched several new angles: PKM/journaling lists (doanhthong/awesome-pkm — desktop
  note-tool focused, no mobile/iOS or journaling section, weak fit, skipped), digital-wellbeing lists
  (jcanfield/awesome-digital-wellbeing — Apps section is Android screen-time-blocker tools only, no
  iOS, and its contributing.md is literally unfilled placeholder text ("Make sure you take care of
  this", "And this as well") signaling a low-quality/template repo, skipped per Lessons' quality bar),
  AGPL/open-source-directory lists (unicodeveloper/awesome-opensource-apps — WebFetch resolved this to
  an unrelated Python-scripts repo content, not a fit), and re-verified piotrkulpinski/openalternative
  (the repo behind opensourcealternative.to) is submission-via-website-only
  (openalternative.co/submit), confirming the existing Backlog entry is correct (minor: site copy
  refers to itself as openalternative.co, same product as opensourcealternative.to). No candidate
  found this run cleared the fit/quality bar, so nothing new added to Backlog. No PRs opened, no
  comments posted, no emails sent — this is the 7th consecutive run with zero direct actions, all
  three blockers remain environment/session-level (already flagged to user once at run 2026-08-17
  run2; not re-flagging since nothing has changed).

- 2026-08-18 (run 5): Re-confirmed all three env blockers fresh this run (periodic check per
  Lessons): `pull_request_read` on janhq/awesome-local-ai#131 still rejected ("Access denied ...
  Allowed repositories: lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to
  smtp.mail.me.com:587 still times out — priority-3 email still impossible. curl to example.com and
  opensourcealternative.to via the agent proxy both still 403 (CONNECT tunnel failed) — general web
  egress still blocked. For priority 2, found a genuine new candidate: deluks/awesome-ios-apps, a
  curated consumer iOS-app directory distinct from vsouza/awesome-ios (already ruled out, dev
  resources only). Confirmed via WebFetch: no dedicated journaling category, "Productivity" is the
  best fit, entry format and alphabetical placement confirmed, no pricing-wording restriction seen.
  Added ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent this run —
  8th consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general
  web egress, SMTP egress); not re-flagging via notification since nothing about the blockers has
  changed since the run2 (2026-08-17) flag.

- 2026-08-18 (run 6): Re-confirmed all three env blockers fresh this run (periodic check per Lessons,
  now with live GitHub MCP tools available for the first time — still blocked): `pull_request_read`
  on janhq/awesome-local-ai#131 rejected with "Access denied ... Allowed repositories: lokii49/mirror"
  — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still times out (exit 56) —
  priority-3 email still impossible. curl to example.com and opensourcealternative.to via the agent
  proxy both still 403 (CONNECT tunnel failed) — general web egress still blocked. For priority 2,
  WebSearch + WebFetch (github.com/raw.githubusercontent.com work) found a new genuine candidate:
  ysyisyourbrother/awesome-on-device-AI — has a real "Mobile LLM Apps" subsection (not just papers)
  with one existing entry (Airgap), confirmed format from the actual README content, no restrictive
  CONTRIBUTING. Added ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails
  sent this run — 9th consecutive run blocked purely on environment/session config (GitHub
  cross-owner scope, general web egress, SMTP egress); not re-flagging via notification since nothing
  about the blockers has changed since the run2 (2026-08-17) flag.

- 2026-08-18 (run 7): Re-confirmed all three env blockers fresh this run (periodic check per Lessons):
  `pull_request_read` on janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed
  repositories: lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to
  smtp.mail.me.com:587 still times out (exit 56) — priority-3 email still impossible. curl to
  example.com and opensourcealternative.to via the agent proxy both still 403 (CONNECT tunnel
  failed) — general web egress still blocked. For priority 2, WebSearch + WebFetch found a new
  genuine candidate: awesomelistsio/awesome-ai-edge-computing — has a real "Applications" section
  (not just frameworks/papers) that already lists a directly comparable app (DailyVox, an on-device
  AI voice diary app), confirming journaling/diary apps are in scope. Confirmed entry format and
  CONTRIBUTING.md rules (no pricing restriction, standard fork/PR flow). Added ready-to-paste copy to
  Backlog. No PRs opened, no comments posted, no emails sent this run — 10th consecutive run blocked
  purely on environment/session config (GitHub cross-owner scope, general web egress, SMTP egress);
  not re-flagging via notification since nothing about the blockers has changed since the run2
  (2026-08-17) flag — this is a standing, unchanged condition, not new information.

- 2026-08-19 (run 8): Re-confirmed all three env blockers fresh this run (periodic check per
  Lessons): `pull_request_read` on janhq/awesome-local-ai#131 still rejected ("Access denied ...
  Allowed repositories: lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to
  smtp.mail.me.com:587 still times out — priority-3 email still impossible. curl to example.com via
  the agent proxy still 403s (CONNECT tunnel failed) — general web egress still blocked. For
  priority 2, WebSearch + WebFetch found a new genuine candidate: Axorax/awesome-free-apps (its
  MOBILE.md), which has a real "Note Taking" category with iOS-tagged entries and no pricing
  restriction, distinct from prior dev-focused awesome-swift/awesome-ios lists already ruled out as
  non-fits. Confirmed entry format, icon convention, and the "append to bottom, do not alphabetize"
  contribution rule from contributing.md. Added ready-to-paste copy to Backlog. No PRs opened, no
  comments posted, no emails sent this run — 11th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, general web egress, SMTP egress); not
  re-flagging via notification since nothing about the blockers has changed since the run2
  (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-19 (run 9): Re-confirmed all three env blockers fresh this run (periodic check per
  Lessons): `pull_request_read` on janhq/awesome-local-ai#131 still rejected ("Access denied ...
  Allowed repositories: lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to
  smtp.mail.me.com:587 still times out (exit 56) — priority-3 email still impossible. curl to
  example.com and opensourcealternative.to via the agent proxy both still 403 (CONNECT tunnel
  failed) — general web egress still blocked. For priority 2, WebSearch + WebFetch found a new
  genuine candidate: naughtyspirit/awesome-ios-apps — has a real "Open Source" section distinct from
  all prior consumer-iOS-app candidates already ruled out or in Backlog (vsouza/awesome-ios,
  deluks/awesome-ios-apps, ThetaApps/ios-app-opensource, jogendra/example-ios-apps). Confirmed entry
  format and CONTRIBUTING.md rules (no pricing/alphabetization restriction, no prompt-injection
  content). Added ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent
  this run — 12th consecutive run blocked purely on environment/session config (GitHub cross-owner
  scope, general web egress, SMTP egress); not re-flagging via notification since nothing about the
  blockers has changed since the run2 (2026-08-17) flag — this remains a standing, unchanged
  condition.

- 2026-08-19 (run 10): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124/timeout) — priority-3 email still impossible. curl to example.com via the
  agent proxy still 403s (`connect_rejected`, policy denial, confirmed via proxy status endpoint) —
  general web egress still blocked. For priority 2, searched several new angles via
  search_repositories (awesome journal/diary/gemma/offline-ai/swiftui-apps) — all returned only
  generic large awesome-lists already known or irrelevant (devtools, ML frameworks, unrelated
  languages), no new journaling/privacy/on-device-AI/iOS-consumer-app fit found. One candidate
  investigated and ruled out: tortuvshin/open-apps (a curated open-source app directory with a real
  iOS/Flutter/Kotlin scope and a submission web form) requires "at least 50 stars, and at least 50
  lifetime commits" per its own criteria (confirmed via WebFetch on its github.com page) —
  lokii49/mirror currently has 0 stars, so it does not qualify; recorded as a negative finding below
  so future runs don't re-investigate it. No new candidate cleared the fit/quality bar this run, so
  nothing new added to Backlog. No PRs opened, no comments posted, no emails sent — 13th consecutive
  run blocked purely on environment/session config (GitHub cross-owner scope, general web egress,
  SMTP egress); not re-flagging via notification since nothing about the blockers has changed since
  the run2 (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-20 (run 11): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, re-checked
  piotrkulpinski/openalternative's CONTRIBUTING.md directly (confirmed still website-form-only via
  openalternative.co/submit, matching the existing Backlog entry, no change needed) and checked
  johnjago/awesome-free-software (no Mobile/iOS/Journal/Notes category exists — desktop/OS software
  only — ruled out, not added). Investigated privacyguides.org's "Notebooks" recommendation page: has
  a hard stated criterion that "any cloud sync functionality must be E2EE" — MirrorNotes' CloudKit
  sync encryption properties aren't confirmed to meet that bar from this environment, and misrepresenting
  it would violate the standing rule against claiming things not in FEATURES, so skipped rather than
  risk a false claim or a rejected submission (recorded as a negative finding below). Found one genuine
  new candidate: alexanderop/awesome-local-first, distinct from schickling/awesome-local-first (already
  in Backlog) — different maintainer/structure, has a real "Example Applications" subsection with a
  directly comparable existing entry (Memex, an on-device AI journal app), confirmed entry format.
  Added ready-to-paste copy to Backlog, flagging the curator's soft popularity preference as a risk
  note. No PRs opened, no comments posted, no emails sent this run — 14th consecutive run blocked
  purely on environment/session config (GitHub cross-owner scope, general web egress, SMTP egress);
  not re-flagging via notification since nothing about the blockers has changed since the run2
  (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-20 (run 12): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed, confirmed via proxy status endpoint's unchanged allowlist) —
  general web egress still blocked. For priority 2, investigated areknawo/awesome-productivity-
  software (had a real "Notes" section, looked promising) but found it archived by its owner on
  2026-03-12 (read-only) — ruled out and logged as a negative finding so future runs skip it. Found
  one genuine new candidate: Furthir/awesome-useful-projects — active (1.5k stars), its "Productivity"
  section already lists comparable privacy-first GitHub-hosted note/knowledge apps (Joplin, Memos,
  Siyuan Note) as precedent, no CONTRIBUTING.md restrictions, entry format confirmed from existing
  entries. Added ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent
  this run — 15th consecutive run blocked purely on environment/session config (GitHub cross-owner
  scope, general web egress, SMTP egress); not re-flagging via notification since nothing about the
  blockers has changed since the run2 (2026-08-17) flag — this remains a standing, unchanged
  condition.

- 2026-08-20 (run 13): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, searched
  several new angles (journal/journalism GitHub search — all academic/unrelated noise; awesome-swiftui
  variants; awesome privacy-friendly; awesome-gemma; on-device-AI variants — all either already known,
  too small/unmaintained, or off-topic). Ruled out madimalo/awesome-swiftui as a non-fit (0 stars,
  SwiftUI clone/demo projects not shipped consumer apps) — logged as negative finding. Found one
  genuine new candidate: XargsUK/awesome-adhd — active (413 stars), has a real "Notetaking" subsection
  under "Apps" with a confirmed markdown-table entry format and pricing-symbol legend; MirrorNotes'
  freemium model (free tier + paid mood-timeline/monthly-report tiers) maps cleanly to the existing
  💠 convention used for comparable apps like Obsidian. No CONTRIBUTING.md at the expected path;
  README documents an issue/Google-Form submission path, PR-editing-the-table should also work per
  repo convention. Added ready-to-paste table row to Backlog. No PRs opened, no comments posted, no
  emails sent this run — 16th consecutive run blocked purely on environment/session config (GitHub
  cross-owner scope, general web egress, SMTP egress); not re-flagging via notification since nothing
  about the blockers has changed since the run2 (2026-08-17) flag — this remains a standing, unchanged
  condition.

- 2026-08-21 (run 17): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, searched
  privacy/journaling/note-taking angles and found paulaime/awesome-privacy — distinct from pluja
  (already OPEN) and lissy93 (gated), not a fork, 406 stars/106 commits, has a real "Note-taking"
  section. Also found and ruled out CRK1918/awesome-privacy-list as a duplicate: confirmed it's a
  fork of pluja/awesome-privacy, so a submission there would be redundant with the already-OPEN PR —
  logged as a negative finding so future runs skip it without re-checking. Added paulaime entry to
  Backlog with confirmed format. No PRs opened, no comments posted, no emails sent this run — 17th
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general web
  egress, SMTP egress); not re-flagging via notification since nothing about the blockers has changed
  since the run2 (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-21 (run 18): Ran concurrently with run 17 (both picked up the same scheduled firing; merged
  without conflict since each found a distinct candidate). Re-confirmed all three env blockers fresh
  this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out, also tried alternate ports 465/25/2525, all fail — priority-3 email still impossible.
  curl to example.com via the agent proxy still 403s (CONNECT tunnel failed, proxy status endpoint's
  allowlist unchanged) — general web egress still blocked. Also confirmed `get_file_contents` (not
  just write ops) is scoped the same way — read access to third-party repos via the GitHub MCP tools
  is blocked too, not just write; WebFetch on raw.githubusercontent.com/github.com URLs remains the
  only way to read third-party repo content from this session. For priority 2, found one genuine new
  candidate: freedomappsprivacy/Freedom-apps-privacy — active FOSS/privacy-alternatives list (CC0-1.0,
  positions itself as combining/expanding awesome-privacy + awesome-selfhosted), distinct from all
  three awesome-privacy variants already known. Confirmed via WebFetch (raw README): best-fit is its
  "Notes & Knowledge" table section (Joplin, Standard Notes, Logseq, Trilium), table format and legend
  confirmed verbatim, no CONTRIBUTING.md restrictions, no pricing wording restriction, no
  prompt-injection content. Added ready-to-paste table row to Backlog, with the Privacy-rating column
  deliberately left at 4/5 stars rather than 5/5 since the other 5-star entries are all E2EE-sync
  tools and MirrorNotes' CloudKit sync E2EE status isn't confirmed (same caution as the existing
  privacyguides.org finding in Lessons). No PRs opened, no comments posted, no emails sent this run —
  18th consecutive run blocked purely on environment/session config (GitHub cross-owner scope,
  general web egress, SMTP egress); not re-flagging via notification since nothing about the blockers
  has changed since the run2 (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-21 (run 19): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (`connect_rejected`, policy denial, proxy status endpoint's allowlist unchanged) —
  general web egress still blocked. For priority 2, searched several new angles via
  search_repositories (journaling/diary apps, privacy-first apps, mindfulness/wellness/self-
  improvement apps, offline-first apps, Swift/iOS consumer-app curators) — every result was either
  already known (dreamingechoes/awesome-mental-health, theimpossibleastronaut/awesome-mentalhealth,
  alexanderop/awesome-local-first, schickling/awesome-local-first — all already in channel
  map/Backlog) or a clear non-fit (dev-focused framework/library lists, unrelated topics like
  competitive programming, PWA tooling, raspberry pi). No new candidate cleared the fit/quality bar
  this run, so nothing new added to Backlog. No PRs opened, no comments posted, no emails sent —
  19th consecutive run blocked purely on environment/session config (GitHub cross-owner scope,
  general web egress, SMTP egress); not re-flagging via notification since nothing about the
  blockers has changed since the run2 (2026-08-17) flag — this remains a standing, unchanged
  condition.

- 2026-08-21 (run 20): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, found one
  genuine new candidate: google-gemma/awesome-gemma — Google DeepMind's own official awesome list for
  the Gemma model family, first Gemma-specific list found (distinct from janhq/awesome-local-ai and
  the two prior generic on-device/edge-AI Backlog entries). Has a real "Demos and Applications" section
  with consumer-app entries, format and CONTRIBUTING.md rules confirmed via WebFetch (no promotional
  wording allowed — copy written factually to comply). Added ready-to-paste copy to Backlog. No PRs
  opened, no comments posted, no emails sent this run — 20th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, general web egress, SMTP egress); not
  re-flagging via notification since nothing about the blockers has changed since the run2
  (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-21 (run 21): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, searched
  several new angles (journaling/diary GitHub topics, AGPL open-source app directories, digital-
  minimalism/self-improvement apps, offline-first, SwiftUI apps) via WebSearch and search_repositories
  — all hits were either already known/logged, generic noise (huge unrelated lists, random small repos
  matching keywords), or a clear non-fit. Investigated yangwao/awesome-offline (looked plausible from
  its name) and ruled it out: it's a developer-resources list (articles/talks/libraries), no section
  for consumer apps — logged as a negative finding. No new candidate cleared the fit/quality bar this
  run, so nothing new added to Backlog. No PRs opened, no comments posted, no emails sent — 21st
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general web
  egress, SMTP egress); not re-flagging via notification since nothing about the blockers has changed
  since the run2 (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-22 (run 22): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed, proxy status endpoint's allowlist unchanged) — general web
  egress still blocked. For priority 2, searched several new angles (bullet journal, digital diary,
  zettelkasten/digital-garden, AGPL open source apps) — mostly noise or app-specific plugin lists
  (Obsidian/Logseq/RemNote resources, not consumer-app directories) or wrong-platform (Android/
  Flutter). Found one genuine new candidate: akshaybharwani/data-not-collected-ios-apps — a curated
  list of iOS apps that don't collect user data (147 apps, 10 stars, actively updated), a strong
  topical match since the whole list's theme mirrors MirrorNotes' on-device-AI/no-data-leaves-device
  pitch. Confirmed via WebFetch (raw README): no journaling category, best fit is "Productivity",
  entry format is bare `App Name - App Store URL` (no description field), no CONTRIBUTING.md, no
  prompt-injection content. Added ready-to-paste entry to Backlog. Also found two very small
  (0-star, single-account, ~1mo old) candidate repos by "alice51849" (awesome-ios-privacy-first,
  awesome-ios-health-wellness) that are an almost too-perfect thematic match for MirrorNotes'
  exact pitch (no-account, on-device, pay-once) — flagging as a mild carbon-copy-account coincidence
  worth a human glance, not added to Backlog this run pending that. No PRs opened, no comments
  posted, no emails sent — 22nd consecutive run blocked purely on environment/session config (GitHub
  cross-owner scope, general web egress, SMTP egress); not re-flagging via notification since nothing
  about the blockers has changed since the run2 (2026-08-17) flag — this remains a standing,
  unchanged condition.

- 2026-08-23 (run 23): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (`connect_rejected`, policy denial, proxy status endpoint's allowlist unchanged) —
  general web egress still blocked. For priority 2, checked piotrkulpinski/open-source-alternatives
  (6.6k stars, distinct repo from piotrkulpinski/openalternative already in Backlog) and confirmed via
  WebFetch it's read-only, maintained by the OpenAlternative platform, submissions still go through
  openalternative.co — no new PR route, matches existing Backlog entry, not re-added. Found one
  genuine new candidate: mustbeperfect/definitive-opensource — large, active (3.4k stars) consumer-
  facing-only open source directory with a real "Journal" subsection under "Text" (alongside Note
  Taking, Markdown Editor). Confirmed table entry format from multiple other sections of the README
  (exact Journal-subsection rows weren't fetchable due to page truncation, but format is consistent
  repo-wide); no CONTRIBUTING.md or pricing restriction found. Noted a caveat in the ready-to-paste
  copy: the list's Stars column will show lokii49/mirror's real count (currently 0, confirmed via
  search_repositories) since there's no minimum-star gate found (unlike tortuvshin/open-apps). Added
  ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent this run — 23rd
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general web
  egress, SMTP egress); not re-flagging via notification since nothing about the blockers has changed
  since the run2 (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-23 (run 24): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, searched
  several new angles via search_repositories (gratitude/mood-tracker apps, journaling/diary app
  topics, indie/small-tech/ethical iOS app lists, no-subscription/buy-once app directories, indie
  maker/developer lists) — every result was either already known/logged or a clear non-fit (generic
  AI/dev-tool lists, unrelated topics like game dev, RSS, Black Friday deals, Chinese indie-dev
  showcase). No new candidate cleared the fit/quality bar this run, so nothing new added to Backlog.
  No PRs opened, no comments posted, no emails sent — 24th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, general web egress, SMTP egress); not
  re-flagging via notification since nothing about the blockers has changed since the run2
  (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-23 (run 25): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, searched
  several new angles via search_repositories (journaling, ADHD apps, mood/gratitude tracking) — most
  results were off-topic academic-journal noise (search term collision with "journal" the publication
  sense) or already known. Found one genuine new candidate: dicktracey909/awesome-adhd-tools —
  active (53 stars), distinct from XargsUK/awesome-adhd already in Backlog, has an "Emotional
  Regulation" section that already lists Daylio (mood tracking) as precedent, a fit for MirrorNotes'
  mood timeline feature. Confirmed entry format and CONTRIBUTING rules (ADHD-specific benefit required,
  no affiliate links, no pricing restriction) via WebFetch. Added ready-to-paste copy to Backlog,
  framed honestly around low-friction capture/mood tracking without inventing features. No PRs opened,
  no comments posted, no emails sent this run — 25th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, general web egress, SMTP egress); not
  re-flagging via notification since nothing about the blockers has changed since the run2
  (2026-08-17) flag — this remains a standing, unchanged condition.

- 2026-08-23 (run 26): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com and
  opensourcealternative.to via the agent proxy both still 403 (CONNECT tunnel failed) — general web
  egress still blocked. For priority 2, searched several new angles (digital minimalism/no-tracking
  directories, AGPL/copyleft software lists, ethical software lists, privacy-respecting service
  lists, journaling-app GitHub topic page for aggregator repos) — no genuine new fit found. Checked
  nikivdev/privacy-respecting (2k stars, actively maintained) via WebFetch: confirmed it has no
  note-taking/journaling/diary/productivity section at all (Search Engines, Social Networks,
  Messengers, Cloud Storage, VPN, Hosting, Email, OS, Browsers, Video, AI Assistants, Maps only) —
  logged as a negative finding so future runs skip it. GitHub topic page for "journaling-app" only
  surfaces individual apps, not curated directories — not a useful discovery channel. No new
  candidate cleared the fit/quality bar this run, so nothing new added to Backlog. No PRs opened, no
  comments posted, no emails sent — 26th consecutive run blocked purely on environment/session config
  (GitHub cross-owner scope, general web egress, SMTP egress). Re-flagging to user via notification
  this run despite no new information: it has been 6 days / ~24 runs since the last flag
  (2026-08-17 run2) with the identical block still fully open and 17 ready-to-paste backlog entries
  now piled up waiting on a human to actually submit them — a periodic reminder seemed warranted
  given the scale of unactioned backlog, even though the underlying condition itself hasn't changed.

- 2026-08-24 (run 27): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com and
  opensourcealternative.to via the agent proxy both still 403 (CONNECT tunnel failed) — general web
  egress still blocked. For priority 2, searched several new angles via search_repositories
  (note-taking/journaling app directories, indie-iOS lists, mindfulness/meditation, digital
  wellbeing, pay-once/no-subscription app lists, Gemma-application repos, topic:journal/topic:diary)
  — no genuine new fit found. Investigated and ruled out: Correia-jpv/fucking-open-source-ios-apps —
  confirmed via WebFetch it's an auto-generated derivative of dkhamsing/open-source-ios-apps ("This
  README is generated ... To contribute, make changes to contents.json"), where MirrorNotes is
  already MERGED (#2274) — submitting separately would be a low-value duplicate of an already-served
  channel, not added. Re-checked the two alice51849 repos flagged as a coincidence in run 22
  (awesome-ios-privacy-first, awesome-ios-health-wellness): still 0 stars, still 1 fork/1 open issue
  each, no growth in 5+ weeks — leaving unadded pending a human glance, per that run's note; nothing
  new to add there. Crackx17/awesome-pay-once-mac-apps ruled out — Mac apps only, wrong platform for
  MirrorNotes (iOS). No new candidate cleared the fit/quality bar this run, so nothing new added to
  Backlog. No PRs opened, no comments posted, no emails sent — 27th consecutive run blocked purely on
  environment/session config (GitHub cross-owner scope, general web egress, SMTP egress); not
  re-flagging via notification since nothing about the blockers has changed since the last flag
  (2026-08-23 run 26) — this remains a standing, unchanged condition.

- 2026-08-24 (run 28): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (`connect_rejected`, policy denial, proxy status endpoint's allowlist unchanged) —
  general web egress still blocked. For priority 2, searched several new angles via
  search_repositories (voice/encrypted-journal apps, indie-iOS lists, self-improvement/digital-detox
  lists, private-AI-apps lists, on-device-llm apps, quantified-self refresh, open-source-apple-apps) —
  no genuine new fit found: hits were either 0-result, unrelated (Keycloak, delivery-app templates,
  academic-journal noise), dev-resource lists (jiejuefuyou/awesome-indie-ios — indie-dev tooling, not
  a consumer directory), a private-cloud/homelab list (mxuexxmy/awesome-lazycat-microserver, not
  iOS-app related), or forks/near-duplicates of dkhamsing/open-source-ios-apps (already MERGED) —
  Correia-jpv's fork already ruled out in run 27, several more near-identical forks/spam clones
  surfaced this run (spartastanprice263/*, mazahakater4/*), not worth logging individually. No new
  candidate cleared the fit/quality bar this run, so nothing new added to Backlog. No PRs opened, no
  comments posted, no emails sent — 28th consecutive run blocked purely on environment/session config
  (GitHub cross-owner scope, general web egress, SMTP egress); not re-flagging via notification since
  nothing about the blockers has changed since the last flag (2026-08-23 run 26) — this remains a
  standing, unchanged condition. Note: the pool of easily-discoverable new awesome-list candidates via
  search_repositories/WebSearch appears increasingly saturated (18 ready-to-paste Backlog entries
  already accumulated across runs 1-27) — future runs may increasingly come up empty on priority 2
  simply because most reachable good-fit targets have already been found, not because the search
  effort lapsed.

- 2026-08-24 (run 29): Re-confirmed all three env blockers fresh this run: `add_repo` for
  janhq/awesome-local-ai still rejected ("cross-tier adds are not supported in v1 ... session already
  has repos from owner(s) [lokii49]") — priority-1 bump still impossible. `/dev/tcp` to
  smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible. For priority 2,
  searched fresh angles via WebSearch (journaling/diary app privacy directories, self-hosted/AGPL iOS
  app lists, on-device/mobile-LLM app directories, mental-health app lists) and checked two genuinely
  new hits via WebFetch: megan201296/awesome-mental-health (Articles/Books/Talks only, no apps
  section, no CONTRIBUTING, ~12 commits — inactive) and stevelaskaridis/awesome-mobile-llm (a
  developer/research resources list — papers, frameworks, benchmarks — not a consumer-app directory
  despite the on-device-AI angle). Both ruled out and logged under Lessons so future runs skip them.
  No new candidate cleared the fit/quality bar, so nothing added to Backlog. No PRs opened, no
  comments posted, no emails sent — 29th consecutive run blocked purely on environment/session config
  (GitHub cross-owner scope, general web egress, SMTP egress); not re-flagging via notification since
  nothing about the blockers has changed since the last flag (2026-08-23 run 26) — this remains a
  standing, unchanged condition.

- 2026-08-24 (run 30): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out — priority-3 email still impossible. curl to example.com and opensourcealternative.to
  via the agent proxy both still 403 (CONNECT tunnel failed) — general web egress still blocked. For
  priority 2, searched several new angles (journaling/self-improvement/mindfulness/writing-apps
  lists) — found one genuine new candidate: wckyhq/awesome-mindfulness, a small mindfulness/wellness
  list with a real dedicated "Journalling" section (2 existing iOS-app entries), confirmed entry
  format and icon convention via WebFetch. Flagged as lower-confidence than most Backlog entries
  (0 stars, single-commit repo) but a specific, genuine fit — added ready-to-paste copy to Backlog.
  Also found and fixed a real repo-hygiene issue unrelated to the blockers: this session's `main`
  branch ref and `origin/main` were stale, 7 commits behind the actual HEAD this loop had been
  committing to across runs 23-29 (a detached-HEAD checkout artifact) — verified it was a clean
  fast-forward (no divergence), merged `main` up to the latest commit, and confirmed
  (via `git fetch`) that `origin/main` already held all 7 commits, so no data was actually at risk;
  local branch state alone was stale. No PRs opened, no comments posted, no emails sent this run —
  30th consecutive run blocked purely on environment/session config (GitHub cross-owner scope,
  general web egress, SMTP egress); not re-flagging via notification since nothing about the
  blockers has changed since the last flag (2026-08-23 run 26) — this remains a standing, unchanged
  condition.

- 2026-08-25 (run 31): Fixed repo hygiene again: local `main`/`origin/main` were still 8 commits
  behind the detached-HEAD chain runs 23-30 had been committing to (run 30's own "fix stale main
  branch ref" note only fixed it up to run 29 — its own commit landed on the detached HEAD, not
  `main`). Verified clean fast-forward, merged, pushed to `origin/main` — HEAD, `main`, and
  `origin/main` are now all aligned. Re-confirmed all three env blockers fresh: `pull_request_read`
  on janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out — priority-3 email still impossible. curl to example.com and opensourcealternative.to
  via the agent proxy both still 403 (CONNECT tunnel failed) — general web egress still blocked. For
  priority 2, searched several new angles (journaling/diary GitHub search, self-hosted AI companion +
  journaling, buy-once/no-subscription iOS apps, digital wellbeing/self-improvement). Ruled out two:
  frechdi/awesome-self-hosted-ai (exclusively server-side LLM infra/hosting, no mobile-app section at
  all) and DasterProkio/awesome-ai-companion (525 stars, active, but scoped to AI-companion-persona
  tools specifically, not general journaling — MirrorNotes has no companion/persona feature so doesn't
  fit even its closest section) — both logged under Lessons. Found one genuine new candidate:
  jyguyomarch/awesome-productivity — large, active (3.3k stars, 140 open PRs), has a real "Note
  Management" subsection listing comparable privacy-first apps (Standard Notes). Confirmed entry
  format and CONTRIBUTING.md rules via WebFetch (no pricing restriction, no prompt-injection content).
  Added ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent this run —
  31st consecutive run blocked purely on environment/session config (GitHub cross-owner scope,
  general web egress, SMTP egress); not re-flagging via notification since nothing about the blockers
  has changed since the last flag (2026-08-23 run 26) — this remains a standing, unchanged condition.

- 2026-08-25 (run 32): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com and
  opensourcealternative.to via the agent proxy both still 403 (CONNECT tunnel failed) — general web
  egress still blocked. For priority 2, searched several new angles via search_repositories/WebSearch
  (encrypted/private/offline journal lists, buy-once/no-subscription app lists, ethical-software/
  small-tech directories, Gemma-3-specific app lists, AI-diary/AI-journal directory searches) — all
  either off-topic noise (academic-journal/publication-sense collisions, huge generic top-star lists
  already known), zero-result queries, or already-known/logged candidates. No new candidate cleared
  the fit/quality bar this run, so nothing added to Backlog. No PRs opened, no comments posted, no
  emails sent — 32nd consecutive run blocked purely on environment/session config (GitHub cross-owner
  scope, general web egress, SMTP egress), all three re-verified fresh this run with unchanged
  evidence; not re-flagging via notification since nothing about the blockers has changed since the
  last flag (2026-08-23 run 26) — this remains a standing, unchanged condition.

- 2026-08-25 (run 33): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (CONNECT tunnel failed) — general web egress still blocked. For priority 2, searched
  several new angles (awesome-journal/awesome-diary/awesome-note-taking name variants, awesome-ios
  topic search) — most returned only academic-journal-collisions or already-known large generic
  lists (sindresorhus/awesome, awesome-mac, awesome-privacy x2, awesome-flutter, awesome-swift, all
  already known/ruled-out/in-map). Found one genuine new candidate: andyhaskell/awesome-notetaking —
  small but active, not archived, has a real "Apps" section (Notion, Dash) distinct from
  tehtbl/awesome-note-taking (already OPEN). Confirmed entry format and CONTRIBUTING.md rules via
  WebFetch (non-promotional description required, no pricing restriction, no prompt-injection
  content). Added ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent
  this run — 33rd consecutive run blocked purely on environment/session config (GitHub cross-owner
  scope, general web egress, SMTP egress), all three re-verified fresh this run with unchanged
  evidence; not re-flagging via notification since nothing about the blockers has changed since the
  last flag (2026-08-23 run 26) — this remains a standing, unchanged condition.

- 2026-08-26 (run 34): Re-confirmed all three env blockers fresh this run: `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. `/dev/tcp` to smtp.mail.me.com:587 still
  times out (exit 124) — priority-3 email still impossible. curl to example.com via the agent proxy
  still 403s (`connect_rejected`, policy denial, proxy status endpoint's allowlist unchanged) —
  general web egress still blocked. For priority 2, searched several new angles via WebSearch
  ("journaling app"/"diary app" iOS privacy directories, AGPL iOS app directories, "Day One
  alternative" open-source lists) — every hit was either an individual app (not a curated directory
  with a submission path), already-known/logged (naughtyspirit, ThetaApps, vsouza, dkhamsing,
  jogendra), or a general software-comparison site (alternativeto.net, already in Backlog as a
  web-form candidate) rather than a new list. No new candidate cleared the fit/quality bar this run,
  consistent with run 28's saturation note. No PRs opened, no comments posted, no emails sent — 34th
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general web
  egress, SMTP egress), all three re-verified fresh this run with unchanged evidence; not re-flagging
  via notification since nothing about the blockers has changed since the last flag (2026-08-23
  run 26) and the gap since then (3 days / 8 runs) is shorter than the prior flagging interval —
  this remains a standing, unchanged condition.

- 2026-08-27 (run 35): Re-confirmed all three env blockers fresh this run: `/dev/tcp` to
  smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible. curl to
  example.com via the agent proxy still 403s (`connect_rejected`, policy denial, proxy status
  endpoint's allowlist unchanged) — general web egress still blocked. `pull_request_read` on
  janhq/awesome-local-ai#131 still rejected ("Access denied ... Allowed repositories:
  lokii49/mirror") — priority-1 bump still impossible. For priority 2, checked
  raw.githubusercontent.com/dkhamsing/open-source-ios-apps APPSTORE.md (surfaced by a search hit) and
  confirmed it's the same generated list as the already-MERGED #2274 (built from the same
  contents.json), and MirrorNotes is already listed there under Health — not a new channel, no action
  needed. Investigated mrseth01/awesome-adhd (322 stars, active, distinct from XargsUK/awesome-adhd
  already in Backlog) and ruled it out: its "Software Tools" section is habit-formation/focus apps
  (Beeminder, SelfControl, Forest, Habitica) with no journaling/mood-tracking precedent, and entries
  are bare links with no description field in practice — a real fit/format mismatch, logged under
  Lessons. Searched several further angles (awesome-gemma-adjacent, mental-wellness/self-reflection,
  general journaling/diary "awesome list" web search) — all either already-known/logged or generic
  noise (huge unrelated LLM-tooling lists, individual apps rather than curated directories with a
  submission path). No new candidate cleared the fit/quality bar this run, consistent with run 28's
  saturation note. No PRs opened, no comments posted, no emails sent — 35th consecutive run blocked
  purely on environment/session config (GitHub cross-owner scope, general web egress, SMTP egress),
  all three re-verified fresh this run with unchanged evidence; not re-flagging via notification since
  nothing about the blockers has changed since the last flag (2026-08-23 run 26) and the gap since
  then (4 days / 9 runs) remains shorter than the prior flagging interval — this remains a standing,
  unchanged condition.

- 2026-08-27 (run 36): Re-confirmed all three env blockers fresh this run: `/dev/tcp` to
  smtp.mail.me.com:587 still times out (exit 124) — priority-3 email still impossible. curl to
  example.com via the agent proxy still 403s (CONNECT tunnel failed) — general web egress still
  blocked. `pull_request_read` on janhq/awesome-local-ai#131 still rejected ("Access denied ...
  Allowed repositories: lokii49/mirror") — priority-1 bump still impossible. For priority 2, searched
  several new angles (on-device-AI journaling 2026, digital-minimalism/no-tracking iOS directories,
  AGPL/copyleft open-source directories, voice-journal/gratitude-journal/reflection-app lists) — most
  hits were already-known/logged candidates or individual apps rather than curated directories. Found
  one genuine new candidate: sfermigier/awesome-foss-alternatives — a business-SaaS-alternatives list
  with a real "Note-taking / Personal Knowledge Management" section (Joplin, Logseq, Notesnook,
  SiYuan) as precedent, no CONTRIBUTING restrictions, entry format confirmed via WebFetch. Added
  ready-to-paste copy to Backlog. No PRs opened, no comments posted, no emails sent this run — 36th
  consecutive run blocked purely on environment/session config (GitHub cross-owner scope, general web
  egress, SMTP egress), all three re-verified fresh this run with unchanged evidence; not re-flagging
  via notification since nothing about the blockers has changed since the last flag (2026-08-23
  run 26) and the gap since then (4 days / 10 runs) remains shorter than the prior flagging interval —
  this remains a standing, unchanged condition.

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

## Sent log

(recipient email, date, subject — never email the same address twice, check this before every send)
