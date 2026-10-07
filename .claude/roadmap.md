# MirrorNotes roadmap

Date: 2026-10-07. Covers the whole product (iOS, Mac, growth). Release-specific detail stays in `3.0.9-roadmap.md` and `platform-roadmap.md`. This file orders the work.

**Legend.** **[checked]** means it was verified this pass (App Store Connect, the repo or git). **[unverified]** means it comes from earlier notes and needs confirming.

## Where it stands

- **iOS 3.0.8 (build 14): READY_FOR_SALE** [checked, ASC 2026-10-07].
- **Mac 1.0.1 (build 15): IN_REVIEW** [checked]. Mac 1.0 is on sale.
- Branch `3.0.9` at `9297864` [checked]. The release shipped from it, and it is merged to main through `b5c39f1`.
- Downloads and ratings: unknown. The July audit found ~0 traffic and ~0 downloads [unverified now]. Pull current numbers from App Analytics before planning growth spend.
- The 24/7 marketing routine is disabled (2026-09-20). It never sent mail and never opened PRs.

## Now (this week): verify what shipped

The owner submitted 3.0.8 / Mac 1.0.1 without device checks. It is live now, so these are checks on production, not new work.

1. **CloudKit Production schema for `CD_JournalErasure`** (owner, CloudKit Console). Commit `5a8f08b` seeds only Development. If Production lacks the record type, "Delete Everything" erasure records may not sync to other devices. Confirm it was deployed, and deploy if not. [unverified either way]
2. **Device checks on an App Store install:**
   - Restore offer and local backup (`LocalJournalBackup`, `JournalRestoreCopy`).
   - The widget and lock screen must NOT show the second quote ("You also wrote…" is display-time only).
   - Hospital-day fallback on an Apple Intelligence device (`refusedDayNudge`).
   - Whether `JournalSafety`'s `eventChangedNotification` fires under SwiftData. If it never fires, the "Not backed up" banner never shows.
   - Mac: the Format (Aa) popover and Notes-style toolbar on real hardware, once 1.0.1 is approved.
3. **Watch Mac 1.0.1 review.** If it is rejected, use `deliver --reject_if_possible` and `--run_precheck_before_submit false` (see the release memory).
4. **Native review of the 10-locale release notes and new strings.** They were model-translated. Low risk, cheap.

## Next (3.0.9 / Mac 1.0.2, ~2–4 weeks)

