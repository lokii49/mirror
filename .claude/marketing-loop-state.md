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
- Some directories gate submissions on the *submitting repo's* own popularity, not just topical
  fit: tortuvshin/open-apps requires ≥50 stars and ≥50 lifetime commits on the source repo before
  it'll list an app. lokii49/mirror has 0 stars, so it doesn't qualify yet — skip this target until
  the repo has enough stars, don't re-add it to Backlog until then. Confirmed 2026-08-19.

## Sent log

(recipient email, date, subject — never email the same address twice, check this before every send)
