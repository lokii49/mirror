# Xcode Cloud for mirror

Set up 2026-10-10 for the `3.1.2` backlog: build and unit-test every push on Apple's servers, so work can continue while the laptop is closed.

## What it covers, and what it doesn't

| Covered | Not covered |
|---|---|
| iOS build (and macOS build, if added) of every push to `3.1.2` | Physical iPhone tests (14 Pro, iPhone 13): those need the laptop |
| Unit tests (`mirrorTests`) on an iOS simulator | UI tests (`mirrorUITests`): left out, as XCUITest is unreliable on the Xcode 27 betas |
| Results in App Store Connect and Xcode's Report navigator, emailed on failure | Model-gated tests: they skip, because simulators have no Foundation Models and no Gemma file |

Model-gated means `@Test(.enabled(if: LocalLLMService.isModelAvailable))`, which includes the runner-level reflection tests. A clean CI run is therefore not the full device evidence the backlog asks for. Run those on the 14 Pro later (see "When the laptop is back").

## Files in the repo

- `ci_scripts/ci_post_clone.sh`: runs after Xcode Cloud clones the repo. It creates `mirror/LocalModels` and logs the branch, commit and Xcode version. It must stay executable and next to `mirror.xcodeproj`.
- Shared scheme **`mirror CI`**: a copy of `mirror` that tests `mirrorTests` only and launches Debug. The `mirror` scheme is unchanged, including its Release launch from PR #50.

## One-time setup (owner, in Xcode, about 10 minutes)

1. Open `mirror.xcodeproj` in Xcode with the `3.1.2` branch checked out (the `mirror-3.1.2` worktree, or `git switch 3.1.2`).
2. **Product → Xcode Cloud → Create Workflow…**, then pick the **mirror** app (bundle id `com.lokesh.mirror`; it already exists in App Store Connect).
3. When asked, **grant access to the GitHub repository** `lokii49/mirror`. Xcode opens App Store Connect to install the Xcode Cloud GitHub app on that repo. Allow only this repo.
4. Edit the default workflow:
   - **Name:** `3.1.2 CI`
   - **Environment:** the Xcode version that matches local (Xcode 27.1, or the newest 27.x offered). Clean builds on.
   - **Start condition:** *Branch Changes*, branch `3.1.2`; auto-cancel builds on new pushes.
   - **Actions:**
     - *Build*, scheme `mirror CI`, platform iOS.
     - *Test*, scheme `mirror CI`, platform iOS, destination *iPhone 17 (latest iOS)* simulator.
     - Optional: *Build*, scheme `mirror`, platform macOS, to catch Mac-only compile errors. Every fix so far was checked with a Release build on both platforms.
   - **Post-actions:** none. Archive, TestFlight and notarization are left out deliberately: releases stay manual, with the API-key upload method.
5. **Save**, then **Start Build** once to confirm the first run is green.

Signing is cloud-managed for build and test; nothing to configure. Check your included compute hours in App Store Connect → Xcode Cloud → Usage. A full local run of `mirror CI` on a simulator takes over 10 minutes; expect similar or longer per Xcode Cloud run.

## Continuing the backlog while the laptop is closed

Use a **Claude Code cloud session** (claude.ai/code, or `/schedule` for a routine) on `lokii49/mirror`, branch `3.1.2`. Cloud sessions run on Linux: **they can edit, commit and push, but can't build or run Xcode.** Xcode Cloud is the build and test check for their pushes.

Prompt to start a session:

> Work on branch `3.1.2` of lokii49/mirror. Follow `CLAUDE.md` (repo root) and read `.claude/3.1.2-backlog.md`. Take the next open item in order, starting with A15 (Talk It Out answers have no length cap; CLAUDE.md security rule 3: at most 10,000 characters sent to the local LLM, oldest content truncated first).
>
> For each item:
> - Write a failing Swift Testing test first, using synthetic text only.
> - Make the smallest fix, matching the surrounding code's style and comment density.
> - Get an advisor audit of the change.
> - Commit with a message explaining the defect and the fix, then push.
>
> You can't run Xcode here, so say so in the commit message ("not built locally; see Xcode Cloud"). After each push, poll the commit's checks with `gh` (e.g. `gh api repos/lokii49/mirror/commits/<sha>/check-runs`) until Xcode Cloud finishes. If it's red, read the check details, fix and push again. Stop after 3 red rounds on one item and write what failed in the backlog. Add the item to the backlog's "Fixed" section, marked "pending device verification".
>
> Stop and ask before A16, A19 or the B (translations) section: they need product decisions. Never touch release versions, App Store metadata or CloudKit schema.

After each push, the `3.1.2 CI` workflow builds and tests it. A red run is emailed to the owner and shown in App Store Connect → Xcode Cloud. The next session, cloud or laptop, reads that result before starting new work.

## When the laptop is back

1. `git pull` in `mirror-3.1.2`.
2. Check the latest `3.1.2 CI` runs are green.
3. Run the device evidence for the cloud-made commits, following `tools/testing/README.md`:
   - MN Dev on the 14 Pro, with the GGUF copied into the app container;
   - a negative control per fix;
   - the iPhone 13 for widget and iCloud items.
4. In the backlog, move each item from "pending device verification" to verified.
