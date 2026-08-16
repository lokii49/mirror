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

## Sent log

(recipient email, date, subject — never email the same address twice, check this before every send)
