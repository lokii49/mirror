import SwiftUI
import SwiftData
import BackgroundTasks
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UserNotifications
import WidgetKit
import RevenueCat

@main
struct mirrorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    // Foreground proactive generation task — cancelled immediately when app backgrounds
    // so GPU inference stops at the next Task.checkCancellation() in LocalLLMService.
    nonisolated(unsafe) static var activeGenerationTask: Task<Void, Never>?

    /// Starts `work` once a cancelled `previous` pass has finished. Coming back to the app cancels
    /// the running pre-generation and starts another; the cancelled one still holds its
    /// `InsightGenerationCoordinator` claim until it unwinds, so the new pass found the key taken
    /// and gave up, and nothing generated until the next activation (backlog A14; on Mac every app
    /// switch is an activation).
    static func afterCancelling(_ previous: Task<Void, Never>?, priority: TaskPriority = .background, _ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task(priority: priority) {
            await previous?.value
            guard !Task.isCancelled else { return }
            await work()
        }
    }
    // The one-time regrade of old digests/reports; cancelled on background like the task above.
    nonisolated(unsafe) static var regradeTask: Task<Void, Never>?

    var sharedModelContainer: ModelContainer = MirrorModelContainer.shared

    init() {
        PerfSignpost.beginLaunch()
        // Plaintext left by an archive export/import that was interrupted (crash, force quit).
        DispatchQueue.global(qos: .utility).async { ArchivePackage.removeStaleStaging() }
        #if os(macOS) && DEBUG
        if let dir = MacFormatPopoverRender.requestedDirectory {
            DispatchQueue.main.async { MacFormatPopoverRender.renderAndQuit(to: dir) }
        }
        #endif
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: "appl_OcfOuFibRNCALKDBSbAslQwJKQT")
        // Create it now, not on first use: its init writes the widgets' tier key, which has to
        // land before the app-active pass reloads the widget timelines.
        _ = SubscriptionService.shared
        UNUserNotificationCenter.current().delegate = MirrorNotificationDelegate.shared
        NotificationService.registerCategories()
        registerNightlyInsightsTask()
        configureNavigationBarAppearance()
        if MirrorModelContainer.isStoreAvailable {
            JournalSafety.shared.start(container: sharedModelContainer)
            WidgetSaveRefresher.shared.start(container: sharedModelContainer)
        }
        // Re-attach to a search-model download still running in its background session, so it
        // installs when it finishes even if Ask and Settings are never opened this launch.
        if SemanticSearchService.consent == .accepted, !SemanticSearchService.isModelOnDisk {
            _ = ModelDownloadManager.searchModel
        }
        #if os(macOS)
        // Global quick-capture shortcut. Not in harness runs: an unsigned copy shares the installed
        // app's bundle id and would take the combination from it.
        #if DEBUG
        let harnessRun = MacSnapshot.isRequested || PerfSeed.isRequested
        #else
        let harnessRun = false
        #endif
        if !harnessRun {
            MacGlobalHotKey.shared.start(container: sharedModelContainer)
            AppLockMacCovers.start()
        }
        #endif
        #if DEBUG
        if CloudKitSchemaSeed.isRequested, MirrorModelContainer.isStoreAvailable {
            CloudKitSchemaSeed.run(context: sharedModelContainer.mainContext)
        }
        if CloudKitSchemaSeed.isRemovalRequested, MirrorModelContainer.isStoreAvailable {
            CloudKitSchemaSeed.removeSeed(context: sharedModelContainer.mainContext)
        }
        #endif
        #if DEBUG
        // `--perfSeed=N`: fill the synthetic scratch store once (PerfSeed.swift). Before first frame.
        if PerfSeed.isRequested {
            PerfSignpost.interval("perfSeed") { PerfSeed.seedIfNeeded(into: sharedModelContainer.mainContext) }
            if GemmaMemoryProbe.isRequested {
                Task { @MainActor in await GemmaMemoryProbe.run() }
            } else if PerfSeed.draftRecoveryPhase != nil {
                Task { @MainActor in await PerfSeed.runDraftRecoveryCheck() }
            } else {
                Task { @MainActor in await PerfSeed.runEntriesScenario() }
            }
        }
        #endif
        #if DEBUG
        // See SampleData.seedPastNudges — InsightView's "Past reflections" section only
        // renders once real usage has accumulated a few days of history, so there was no way
        // to see/screenshot it without days of manual use. Opt-in via launch argument, DEBUG
        // only, never reachable in a release build.
        if ProcessInfo.processInfo.arguments.contains("--seedPastBriefings") {
            SampleData.seedPastNudges(into: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--clearPastBriefingsSamples") {
            SampleData.clearPastNudgeSamples(from: sharedModelContainer.mainContext)
        }
        // See SampleData.seedCurrentMonthBulk — MonthlyReportView only generates real
        // output once the current calendar month has >=20 real entries. Scratch-device
        // only (see 2.1.0-design-plan.md B2 notes): never run against a device with real
        // journal data, use `simctl clone` first.
        if ProcessInfo.processInfo.arguments.contains("--seedCurrentMonthBulk") {
            SampleData.seedCurrentMonthBulk(into: sharedModelContainer.mainContext)
        }
        // See SampleData.seedMonthlyReportSample — real 6-section generation is too slow to
        // finish inside a UI-test window on the simulator. Inserts a ready-made monthly
        // report so MonthlyReportView's loaded layout renders instantly. Scratch-device only.
        if ProcessInfo.processInfo.arguments.contains("--seedMonthlyReportSample") {
            SampleData.seedMonthlyReportSample(into: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--clearMonthlyReportSample") {
            SampleData.clearMonthlyReportSample(from: sharedModelContainer.mainContext)
        }
        // See SampleData.seedTodayReflection — the daily reflection card only shows
        // its loaded state (and thus the Sentinel source sheet) when a nudge
        // Insight exists for today. Seeds one plus a few recent moody entries so
        // InsightSignalSource's reconstruction has something to show. Scratch-device only.
        if ProcessInfo.processInfo.arguments.contains("--clearTodayReflectionSample") {
            SampleData.clearTodayReflectionSample(from: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--seedTodayReflection") {
            SampleData.seedTodayReflection(into: sharedModelContainer.mainContext)
        }
        // weekly digest + Ask cards also gate their source sheet on a
        // loaded Insight. These seed one of each for the current period (lean on
        // --seedTodayReflection's this-week entries for the reconstruction).
        // Scratch-device only.
        if ProcessInfo.processInfo.arguments.contains("--seedWeeklyDigestSample") {
            SampleData.seedWeeklyDigestSample(into: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--clearWeeklyDigestSample") {
            SampleData.clearWeeklyDigestSample(from: sharedModelContainer.mainContext)
        }
        // Prior-week digest only — drives InsightViewModel's `.previousWeek`
        // fallback (this week has no digest yet). Do NOT also seed this week's.
        if ProcessInfo.processInfo.arguments.contains("--seedPriorWeekDigestSample") {
            SampleData.seedPriorWeekDigestSample(into: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--seedAskSample") {
            SampleData.seedAskSample(into: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--clearAskSample") {
            SampleData.clearAskSample(from: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--seedRichInlineStylesSample") {
            SampleData.seedRichInlineStylesSample(into: sharedModelContainer.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("--clearRichInlineStylesSample") {
            SampleData.clearRichInlineStylesSample(from: sharedModelContainer.mainContext)
        }
        // Recovery/verification tool: a UI test run that taps the Classic/Sentinel picker
        // mutates real UserProfile.displayMode, same as a real user tap -- there's no simctl
        // "undo" for that once the test exits, and screenshot passes need both modes on
        // demand without a manual tap round-trip. Opt-in via launch arg
        // (--forceDisplayMode=classic or --forceDisplayMode=sentinel), DEBUG only.
        if let modeArg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--forceDisplayMode=") }),
           let mode = DisplayMode(rawValue: String(modeArg.dropFirst("--forceDisplayMode=".count))) {
            let context = sharedModelContainer.mainContext
            if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
                // Existing profile: only touch the theme, never onboardingComplete —
                // that's the first-run gate and this arg could be passed on a real device.
                profile.displayMode = mode
            } else {
                // Fresh/erased sim has no profile — make one so this arg also
                // skips onboarding for screenshot passes, not just sets the theme.
                let p = UserProfile()
                p.onboardingComplete = true
                p.displayMode = mode
                context.insert(p)
            }
            try? context.save()
        }
        // Screenshot passes need light/dark on demand without a Settings round-trip.
        // Writes the same AppStorage key the Appearance setting uses. DEBUG only.
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--forceAppearance=") }) {
            let value = String(arg.dropFirst("--forceAppearance=".count))
            if ["light", "dark", "system"].contains(value) {
                UserDefaults.standard.set(value, forKey: "mirrorAppearanceMode")
            }
        }
        // mirrorUITests relaunches the app per test method but the draft
        // (UserDefaults + DraftAttachmentStore) and every saved Entry/Insight
        // persist on-disk across launches — without this, WriteView tests
        // accumulate every prior test's typed text into one ballooning draft.
        // Opt-in via launch arg, DEBUG only, scratch-device only (wipes ALL
        // entries — never pass this against a device with real journal data).
        if ProcessInfo.processInfo.arguments.contains("--clearWriteTestState") {
            WriteView.clearAllDraftStorage()
            SampleData.clear(from: sharedModelContainer.mainContext)
        }
        // Design-review capture for MirrorNotificationContentExtension: fires the real
        // "ready" nudge notification (matching category, App Group mood) a few seconds
        // after launch so a UI test can background the app and screenshot the expanded
        // Content Extension. Scratch-device only, DEBUG only — delete once screenshots
        // are captured, this is not a regression test fixture.
        if ProcessInfo.processInfo.arguments.contains("--scheduleTestNudge") {
            let defaults = UserDefaults(suiteName: WidgetShared.appGroupID)
            let today = DateHelpers.dayIdentifier(for: Date())
            defaults?.set(today, forKey: "widget.nudge.date")
            defaults?.set("Content", forKey: "widget.nudge.mood")
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                let content = UNMutableNotificationContent()
                content.title = "mirror"
                content.body = "Your daily reflection is ready."
                content.sound = .default
                content.categoryIdentifier = "mirror.dailyNudge"
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
                let request = UNNotificationRequest(identifier: "mirror.testNudge", content: content, trigger: trigger)
                center.add(request)
            }
        }
        #endif
    }

    private func configureNavigationBarAppearance() {
        #if os(iOS)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = UIColor(MirrorTheme.inkBorder)
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if MirrorModelContainer.isStoreAvailable {
                    ContentView()
                } else {
                    StoreUnavailableView()
                }
            }
            #if os(macOS)
            // An open main window takes widget and notification links (mirror://...) itself.
            // Without this, macOS opened another main window for every widget click (2026-10-09).
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            #endif
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        // Only the main window group handles links; it opens a window only when none is open.
        .handlesExternalEvents(matching: ["*"])
        .commands { MirrorMacCommands() }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        #endif
        .onChange(of: scenePhase) { _, phase in
            #if os(iOS)
            // App Lock: away starts in the background only (the Face ID prompt itself makes the
            // app inactive); inactive and background hide the content from the app switcher.
            switch phase {
            case .background:
                AppLock.shared.didLeave()
                AppLock.shared.setPrivacyCover(true)
            case .inactive:
                AppLock.shared.setPrivacyCover(true)
            case .active:
                AppLock.shared.setPrivacyCover(false)
                AppLock.shared.didReturn()
            @unknown default:
                break
            }
            #endif
            // Store couldn't be opened: sharedModelContainer is an empty stand-in, so nothing
            // below (generation, cleanup passes, reminders) has anything real to work on.
            guard MirrorModelContainer.isStoreAvailable else { return }
            #if DEBUG && os(macOS)
            // Snapshot mode renders sample data only: no generation, cleanup passes or permission prompts.
            if MacSnapshot.isRequested { return }
            #endif
            #if DEBUG
            // Perf baseline runs an unsigned copy with the real bundle id: it shares the system's
            // notification center with the installed app, so it must not touch reminders, and it
            // skips the background branch (which schedules notifications) entirely.
            let perfRun = PerfSeed.isRequested
            if perfRun && phase == .background { return }
            #else
            let perfRun = false
            #endif
            switch phase {
            case .active:
                // Request notification permission for users who completed onboarding before
                // the permission prompt was added (status .notDetermined = never asked).
                if !perfRun {
                    Task {
                        await requestNotificationPermissionIfNeeded()
                        migrateToUnifiedDailyReminder()
                        await reArmUserReminders()
                    }
                }
                // Backfill the rate-us gate for users already past 5 entries
                // (including anyone who only saw Apple's raw prompt on an older
                // build). Idempotent — one-shot flag, self-guards on count.
                Task { @MainActor in
                    PerfSignpost.interval("active.reviewPrompt") {
                        ReviewRequestManager.requestIfEntryMilestoneReached(context: sharedModelContainer.mainContext)
                    }
                }
                // One-time move of daily mood check-ins from the legacy encrypted
                // UserDefaults blob into SwiftData (so they sync via CloudKit).
                // Idempotent, one-directional, keeps the blob intact.
                Task { @MainActor in
                    PerfSignpost.interval("active.moodCheckInMigration") {
                        MoodCheckInMigration.runIfNeeded(context: sharedModelContainer.mainContext)
                    }
                }
                // iCloud status, restore-from-device offer, and cleanup of restored copies
                // whose originals CloudKit has since delivered.
                PerfSignpost.interval("active.journalSafety") { JournalSafety.shared.appDidBecomeActive() }
                // One-time: re-clean daily reflections cached before the
                // announce-line / "friend" vocative strip landed (076b9f5).
                Task { @MainActor in
                    PerfSignpost.interval("active.cachedInsightRepair") {
                        CachedInsightRepair.runIfNeeded(context: sharedModelContainer.mainContext)
                    }
                }
                // One-time: retroactively flag already-cached nudges/digests/reports that
                // fabricated content slipped past the pre-fix grounding check (see
                // UngroundedInsightCleanup's doc comment).
                Task { @MainActor in
                    PerfSignpost.interval("active.ungroundedCleanup") {
                        UngroundedInsightCleanup.runIfNeeded(context: sharedModelContainer.mainContext)
                    }
                }
                // One-time: recount word totals for Japanese/Chinese entries (see CJKWordCountRecount).
                Task { @MainActor in
                    PerfSignpost.interval("active.cjkRecount") {
                        CJKWordCountRecount.runIfNeeded(context: sharedModelContainer.mainContext)
                    }
                }
                // One-time: remove list markers the old editor saved next to mid-text photos
                // (see PhotoMarkerRepair).
                Task { @MainActor in
                    PerfSignpost.interval("active.photoMarkerRepair") {
                        PhotoMarkerRepair.runIfNeeded(context: sharedModelContainer.mainContext)
                    }
                }
                // One-time: rewrite the latest digest/report if the pre-grammar Gemma path wrote it.
                mirrorApp.regradeTask?.cancel()
                mirrorApp.regradeTask = Task(priority: .background) { @MainActor in
                    await PreGrammarInsightRegrade.runIfNeeded(context: sharedModelContainer.mainContext)
                }
                // Proactively generate so content is ready before user opens Insights tab.
                // Store task so we can cancel it immediately if the app backgrounds.
                let previousGeneration = mirrorApp.activeGenerationTask
                previousGeneration?.cancel()
                // Not in perf runs: it loads the model and can post a "reflection ready" notification.
                if !perfRun {
                    mirrorApp.activeGenerationTask = mirrorApp.afterCancelling(previousGeneration) {
                        await PerfSignpost.interval("active.preGenerateInsights") { await preGenerateInsightsIfNeeded() }
                    }
                } else {
                    mirrorApp.activeGenerationTask = nil
                }
            case .background:
                // Cancel any foreground GPU generation immediately — LocalLLMService will
                // stop at the next Task.checkCancellation() and the nightly BGProcessingTask
                // will retry on CPU.
                // Cancelled but kept: the next .active pass waits for it to unwind and release its
                // claim (A14). Home and back is the common way back in on iPhone.
                mirrorApp.activeGenerationTask?.cancel()
                mirrorApp.regradeTask?.cancel()
                mirrorApp.regradeTask = nil
                WidgetSaveRefresher.shared.flushNow()
                scheduleDailyNudgeFallback()
                generateDailyNudgeInBackgroundIfNeeded()
                scheduleNightlyInsights()
                // A true backgrounding, unlike an .active->.inactive->.active flicker from a
                // system permission dialog mid-launch (see UngroundedInsightCleanup's deferral,
                // which needs a real "this is a later session" signal, not just another .active
                // call within the same cold launch).
                UngroundedInsightCleanup.recordBackgrounding()
                // Refresh the on-device journal backup — if the user now turns iCloud off
                // for the app, this copy is what survives the purge (LocalJournalBackup).
                JournalSafety.shared.appDidEnterBackground()
                // Give any remaining in-flight generation (BGProcessingTask path) ~30s grace.
                extendBackgroundForPendingGeneration()
            default:
                break
            }
        }
        // One app refresh for everything the nightly task does, for devices that don't charge
        // overnight (the nightly BGProcessingTask needs power): see runDailyNudgeFallback.
        #if os(iOS)
        .backgroundTask(.appRefresh("com.lokesh.mirror.dailyNudge")) {
            await runDailyNudgeFallback()
        }
        #endif

        #if os(macOS)
        MenuBarExtra {
            MacQuickCaptureView()
                .modelContainer(sharedModelContainer)
        } label: {
            Image("mac-pen").renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("New Entry", id: "new-entry") {
            MacNewEntryWindow()
        }
        .handlesExternalEvents(matching: [])
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 800)

        WindowGroup("Entry", id: "entry", for: UUID.self) { $entryID in
            MacEntryWindow(entryID: entryID)
        }
        .handlesExternalEvents(matching: [])
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 800)

        Settings {
            MacSettingsRoot()
                .modelContainer(sharedModelContainer)
        }
        #endif
    }

    // MARK: - BGProcessingTask: nightly at ~3AM while charging

    private func registerNightlyInsightsTask() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.lokesh.mirror.nightlyInsights",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            guard MirrorModelContainer.isStoreAvailable else {
                processingTask.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                await mirrorApp.runNightlyInsights(container: self.sharedModelContainer)
            }
            // setTaskCompleted must be called exactly once: the expiration handler and the
            // work-finished path can fire together.
            let completion = RunOnce()
            processingTask.expirationHandler = {
                work.cancel()
                completion.run { processingTask.setTaskCompleted(success: false) }
            }
            Task {
                _ = await work.result
                scheduleNightlyInsights()  // always re-schedule, even if expired
                completion.run { processingTask.setTaskCompleted(success: true) }
            }
        }
        #elseif os(macOS)
        // Mac has no BGTaskScheduler. A Mac left open overnight gets the same pass from a
        // background activity that checks hourly and runs once in the small hours; a Mac that
        // is asleep or closed catches up through the app-active path on the next launch.
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.lokesh.mirror.nightlyInsights")
        scheduler.repeats = true
        scheduler.interval = 60 * 60
        scheduler.tolerance = 15 * 60
        scheduler.qualityOfService = .utility
        let container = sharedModelContainer
        scheduler.schedule { completion in
            guard MirrorModelContainer.isStoreAvailable,
                  Self.macNightlyIsDue(now: Date(), lastRun: UserDefaults.standard.object(forKey: Self.macNightlyLastRunKey) as? Date) else {
                completion(.finished)
                return
            }
            Task { @MainActor in
                UserDefaults.standard.set(Date(), forKey: Self.macNightlyLastRunKey)
                await mirrorApp.runNightlyInsights(container: container)
                completion(.finished)
            }
        }
        Self.macNightlyScheduler = scheduler
        #endif
    }

    #if os(macOS)
    private static var macNightlyScheduler: NSBackgroundActivityScheduler?
    private static let macNightlyLastRunKey = "macNightlyInsightsLastRun"

    /// True from 3 AM to 6 AM local time when the pass has not run since the last 3 AM, matching
    /// the iPhone task's "around 3 AM, once a night".
    static func macNightlyIsDue(now: Date, lastRun: Date?, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        guard (3..<6).contains(hour) else { return false }
        let threeAM = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: now) ?? now
        guard let lastRun else { return true }
        return lastRun < threeAM
    }
    #endif

    private func scheduleNightlyInsights() {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: "com.lokesh.mirror.nightlyInsights")
        // Only run while charging → no thermal impact on the user.
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        // Target ~3AM local time; iOS fires it opportunistically after that.
        request.earliestBeginDate = next3AM()
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    private func next3AM() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 3
        components.minute = 0
        components.second = 0
        guard var target = calendar.date(from: components) else { return Date() }
        if target <= Date() {
            target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
        }
        return target
    }

    // MARK: - Nightly task body (static so the BGTask closure can call it without capturing self)

    @MainActor
    private static func runNightlyInsights(container: ModelContainer) async {
        let context = container.mainContext
        await runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)

        // Refresh contextual nudge notification so it reflects tonight's generation result.
        // Covers the case where no writing happened: resets to "write" message so user
        // isn't reminded of a stale "ready" from yesterday.
        if SubscriptionService.shared.isSubscribed {
            let insightReady = hasDailyNudgeForToday(context: context)
            let hasWrittenToday = hasEntryToday(context: context)
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            await NotificationService.rescheduleContextualNudge(
                hasWrittenToday: hasWrittenToday,
                insightReady: insightReady,
                hour: hour,
                minute: minute
            )
        }

        // Weekly digest only on Sunday
        if DateHelpers.isSunday() {
            await runWeeklyDigestIfNeeded(context: context)
        }
        // Monthly report (Deep only): last 7 days of the month, 10+ entries (the runner's gates)
        await runMonthlyReportIfNeeded(context: context)
        // Fill in moods the save-time auto-detect missed, then check alerts
        await backfillMissingMoodsIfNeeded(context: context)
        // Mood alert check every night (Deep only)
        await checkMoodAlertIfNeeded(context: context)
    }

    // MARK: - Proactive generation on app active

    @MainActor
    private func preGenerateInsightsIfNeeded() async {
        // Empty in-memory stand-in when the journal store couldn't be opened: nothing to do.
        guard MirrorModelContainer.isStoreAvailable else { return }
        let context = sharedModelContainer.mainContext
        await mirrorApp.runDailyNudgeIfNeeded(context: context)
        mirrorApp.updateWidgetHeatmaps(context: context)
        mirrorApp.syncNudgeToWidget(context: context)
        // Catch-all for the two insight widgets: a digest/report generated in a
        // previous session or served from cache never hits the write sites above,
        // same reason syncNudgeToWidget exists.
        WidgetBridge.syncWeeklyDigest(from: context)
        WidgetBridge.syncMonthlyReport(from: context)
        // An erase on another device leaves this one's widget text otherwise.
        WidgetBridge.clearIfJournalEmpty(context: context)

        // Update the daily nudge notification to reflect current state.
        // Content resets on every app open so the message matches today's context.
        if SubscriptionService.shared.isSubscribed {
            let insightReady = mirrorApp.hasDailyNudgeForToday(context: context)
            let hasWrittenToday = mirrorApp.hasEntryToday(context: context)
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            await NotificationService.rescheduleContextualNudge(
                hasWrittenToday: hasWrittenToday,
                insightReady: insightReady,
                hour: hour,
                minute: minute
            )
        }

        // Weekly digest: generate on Sundays proactively (fallback if nightly BGProcessingTask missed)
        if DateHelpers.isSunday() {
            await mirrorApp.runWeeklyDigestIfNeeded(context: context)
        }
        // Monthly report (Deep only): last 7 days of the month, 10+ entries (the runner's gates).
        await mirrorApp.runMonthlyReportIfNeeded(context: context)
        // Fill in moods the save-time auto-detect missed, then check alerts
        await mirrorApp.backfillMissingMoodsIfNeeded(context: context)
        await mirrorApp.checkMoodAlertIfNeeded(context: context)
    }

    // MARK: - Shared generation helpers (also called from BGAppRefreshTask fallback)

    /// At or past the user's reflection time today, hour and minute. It used to compare the hour
    /// only, so a reflection time of 8:30 opened at 8:00.
    static func isAtOrPastReflectionTime(_ now: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0, c.minute ?? 0) >= (hour, minute)
    }

    /// Today's real reflection allows one more (InsightService.allowsAnotherReflectionToday),
    /// judged from today's readable entries and the last failed extra attempt. Only today's
    /// entries are fetched (and decrypted).
    @MainActor
    static func anotherReflectionAllowed(after newestToday: Insight, context: ModelContext) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let todayEntries = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt >= startOfToday }))) ?? []
        return InsightService.allowsAnotherReflectionToday(
            todaysReflectionAt: newestToday.generatedAt,
            todayEntryDates: todayEntries.filter(InsightService.hasReadableContext).map(\.createdAt),
            lastFailedExtraAttempt: UserDefaults.standard.object(forKey: extraReflectionFailedAttemptKey) as? Date
        )
    }

    /// Whether today's rows leave room for a reflection now, by the same first check
    /// runDailyNudgeIfNeeded makes: none yet, the newest is the fallback, or one more is allowed.
    /// The background catch-up used `!hasDailyNudgeForToday`, which skipped the same-day second
    /// reflection when the user saved and left the app right away.
    @MainActor
    static func dailyReflectionMayBeDue(context: ModelContext) -> Bool {
        let today = DateHelpers.dayIdentifier(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<Insight>(predicate: #Predicate { $0.periodIdentifier == today }))) ?? []
        guard let newestToday = rows.filter({ $0.type == .dailyNudge }).max(by: { $0.generatedAt < $1.generatedAt }),
              !InsightService.isUngroundedFallback(newestToday.content) else { return true }
        return anotherReflectionAllowed(after: newestToday, context: context)
    }

    @MainActor
    static func runDailyNudgeIfNeeded(context: ModelContext, bypassTimeGate: Bool = false, userInitiatedRetry: Bool = false) async {
        let today = DateHelpers.dayIdentifier(for: Date())
        let coordinatorKey = "nudge_\(today)"

        // Check SwiftData cache
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        let todayInsights = (try? context.fetch(descriptor)) ?? []
        // A fallback insight isn't a nudge that succeeded — it's the absence of one. Counting ANY
        // real nudge as "done for today" used to make the 3AM BGProcessingTask (charging, idle,
        // precisely the low-pressure window a retry has the best shot in) — and a user's own
        // "Try Again" tap — skip today entirely even when the NEWEST row for today is the
        // fallback (e.g. a real nudge generated this morning, then a later re-gen off newer
        // entries produced the fallback). Must match resolvedNudgeState's own "newest wins"
        // read: only skip when the newest row for today is real.
        //
        // A real one blocks the rest of today unless it was built only from earlier days and the
        // user has written today since (InsightService.allowsAnotherReflectionToday, 2026-09-28):
        // otherwise writing after an evening-before reflection waited a day, and was skipped
        // entirely when the next day's writing came first. Only today's entries are fetched
        // (and decrypted) for that check.
        var isExtraReflection = false
        let newestTodayNudge = todayInsights
            .filter({ $0.type == .dailyNudge })
            .max(by: { $0.generatedAt < $1.generatedAt })
        if let newestToday = newestTodayNudge,
           !InsightService.isUngroundedFallback(newestToday.content) {
            guard anotherReflectionAllowed(after: newestToday, context: context) else {
                #if DEBUG
                print("[nudge] blocked: newestToday-is-real")
                #endif
                return
            }
            isExtraReflection = true
        }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Real device case (2026-09-25): a background pass running while the device is locked can
        // hit a Keychain read failure (KeychainManager's documented errSecInteractionNotAllowed),
        // which Entry.text silently turns into "". formatEntries then drops that entry from the
        // prompt entirely, and isUngrounded/sharesNoWordWithRecent/openingIsUngrounded all
        // early-return "not ungrounded" on an empty source word set — so a Gemma nudge generated
        // against a blank "Recent entries:" block sails through every guard.
        // InsightService.hasReadableContext, not the narrower textDecryptionFailed — matches
        // exactly what generateNudge itself filters on, so this count gate and that function agree
        // on which entries count as "readable" (a photo-only or failed-voice-transcription entry
        // isn't a decryption failure but is just as unreadable). Filtered before the count gate so
        // unreadable entries don't count toward "enough to generate from" either.
        let entries = ((try? context.fetch(entryDescriptor)) ?? []).filter(InsightService.hasReadableContext)
        guard entries.count >= 3 else {
            #if DEBUG
            print("[nudge] blocked: entries<3")
            #endif
            return
        }
        // The reflection is saved encrypted: don't generate one that would be stored in plaintext.
        guard MirrorEncryption.canEncrypt(creatingIfNeeded: false) else {
            #if DEBUG
            print("[nudge] blocked: key-unavailable")
            #endif
            return
        }

        // First nudge is free; subsequent require subscription. A fallback doesn't count as
        // "seen" — otherwise a free user whose very first attempt happened to fail the grounding
        // check would be locked behind the paywall for a nudge they never actually received.
        let allInsightsDescriptor = FetchDescriptor<Insight>()
        let allInsights = (try? context.fetch(allInsightsDescriptor)) ?? []
        let hasSeenFirst = allInsights.contains { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
        if hasSeenFirst && !SubscriptionService.shared.isSubscribed {
            #if DEBUG
            print("[nudge] blocked: paywall")
            #endif
            return
        }

        // Only generate if there are entries written after the last REAL nudge. No new writing →
        // no new reflection. A fallback is excluded from "last nudge" here too — retrying it
        // against the same entries that produced it is exactly the point, not blocked by "nothing
        // new since then." `userInitiatedRetry` bypasses this gate entirely — it exists to stop
        // *automatic* regeneration churn (nightly task, app-open pre-gen) when nothing new was
        // written, not to block a deliberate Try Again tap. Without this, a user whose single
        // real nudge happened to generate after their most recent entry (e.g. an overnight
        // background pass) could tap Try Again forever and silently get nothing — same pattern
        // digest/monthly's `forceRegenerate` already uses for their own explicit-retry paths.
        if !userInitiatedRetry, let lastNudge = allInsights
            .filter({ $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) })
            .max(by: { $0.generatedAt < $1.generatedAt }) {
            guard entries.contains(where: { $0.createdAt > lastNudge.generatedAt }) else {
                #if DEBUG
                print("[nudge] blocked: no-new-entry-since-last-real-nudge")
                #endif
                return
            }
        }

        // Today's newest is a fallback: retry automatically only once what it reads has changed.
        let retrySignature = InsightService.fallbackRetrySignature(
            day: today, recent: InsightService.dailyNudgeContext(from: entries, asOf: Date()).recent
        )
        guard InsightService.allowsRetryAfterFallback(
            newestTodayIsFallback: newestTodayNudge.map { InsightService.isUngroundedFallback($0.content) } ?? false,
            storedSignature: UserDefaults.standard.string(forKey: fallbackRetrySignatureKey),
            signature: retrySignature,
            userInitiatedRetry: userInitiatedRetry
        ) else {
            #if DEBUG
            print("[nudge] blocked: fallback-unchanged-writing")
            #endif
            return
        }

        // Respect the user's preferred nudge time so a full day of writing informs the reflection.
        // Nightly background tasks bypass this gate — they're the fallback for users who never
        // opened the app at their preferred hour.
        if !bypassTimeGate {
            guard isAtOrPastReflectionTime(Date(), hour: NotificationService.nudgeHour(), minute: NotificationService.nudgeMinute()) else {
                #if DEBUG
                print("[nudge] blocked: before-nudge-hour")
                #endif
                return
            }
        }

        guard modelAvailable() else {
            #if DEBUG
            print("[nudge] blocked: model-unavailable")
            #endif
            return
        }
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else {
            #if DEBUG
            print("[nudge] blocked: coordinator-claimed")
            #endif
            return
        }
        #if DEBUG
        print("[nudge] proceeding to generate")
        #endif
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        // Excludes fallback rows — same "fallback doesn't count as a real one" reasoning
        // InsightViewModel.hasSeenFirstNudge and InsightView.hasSeenMoreThanOneNudge already
        // use. Without this, a user whose recent dailyNudge rows are mostly fallback boilerplate
        // (the exact population the retry-loop/dedup work this session was about) gets
        // priorNudgeOpenings fed "MirrorNotes couldn't find today's reflection..." instead of
        // real prior openings, wasting the .prefix(4) window on content there's no reason to
        // avoid repeating and weakening the actual cross-day anti-repetition check.
        let recentNudges = allInsights
            .filter { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
            .sorted { $0.generatedAt > $1.generatedAt }
            .prefix(4)
            .map(\.content)

        // The reflection's plan reads its source entries' moods (the mood line in the prompt, the
        // mood-matched fixed text outside English). A save-time detection may still be running
        // (joined here), or may have died with the app (Siri saves, a quick background): fill
        // them in first. Only the entries the reflection reads, so at most three.
        await MoodAutoDetector.shared.fillMissingMoods(
            for: InsightService.dailyNudgeContext(from: entries, asOf: Date()).recent,
            context: context
        )

        do {
            let (text, engine, degraded) = try await InsightService.generateNudge(entries: entries, recentNudges: Array(recentNudges))
            #if DEBUG
            print("[nudge] generateNudge returned: degraded=\(degraded) isFallbackText=\(InsightService.isUngroundedFallback(text)) engine=\(engine)")
            #endif
            // Today already has a real reflection on the card; a "couldn't confirm" row would
            // replace it (newest wins) and push it out of sight. Keep it, and try again only
            // after more writing. A throw or cancellation isn't recorded: it retries on the next
            // trigger, like a first reflection.
            if isExtraReflection && InsightService.isUngroundedFallback(text) {
                UserDefaults.standard.set(Date(), forKey: extraReflectionFailedAttemptKey)
                return
            }
            let insight = Insight(type: .dailyNudge, content: text, periodIdentifier: today, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            if InsightService.isUngroundedFallback(text) {
                UserDefaults.standard.set(retrySignature, forKey: fallbackRetrySignatureKey)
            } else {
                UserDefaults.standard.removeObject(forKey: fallbackRetrySignatureKey)
            }
            // Real device case (2026-09-20): the widget has no groundingFallback UI like the
            // in-app card does — it just renders whatever string it's handed. Writing `text`
            // unconditionally put the canned "couldn't confirm this reflection" sentence on the
            // home screen looking like a real nudge, with no retry affordance there at all. Only
            // sync the widget on a real result; a fallback leaves the widget showing whatever
            // real nudge it last had (or nothing), same as the in-app UI never overwrites a real
            // card with a fallback in place.
            if !InsightService.isUngroundedFallback(text) {
                let wDefaults = UserDefaults(suiteName: WidgetShared.appGroupID)
                wDefaults?.set(InsightService.nudgeTextForOutsideApp(text), forKey: "widget.nudge.text")
                wDefaults?.set(today, forKey: "widget.nudge.date")
                // The day it's about (the newest readable entry's), so the widget can keep an
                // evening-before reflection next morning without resurfacing older ones.
                wDefaults?.set(entries.first.map { DateHelpers.dayIdentifier(for: $0.createdAt) }, forKey: "widget.nudge.aboutDate")
                if let todaysMood = entries.first(where: { DateHelpers.dayIdentifier(for: $0.createdAt) == today })?.mood {
                    wDefaults?.set(todaysMood, forKey: "widget.nudge.mood")
                } else {
                    wDefaults?.removeObject(forKey: "widget.nudge.mood")
                }
                WidgetCenter.shared.reloadTimelines(ofKind: "MirrorNudgeWidget")
            }
            let hour = NotificationService.nudgeHour()
            let minute = NotificationService.nudgeMinute()
            if SubscriptionService.shared.isSubscribed {
                // Update the repeating nudge content to "ready" so it fires correctly at nudge time.
                // No second one-time notification — that would double-fire at the same minute.
                // `insightReady: !degraded` — a nudge that tripped the grounding/repeat guard is
                // still saved and shown as a card (a flawed reflection beats none), but the push
                // falls back to the generic "come check" body instead of promising a "ready"
                // reflection the guard couldn't confirm is actually good.
                let previewEnabled = UserDefaults.standard.bool(forKey: "nudgePreviewEnabled")
                await NotificationService.rescheduleContextualNudge(
                    hasWrittenToday: true,
                    insightReady: !degraded,
                    hour: hour,
                    minute: minute,
                    previewText: previewEnabled ? text : nil
                )
            } else {
                // First nudge for free users — one-time hook to drive paywall conversion.
                // NOT gated on `degraded`: the Insight above is already saved, which makes
                // `hasSeenFirst` true on every later call once it's a REAL nudge — a flawed
                // first nudge still beats never showing the paywall hook at all. Can fire more
                // than once now: `hasSeenFirst` excludes fallback content (see its own comment
                // above), so a fallback first attempt followed by a successful Try Again lands
                // here twice. Harmless — scheduleFirstNudgeHook replaces its one pending request
                // by a fixed identifier rather than adding a second, so this only ever re-arms
                // the same one-time notification, never duplicates it.
                await NotificationService.scheduleFirstNudgeHook(hour: hour, minute: minute)
            }
        } catch {
            #if DEBUG
            print("[nudge] generateNudge threw: \(type(of: error))")
            #endif
            /* Non-fatal — InsightView.task will retry when user navigates there */
        }
    }

    // Both of these feed "insightReady" into push-notification copy that promises a real
    // reflection — a fallback insight must not count, or the push claims a reflection is ready
    // when all that's actually there is the "couldn't confirm" message. Also why this reads the
    // NEWEST matching insight rather than the first: a retried fallback inserts a second row for
    // today rather than deleting the first (same non-destructive pattern weekly digest/monthly
    // report already use, since a CloudKit-synced deletion can hand a second device a tombstoned
    // object), so today can briefly hold two dailyNudge rows.
    @MainActor
    static func hasDailyNudgeForToday(context: ModelContext) -> Bool {
        let today = DateHelpers.dayIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        let todayInsights = (try? context.fetch(descriptor)) ?? []
        return todayInsights.contains { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
    }

    @MainActor
    static func todaysDailyNudgeText(context: ModelContext) -> String? {
        let today = DateHelpers.dayIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        let todayInsights = (try? context.fetch(descriptor)) ?? []
        return todayInsights
            .filter { $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) }
            .max { $0.generatedAt < $1.generatedAt }?.content
    }

    @MainActor
    static func hasEntryToday(context: ModelContext) -> Bool {
        let start = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.createdAt >= start }
        )
        return ((try? context.fetch(descriptor)) ?? []).count > 0
    }

    @MainActor
    static func runWeeklyDigestIfNeeded(context: ModelContext) async {
        let thisWeek = DateHelpers.digestWeekIdentifier(for: DateHelpers.now())
        let coordinatorKey = "digest_\(thisWeek)"

        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == thisWeek }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        // Newest wins — a stale digest is superseded by a fresh row, not deleted
        // (deleting a CloudKit-synced Insight can hand a second device a tombstoned
        // object mid-sync). Same non-destructive approach the monthly report uses.
        let cachedDigest = existing
            .filter { $0.type == .weeklyDigest }
            .max { $0.generatedAt < $1.generatedAt }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Same locked-device decrypt-failure guard as runDailyNudgeIfNeeded — see its comment.
        let entries = ((try? context.fetch(entryDescriptor)) ?? []).filter(InsightService.hasReadableContext)
        // Digest covers the current week only — gate on this week's entries, not lifetime.
        let weekEntries = entries.filter { DateHelpers.digestWeekIdentifier(for: $0.createdAt) == thisWeek }
        guard weekEntries.count >= InsightService.weeklyDigestMinimumWeekEntries,
              SubscriptionService.shared.isSubscribed else { return }

        // Already have this week's digest — regenerate only once it's gone stale
        // (24h cooldown elapsed AND newer entries since), else nothing to do.
        if let cached = cachedDigest {
            guard InsightService.weeklyDigestIsStale(
                generatedAt: InsightService.stalenessBaseline(cachedAt: cached.generatedAt, .weeklyDigest, period: thisWeek),
                newestWeekEntry: weekEntries.first?.createdAt  // entries are sorted newest-first
            ) else { return }
        }

        guard modelAvailable(), MirrorEncryption.canEncrypt(creatingIfNeeded: false) else { return }
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        do {
            let (text, engine) = try await InsightService.generateWeeklyDigest(weekEntries: weekEntries, allEntries: entries)
            if InsightService.keepsRealRowOverFallback(newText: text, cachedContent: cachedDigest?.content) {
                InsightService.recordKeptRealRow(.weeklyDigest, period: thisWeek)
                return
            }
            let insight = Insight(type: .weeklyDigest, content: text, periodIdentifier: thisWeek, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            WidgetBridge.syncWeeklyDigest(from: context)
            // scheduleWeeklyDigest is the sole fire — no separate one-time notification
            // to avoid double-banner on Sunday at 7am.
            await NotificationService.scheduleWeeklyDigest()
        } catch { /* Non-fatal */ }
    }

    // MARK: - Monthly Report (Deep only)

    @MainActor
    static func runMonthlyReportIfNeeded(context: ModelContext) async {
        // Cheap gates first: this runs on every app refresh, and everything below fetches and
        // decrypts the whole journal.
        guard DateHelpers.isInLastWeekOfMonth(), SubscriptionService.shared.isDeep else { return }
        let thisMonth = DateHelpers.monthIdentifier(for: DateHelpers.now())
        let coordinatorKey = "monthlyReport_\(thisMonth)"

        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == thisMonth }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        // Newest wins, same non-destructive pattern as runWeeklyDigestIfNeeded's cachedDigest —
        // was `guard !existing.contains(where: { $0.type == .monthlyReport })`, existence-only
        // with no staleness re-check, unlike its weekly sibling. A month whose first background
        // attempt landed a grounding-fallback (same non-destructive insert-new-row-per-retry
        // pattern as daily nudge/weekly digest) could never get a second automatic attempt from
        // this nightly pass for the rest of the month, even after the 24h cooldown elapsed and
        // new entries were written — the exact case weeklyDigestIsStale exists to handle for
        // digests, just never applied here. weeklyDigestIsStale's own logic (24h cooldown +
        // newer entry since) has nothing digest-specific in it, so reused directly rather than
        // duplicating it into a monthly-named copy.
        let cachedReport = existing
            .filter { $0.type == .monthlyReport }
            .max { $0.generatedAt < $1.generatedAt }

        let entryDescriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // Same locked-device decrypt-failure guard as runDailyNudgeIfNeeded — see its comment.
        let allEntries = ((try? context.fetch(entryDescriptor)) ?? []).filter(InsightService.hasReadableContext)
        let cal = Calendar.current
        let now = DateHelpers.now()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let monthEntries = allEntries.filter { $0.createdAt >= monthStart }

        if let cachedReport {
            guard InsightService.weeklyDigestIsStale(
                generatedAt: InsightService.stalenessBaseline(cachedAt: cachedReport.generatedAt, .monthlyReport, period: thisMonth),
                newestWeekEntry: monthEntries.first?.createdAt  // entries are sorted newest-first
            ) else { return }
        }

        // Same last-week-of-month gate as InsightViewModel.loadMonthlyReport (see its comment) —
        // this background pass must not generate early just because entries happen to be there.
        guard DateHelpers.isInLastWeekOfMonth(now),
              monthEntries.count >= InsightService.monthlyReportMinimumEntries,
              SubscriptionService.shared.isDeep else { return }
        guard modelAvailable(), MirrorEncryption.canEncrypt(creatingIfNeeded: false) else { return }
        guard InsightGenerationCoordinator.shared.claim(key: coordinatorKey) else { return }
        defer { InsightGenerationCoordinator.shared.release(key: coordinatorKey) }

        do {
            let (text, engine) = try await InsightService.generateMonthlyReport(monthEntries: monthEntries, allEntries: allEntries)
            if InsightService.keepsRealRowOverFallback(newText: text, cachedContent: cachedReport?.content) {
                InsightService.recordKeptRealRow(.monthlyReport, period: thisMonth)
                return
            }
            let insight = Insight(type: .monthlyReport, content: text, periodIdentifier: thisMonth, generatedByEngine: engine)
            context.insert(insight)
            try context.save()
            WidgetBridge.syncMonthlyReport(from: context)
            await NotificationService.scheduleMonthlyReportReminder()
        } catch { /* Non-fatal */ }
    }

    // MARK: - Model availability

    // Was its own Gemma-only check (bundled-resource or downloaded-file existence) — never
    // consulted FoundationModelEngine.isAvailable, so on an FM-capable device (iOS 26+, Apple
    // Intelligence on, eligible hardware) daily nudge/weekly digest/monthly report generation
    // would gate on downloading Gemma even though FM alone is enough to generate immediately,
    // no download needed. LocalLLMService.isModelAvailable already ORs in FM correctly (see
    // backfillMissingMoodsIfNeeded above, which used it right from the start) — delegate to
    // that single source of truth instead of a second, incomplete copy of the same check.
    static func modelAvailable() -> Bool {
        LocalLLMService.isModelAvailable
    }

    // MARK: - Mood Alert (Deep only — 3+ recent negative-mood days)

    private static let moodAlertCooldownKey = "mirror.lastMoodAlertSent"
    /// When a second same-day reflection last came back as the fallback (see
    /// InsightService.allowsAnotherReflectionToday). Per device, like the other generation state.
    static let extraReflectionFailedAttemptKey = "mirror.nudge.extraReflectionFailedAttempt"
    /// `InsightService.fallbackRetrySignature` of the writing today's fallback reflection read.
    static let fallbackRetrySignatureKey = "mirror.nudge.fallbackRetrySignature"

    // MARK: - Mood backfill
    //
    // The save-time auto-detect in WriteView is fire-and-forget: if the app is
    // suspended right after saving (the common case), the LLM task dies and the
    // entry stays mood-less forever. This pass retries on app-active and nightly.

    private static var isBackfillingMoods = false
    private static let moodBackfillWindowDays = 14
    private static let moodBackfillBatchLimit = 5

    @MainActor
    static func backfillMissingMoodsIfNeeded(context: ModelContext) async {
        guard SubscriptionService.shared.isSubscribed else { return }
        guard LocalLLMService.isModelAvailable else { return }
        guard !isBackfillingMoods else { return }
        isBackfillingMoods = true
        defer { isBackfillingMoods = false }

        let cutoff = Calendar.current.date(byAdding: .day, value: -moodBackfillWindowDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.encryptedMood == nil && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let candidates = ((try? context.fetch(descriptor)) ?? []).prefix(moodBackfillBatchLimit)

        for entry in candidates {
            guard !Task.isCancelled else { return }
            // Joins a save-time detection still running for the same entry instead of a second
            // model call. nil = nothing to classify (unreadable, empty) — skip it.
            guard let detection = MoodAutoDetector.shared.detectIfNeeded(entry, context: context) else { continue }
            // One failure means the LLM path is unhealthy right now (memory pressure,
            // cancellation mid-load) — stop the pass and let the next trigger retry.
            guard await detection.value else { return }
        }
    }

    @MainActor
    static func checkMoodAlertIfNeeded(context: ModelContext) async {
        guard SubscriptionService.shared.isDeep else { return }

        // Cooldown: at most one alert per 24h
        if let last = UserDefaults.standard.object(forKey: moodAlertCooldownKey) as? Date,
           Date().timeIntervalSince(last) < 86400 { return }

        let descriptor = FetchDescriptor<Entry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let entries = (try? context.fetch(descriptor)) ?? []

        // Recent negative mood-*days* (entry moods + check-ins merged, latest of
        // the day wins) — not consecutive entries, which three low entries in
        // one afternoon could falsely trip.
        let checkIns = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        let lowMoodDays = MoodLog.recentNegativeMoodDays(
            entries: entries,
            checkIns: checkIns
        )

        if lowMoodDays >= 3 {
            UserDefaults.standard.set(Date(), forKey: moodAlertCooldownKey)
            await NotificationService.sendMoodAlert(consecutiveCount: lowMoodDays)
        }
    }

    // MARK: - BGAppRefreshTask fallback for daily reflection

    @MainActor
    private func runDailyNudgeFallback() async {
        // Empty in-memory stand-in when the journal store couldn't be opened: nothing to do.
        guard MirrorModelContainer.isStoreAvailable else { return }
        // Re-arm first: once the task's time runs out, nothing after this point runs.
        scheduleDailyNudgeFallback()
        let context = sharedModelContainer.mainContext
        // The digest and report ride on this refresh. Separate weekly and monthly refresh
        // requests were never submitted before 3.1.2, and when they were, they didn't stay
        // pending next to this one on device (2026-10-10). They go first: each is due rarely
        // and returns at once when it isn't, while the nudge has other triggers (app-active,
        // the nightly task) and a refresh window fits about one generation.
        if DateHelpers.isSunday() {
            await mirrorApp.runWeeklyDigestIfNeeded(context: context)
            guard !Task.isCancelled else { return }
        }
        await mirrorApp.runMonthlyReportIfNeeded(context: context)
        guard !Task.isCancelled else { return }
        await mirrorApp.runDailyNudgeIfNeeded(context: context, bypassTimeGate: true)
    }

    private func scheduleDailyNudgeFallback() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: "com.lokesh.mirror.dailyNudge")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        Self.submitRefresh(request)
        #endif
    }

    private func generateDailyNudgeInBackgroundIfNeeded() {
        let today = DateHelpers.dayIdentifier(for: Date())
        guard !InsightGenerationCoordinator.shared.isInFlight("nudge_\(today)") else { return }

        let app = UIApplication.shared
        let bgTask = BackgroundTaskReference()
        bgTask.id = app.beginBackgroundTask(withName: "mirror.dailyNudge.catchup") {
            Task { @MainActor in
                app.endBackgroundTask(bgTask.id)
            }
        }

        Task { @MainActor in
            let context = sharedModelContainer.mainContext
            // Also covers "save and leave": the same-day second reflection and the save's mood
            // detection (joined by runDailyNudgeIfNeeded) both run inside this background time.
            if mirrorApp.dailyReflectionMayBeDue(context: context) {
                await mirrorApp.runDailyNudgeIfNeeded(context: context)
            }
            app.endBackgroundTask(bgTask.id)
        }
    }

    #if os(iOS)
    private static func submitRefresh(_ request: BGTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[bg] submitted \(request.identifier)")
            #endif
        } catch {
            #if DEBUG
            print("[bg] submit failed \(request.identifier): \(error)")
            #endif
        }
    }
    #endif

    // MARK: - Widget data bridge

    private static let widgetDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    static func updateWidgetHeatmaps(context: ModelContext) {
        let descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt)])
        let entries = (try? context.fetch(descriptor)) ?? []

        // Entry count per day drives the streak + wrote-today flags below. Stays
        // entry-only — a mood check-in isn't "writing an entry".
        var countByDay: [String: Int] = [:]
        for entry in entries {
            countByDay[widgetDayFormatter.string(from: entry.createdAt), default: 0] += 1
        }

        // Mood per day: entry moods + standalone daily check-ins, latest reading
        // of the day wins. Single merge rule, shared with every other surface.
        let checkIns = (try? context.fetch(FetchDescriptor<MoodCheckIn>())) ?? []
        var moodByDay: [String: String] = [:]
        for (day, event) in MoodLog.dailyMoods(entries: entries, checkIns: checkIns) {
            moodByDay[widgetDayFormatter.string(from: day)] = event.mood
        }

        let defaults = UserDefaults(suiteName: WidgetShared.appGroupID)
        defaults?.set(try? JSONEncoder().encode(countByDay), forKey: "widget.entries.heatmap")
        defaults?.set(try? JSONEncoder().encode(moodByDay),  forKey: "widget.mood.heatmap")

        // Streak + wrote-today for WriteWidget / EntriesMapWidget
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = widgetDayFormatter
        let todayKey = fmt.string(from: today)
        let wroteToday = (countByDay[todayKey] ?? 0) > 0
        var streakDay = today
        if !wroteToday {
            if let yesterday = cal.date(byAdding: .day, value: -1, to: today),
               (countByDay[fmt.string(from: yesterday)] ?? 0) > 0 {
                streakDay = yesterday
            } else {
                streakDay = Date.distantPast
            }
        }
        var streak = 0
        while (countByDay[fmt.string(from: streakDay)] ?? 0) > 0 {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: streakDay) else { break }
            streakDay = prev
        }
        defaults?.set(streak, forKey: "widget.streak")
        defaults?.set(wroteToday, forKey: "widget.wrote.today")

        WidgetCenter.shared.reloadAllTimelines()
    }

    // Writes today's nudge text to AppGroup so NudgeWidget can read it even if the
    // nudge was generated in a previous app session (runDailyNudgeIfNeeded bails early then).
    @MainActor
    static func syncNudgeToWidget(context: ModelContext) {
        let today = DateHelpers.dayIdentifier(for: Date())
        let descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.periodIdentifier == today }
        )
        // Newest wins (matches resolvedNudgeState's own read) and a fallback is skipped
        // entirely, same reasoning as the inline write in runDailyNudgeIfNeeded's do-block: the
        // widget has no groundingFallback UI, so writing the canned "couldn't confirm" sentence
        // renders it as if it were a real nudge with no retry affordance. Catch-all callers of
        // this function (CachedInsightRepair, UngroundedInsightCleanup, preGenerateInsightsIfNeeded)
        // could otherwise push that text to the widget even when the in-app card correctly shows
        // the retry state instead.
        guard let insights = try? context.fetch(descriptor),
              let nudge = insights
                  .filter({ $0.type == .dailyNudge && !InsightService.isUngroundedFallback($0.content) })
                  .max(by: { $0.generatedAt < $1.generatedAt }) else { return }
        let defaults = UserDefaults(suiteName: WidgetShared.appGroupID)
        defaults?.set(InsightService.nudgeTextForOutsideApp(nudge.content), forKey: "widget.nudge.text")
        defaults?.set(today, forKey: "widget.nudge.date")
        let entryDescriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let todaysEntries = (try? context.fetch(entryDescriptor)) ?? []
        defaults?.set(InsightService.reflectedDay(of: nudge, entriesNewestFirst: todaysEntries).map { DateHelpers.dayIdentifier(for: $0) }, forKey: "widget.nudge.aboutDate")
        if let todaysMood = todaysEntries.first(where: { DateHelpers.dayIdentifier(for: $0.createdAt) == today })?.mood {
            defaults?.set(todaysMood, forKey: "widget.nudge.mood")
        } else {
            defaults?.removeObject(forKey: "widget.nudge.mood")
        }
    }

    // MARK: - Notification permission (existing users who completed onboarding before prompt was added)

    /// One-time move from the old separate "writing reminder" to the unified
    /// daily check-in reminder. Carries the user's chosen time over (unless
    /// they'd already picked a check-in time) and clears the old request.
    private func migrateToUnifiedDailyReminder() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "didMergeDailyReminder") else { return }
        d.set(true, forKey: "didMergeDailyReminder")

        if d.bool(forKey: "writingReminderEnabled") {
            // Old reminder was on → carry its time over.
            if !d.bool(forKey: "moodCheckInTimeUserSet") {
                d.set(d.object(forKey: "writingReminderHour") as? Int ?? 9, forKey: "moodCheckInHour")
                d.set(d.object(forKey: "writingReminderMinute") as? Int ?? 0, forKey: "moodCheckInMinute")
            }
        } else if d.object(forKey: "writingReminderEnabled") != nil {
            // Old reminder existed and was explicitly OFF → the check-in
            // reminder (default on) must not surprise them with a notification.
            d.set(false, forKey: "moodCheckInEnabled")
        }
        NotificationService.cancelWritingReminder()
    }

    /// Re-issue the unified daily check-in reminder on every foreground.
    /// `scheduleMoodCheckIn` clears-and-re-adds and no-ops when notifications
    /// aren't authorized — so this is idempotent and self-heals the case where
    /// the reminder was left on (it's on by default) before permission was
    /// granted, when nothing would otherwise have been scheduled.
    private func reArmUserReminders() async {
        let d = UserDefaults.standard
        // `moodCheckInEnabled` defaults to true — treat a missing value as on.
        let enabled = (d.object(forKey: "moodCheckInEnabled") as? Bool) ?? true
        guard enabled else { return }
        await NotificationService.scheduleMoodCheckIn(
            hour: d.object(forKey: "moodCheckInHour") as? Int ?? 9,
            minute: d.object(forKey: "moodCheckInMinute") as? Int ?? 0
        )
    }

    private func requestNotificationPermissionIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        // Gated on entries.count >= 3 — the same threshold runDailyNudgeIfNeeded uses for nudge
        // eligibility — rather than on an existing daily-nudge Insight: permission must resolve
        // *before* the first nudge generates, or scheduleFirstNudgeHook's isAuthorized() check
        // silently no-ops and, since the Insight it would have announced is already saved by
        // then, never gets a second chance (hasSeenFirst locks out that path for non-subscribers
        // for good). This backfill (originally added for users who onboarded before a permission
        // prompt existed at all) is now the ONLY place permission is requested — OnboardingFlow
        // no longer asks at Day 0.
        let context = sharedModelContainer.mainContext
        let entryCount = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? 0
        guard entryCount >= 3 else { return }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        // Not gated on subscription — free users get the same repeating "come write" reminder
        // (insightReady false → generic body) at their chosen hour that onboarding used to
        // schedule unconditionally on Day 0. Only the Core/Deep "your reflection is ready" body
        // needs a subscription; the reminder itself doesn't.
        let insightReady = mirrorApp.hasDailyNudgeForToday(context: context) && SubscriptionService.shared.isSubscribed
        let hasWrittenToday = mirrorApp.hasEntryToday(context: context)
        let previewEnabled = UserDefaults.standard.bool(forKey: "nudgePreviewEnabled")
        await NotificationService.rescheduleContextualNudge(
            hasWrittenToday: hasWrittenToday,
            insightReady: insightReady,
            hour: NotificationService.nudgeHour(),
            minute: NotificationService.nudgeMinute(),
            previewText: (previewEnabled && insightReady) ? mirrorApp.todaysDailyNudgeText(context: context) : nil
        )
    }

    // MARK: - Background time extension for mid-session generation

    private func extendBackgroundForPendingGeneration() {
        guard InsightGenerationCoordinator.shared.isAnyGenerating else { return }
        let app = UIApplication.shared
        let bgTask = BackgroundTaskReference()
        bgTask.id = app.beginBackgroundTask(withName: "mirror.insight.completion") {
            Task { @MainActor in
                app.endBackgroundTask(bgTask.id)
            }
        }
        Task { @MainActor in
            while InsightGenerationCoordinator.shared.isAnyGenerating {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            app.endBackgroundTask(bgTask.id)
        }
    }
}

private final class BackgroundTaskReference: @unchecked Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid
}
