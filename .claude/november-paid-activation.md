# November paid activation (draft plan)

Status: draft, 2026-10-11. Owner decision: a grace period plus an in-app notice about 2 weeks ahead, then gating with the 7-day trial. Nothing here is built yet.

## Where things stand
- `SubscriptionService.allFeaturesFree = true` since 3.1.1: every user is Deep, about 1,000 users.
- The paid-tier fixes are already in `3.1.2`, dormant until the flag flips (backlog "C, paid-tier fixes"):
  - the first reflection is free, then the paywall;
  - regrade checks the tier;
  - Ask limit via `askMonthlyLimit`;
  - cold launch starts from `cachedCustomerInfo`;
  - launch uses the silent `syncPurchases`;
  - Free users don't see Talk It Out.
- `TierGateTests` cover the gates with `debugSetTier`. There is no RevenueCat test seam, so purchase, restore and renewal need sandbox checks.

## Timeline (dates to set)
| Step | When | Build |
|---|---|---|
| A. Notice build ships: an in-app card says paid plans start on <date>; nothing is gated | ~2 weeks before cutover | the build after 3.1.2 |
| B. Cutover: `allFeaturesFree = false`, gating on, 7-day trial on every product | cutover date | November build |
| C. Watch: conversion, refunds, crash rate, support mail | first 2 weeks after | — |

The notice has to be in users' hands before the cutover build, so A needs its own release, approved at least ~2 weeks before B.

## A. The notice
- **Where:** one card or sheet, shown once per device on app-open and dismissible. Reuse the What's New path (`featureCardService.shouldShowWhatsNew`), not a new surface.
- **What it says** (draft, needs owner copy and translations into all 10 languages):
  - from <date>, the AI features (daily reflection, Ask, weekly digest, monthly report, mood timeline, widgets) need Core or Deep;
  - writing, reading, search and iCloud backup stay free forever;
  - new subscribers get a 7-day free trial on their first plan. Don't say "every plan": all four products share one subscription group, and Apple gives one introductory offer per Apple ID per group, so anyone who already had a trial (Core or Deep, monthly or yearly) gets none on a later plan.
- **No push notification.** It would be the first marketing notification, which is out of character for the app.
- **App Store "What's New"** text for build A repeats the date.

## B. Cutover build checklist
- [ ] Flip `allFeaturesFree` to `false`. Update CLAUDE.md's "Everything is free for now" paragraph.
- [ ] App Store Connect: the 4 products are live, each with a 7-day introductory offer; prices as in CLAUDE.md.
- [ ] RevenueCat: entitlements `core`/`deep` and offerings `core`/`deep` map to the products (CLAUDE.md).
- [ ] Sandbox on the 14 Pro:
  - purchase Core and Deep, monthly and yearly;
  - start and cancel a trial;
  - restore on a fresh install;
  - upgrade Core → Deep;
  - expiry → Free;
  - launch while offline with a cached subscriber;
  - paywall (reworked 2026-10-16, 679945e), expected results: cancelling the App Store sheet shows no red text; a Core subscriber sees "Current plan" on Core and "Upgrade to Deep" on the button, and the sheet closes by itself after the Deep purchase; a second open preselects Yearly with the button active; an Apple ID that already had any trial sees no trial badge and "Subscribe"; Restore with nothing to restore shows "No active subscription found for this Apple ID."; the Mac paywall's pinned bottom bar lays out cleanly (not yet looked at on Mac);
  - a second device on the same App Store account (Settings > Media & Purchases, not iCloud): buy on device A, then a fresh install on B gets the tier on first launch without tapping Restore (silent `syncPurchases`); with B already open, buy Deep on A and B moves to Deep on foreground (`customerInfoStream` listener); the Mac build (same bundle id, universal purchase) gets the same tier. `[RC] customerID` differs per device (anonymous IDs), which is expected. Checked 2026-10-16 on internal TestFlight build 20 (paid test, now expired): Deep bought on the iPhone 13 showed on the Mac. Still to check at cutover: the live foreground switch with the other app already open, and a fresh install without Restore.
- [ ] Onboarding on a fresh install with existing iCloud data (iPhone 14 Pro, same iCloud account; open MirrorNotes on another device first so everything is synced, then delete and reinstall from TestFlight): the Classic/Sentinel screen appears and onboarding only ends at Start journaling. ad48327 keeps onboarding open when the synced profile arrives; it was checked only with a fake profile in an iCloud-free test copy, so if the 5th screen is still missing the cause is something else. Also: the notification prompt shows on the reminder step, and the mood check-in reminder starts off.
- [ ] Free walk-through:
  - day 0 shows no paywall and no Talk It Out;
  - the paywall shows after the first nudge;
  - widgets show their locked view;
  - Ask shows the paywall;
  - digest needs Core, report and mood timeline need Deep.
- [ ] Core: Ask stops at 15 in a month.
- [ ] Widgets: `widget.tier` follows the real tier (A1 path).
- [ ] Background passes skip digest, report and mood alert for Free, and run for a cached subscriber on a cold launch.
- [ ] Release notes and App Store description name the plans and the trial, worded as "a 7-day free trial for new subscribers" (one trial per Apple ID across all four plans), never "every plan includes a trial". As of 2026-10-16 no shipped description or release note mentions a trial. The paywall already shows the trial only to eligible users (`SubscriptionService.trialEligibleProductIDs`) and says "Subscribe" otherwise.
- [ ] Privacy policy: still no change (on-device AI), but confirm RevenueCat's disclosure is current.
- [ ] RevenueCat dashboard: check the restore behaviour setting. Since 3.1.3 the app user ID comes from the iCloud account (`RevenueCatIdentity`). Two people with separate iCloud accounts sharing one App Store account will have one receipt and two customers. Under "transfer", each launch's `syncPurchases` moves the subscription to whoever opened the app last (audit 2026-10-17).
- [ ] iCloud sign-out: `RevenueCatIdentity` calls `Purchases.logOut()` when the account status is `.noAccount`, so the device becomes anonymous. The next `syncPurchases` re-attaches the receipt to the new anonymous ID (the same transfer path). Check that a paying user who signs out of iCloud keeps their plan.
- [ ] Settings upgrade row: now shows "Free for <length>" only when eligible, with the store's Core monthly price. Check it with real products once gating is on.

## Decided
- Both plans, Core and Deep, launch on 15 November in the paid build, which is 3.1.6, not 3.1.5 (owner, 2026-10-20). A Deep-only November with Core in December was considered and dropped: the notice and release notes already promise "Core or Deep", and one free trial per Apple ID across the group would spend Core's trial on Deep.
- Free users keep reading the weekly digests and monthly reports already made for them, including those from the free period (owner, 2026-10-20; answers question 4). Gating stops new ones being generated, not reading old ones.

## Open questions for the owner
1. Cutover date (and so the notice date).
2. Notice copy, and whether it shows in Sentinel's voice too.
3. Should anyone keep free access (TestFlight testers, reviewers)? A promo code / offer code via App Store Connect avoids app code.
4. What Free users see on surfaces they used for free during the grace period, such as past digests and reports. Reading past AI output could stay free, in line with "your data is always yours". Needs a call before B. **Answered 2026-10-20: they keep reading them (see Decided).**