### Engineering
- **Gemma memory on Mac: DONE 2026-10-07** [checked]. `--perfSeed=50 --gemmaMemoryProbe` (DEBUG): 56 MiB before load, peak 278–317 MiB while generating, 142 MiB after. Flat across calls, no leak. `generate` already releases the model after every call, so there's nothing to unload on idle.
- **Gemma output quality on Mac: DONE** [checked]. The llmrig rig already runs on this Mac (Metal), so its numbers are Mac numbers. The app's own path on Mac passed 5/5 synthetic grounded nudges (`validateGroundedNudge`), ~1 s each warm. One soft feeling-line miss ("weary" after a good interview), the known class.
- **Mac gaps** (`platform-roadmap.md` Status), branch `3.0.9-next`:
  - **Global quick-capture shortcut: BUILT** (`4c582c4`). ⌥⌘J opens quick capture in a non-activating floating panel (the MenuBarExtra popover can't be opened from code). Changeable in Settings > General > Input. Checked on this Mac: opens from Finder, typing works, ⌘↩ saves, Esc closes, Finder stays frontmost. ⌥⌘J is also Chrome's JavaScript Console shortcut; while MirrorNotes holds it, Chrome won't get it.
  - **Check-in reminder on Mac: BUILT** (`5604d76`). The notification shows even while the app is frontmost, and clicking it reopens a closed main window, then shows Log Mood. Not yet seen with a real notification click on a signed build.
  - **App Lock (iOS + Mac): BUILT**, see below.
  - Sentinel on Mac: deferred (owner, 2026-10-07).
  - Widget rendering on hardware: needs a signed build; owner check.
- **App Lock** (Settings > Your Data / Archive / iCloud & Privacy > Privacy). Off by default. Face ID / Touch ID with passcode or password fallback. Locks on launch and after 5 minutes away, and hides content in the app switcher. iOS covers each scene with a window above alert level (sheets included). Mac covers every app window and disables the menus. Quick capture stays usable because it only writes. Widgets and notifications still show reflection lines (the Settings caption says so). Checked at runtime: Mac cover/uncover, focus parked and restored, menu commands blocked while locked (`8223688`), away rule; iOS lock → unlock → relock → privacy cover on the simulator, Sentinel dark cover, the automatic passcode prompt; Settings rows rendered (Mac light/dark, iOS Classic/Sentinel). iPhone 14 Pro, 2026-10-07 (separate "MN Dev" test app, synthetic journal; real app untouched): turning on with Face ID, no prompt on a quick return, cold launch locked with an automatic Face ID prompt and passcode fallback, Cancel leaves the Unlock button with no loop, relocked after >5 min away, draft kept behind the lock, Sentinel lock screen, turning off asks Face ID. Found and fixed: system-blue button (`2d57684`). App-switcher cover not captured in a screenshot. Needs a signed build (owner): Touch ID on a Mac, screen-lock detection and the Carbon hotkey under the App Sandbox, a real check-in notification click, the app-switcher snapshot, widgets on hardware.
- **Mac backup cadence.** The snapshot on resign-active shipped (`7f59c08`). Confirm on hardware that it actually refreshes.
- **Deferred, owner's call:** FM daily reflection with today-only context, no background brief. Revisit only if reflections start leaking earlier days or quality complaints come in. It needs an llmrig round first: the rig has never tested the background brief.

### App Store metadata: already done
- Title "MirrorNotes: AI Journal, Diary" and the "adhd" keyword are live in all 10 locales [checked, ASC 2026-10-07]. The June note saying they were pending was stale.

### Owner decisions (2026-10-07)
- App lock on iOS and Mac: toggle (off by default), Face ID / Touch ID with password fallback, locks on launch and after 5 minutes away, hidden in the app switcher.
- Sentinel on Mac: deferred again.
- Global quick-capture hotkey: ⌥⌘J, changeable in Settings.
- Mac mood check-in: a notification at check-in time; clicking it opens Log Mood. Never pops up by itself.
- Work happens on branch `3.0.9-next` (from `9297864`), so a Mac 1.0.1 rejection fix can still ship from `e42e5ea`.

## Growth: the real bottleneck

The product is ahead of distribution. Engineering has shipped 3.0.5 → 3.0.8 plus a Mac app in about two weeks, while traffic was ~0 at the last audit. Suggested order:

1. **Apple Search Ads, $10/day.** The only guaranteed traffic. Run it for 2 weeks, then read the cost per install and the trial-to-paid rate.
2. **Show HN** on a Thursday, 9 AM–12 PM ET. Copy is in `POST-TODAY.md` / `LAUNCH-NOW.md`. The new hook is "on-device AI journal, now on Mac, never invents what you didn't write" (the grounding work is a real story).
3. **Product Hunt relaunch.** The June submission never went live. Launch it with the Mac app as the news.
4. **Promo-allowed subreddits:** r/SideProject, r/iosapps, r/BuildInPublic, r/indiehackers.
5. **Mac-specific channels:** Mac App Store editorial nomination for the Mac app, MacStories / 9to5Mac tips, framed as "new Mac app" (a fresh angle vs the June pitches).
6. **Housekeeping:**
   - bump or close the open awesome-list PRs (note-taking#89, mental-health#78, local-ai#131) [unverified status]
   - the mirrornotes.app name collision with another developer can't be fixed. Win on mirrornotes.org SEO pages and App Store search instead.

Measure after each step (App Analytics impressions → page views → installs → trials). Don't stack channels before you know which one moved the number.

## Later (Phase 2–3, per CLAUDE.md)

- **Phase 2:** export to Notion / Obsidian, multiple journals / folders.
- **Phase 3:** custom AI personas.
- **visionOS:** start with the "Designed for iPad" availability toggle (no code). Then a native target that shares the Mac abstractions. Brain View is the spatial candidate (`platform-roadmap.md`).

**Never:** Android, web, social features.

## Settled: don't reopen without new evidence

- Longer FM reflection (2–3 sentences, V1f): FAILED rig round 10.
- Extra app-built lines (mood trend, theme, streak): the owner declined them. Only the second quote shipped.
- Loosening the Gemma grammar back to free prose: measured ~0/40 faithful.
- Any prompt, `@Guide`, guard or grammar change: llmrig round first, N ≥ 10, rubric written before running.
