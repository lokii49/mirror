import SwiftUI
import SwiftData

/// Exposes the user's chosen display mode (Classic / Sentinel) down the view
/// tree. Root-level so any screen can branch without re-querying UserProfile.
private struct DisplayModeKey: EnvironmentKey {
    static let defaultValue: DisplayMode = .classic
}

extension EnvironmentValues {
    var appDisplayMode: DisplayMode {
        get { self[DisplayModeKey.self] }
        set { self[DisplayModeKey.self] = newValue }
    }
}

private enum AppSidebarItem: String, CaseIterable, Hashable {
    case entries, write, insights, settings

    var title: LocalizedStringKey {
        switch self {
        case .entries:  return "Entries"
        case .write:    return "Write"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .entries:  return "book.closed"
        case .write:    return "square.and.pencil"
        case .insights: return "sparkles"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = ContentView.launchTab  // 0=Entries, 1=Write, 2=Insights
    @State private var selectedSidebarItem: AppSidebarItem? = .write
    @State private var insightViewModel = InsightViewModel()
    @State private var showPaywall = false
    @State private var entriesNavResetID = UUID()
    @State private var showWhatsNew = false
    @State private var showRatePrompt = false
    @State private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var showMoodCheckIn = false
    @State private var moodCheckInPresenter = MoodCheckInPresenter.shared
    @State private var appLock = AppLock.shared
    @State private var deepLinkEntryID: UUID? = nil
    #if os(macOS)
    @State private var macSelectedEntry: Entry? = nil
    @State private var macWriteID = UUID()
    @State private var macWriteInitialText = ""
    @State private var macDestination: MacDestination = .write
    @State private var macSidebarVisible = true
    #endif
    @State private var showWriteFromWidgetPrompt = false
    @State private var widgetPromptText: String = ""
    private let featureCardService = FeatureCardService.shared
    @AppStorage("mirrorAppearanceMode") private var appearanceMode: String = "system"

    // Auto mood check-in prompt: if the user hasn't logged a mood today and it's
    // past their preferred check-in time, surface the sheet the next time the app
    // comes to the foreground. `moodCheckInShownDay` is stamped at the single
    // presentation site below (any path — auto, notification tap, manual button),
    // so the prompt fires at most once per day and a dismissed reminder isn't
    // re-nagged an hour later.
    @AppStorage("moodCheckInEnabled") private var moodCheckInEnabled: Bool = true
    @AppStorage("moodCheckInHour") private var moodCheckInHour: Int = 9
    @AppStorage("moodCheckInMinute") private var moodCheckInMinute: Int = 0
    @AppStorage("moodCheckInShownDay") private var moodCheckInShownDay: String = ""

    /// Sentinel is a HUD — it reads as "futuristic" only against a dark
    /// canvas, the same way a cockpit display or mission-control screen
    /// always renders dark regardless of the room's lighting. Forces dark
    /// whenever Sentinel is active; onChange(of: displayMode) below keeps
    /// the stored Appearance setting itself in sync so Settings never
    /// shows "System" while the app is actually pinned dark.
    private func applyColorScheme(_ mode: String) {
        #if os(macOS)
        // Sentinel is not offered on Mac yet, so only the stored Appearance choice applies.
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
        #else
        let style: UIUserInterfaceStyle
        if displayMode == .sentinel {
            style = .dark
        } else {
            switch mode {
            case "light": style = .light
            case "dark":  style = .dark
            default:      style = .unspecified
            }
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
        #endif
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    /// Write, except DEBUG `--initialTab=entries` (headless simulator screenshots,
    /// where a mirror:// link would stop at the system's open confirmation).
    private static var launchTab: Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--initialTab=entries") { return 0 }
        #endif
        return 1
    }

    /// Widgets run in a separate process with no SwiftUI environment of their
    /// own, so appDisplayMode never reaches them directly — mirrors the
    /// existing widget.tier pattern (SubscriptionService writes, widgets read)
    /// to hand them just enough to pick their own Sentinel/Classic chrome.
    private func syncWidgetDisplayMode() {
        UserDefaults(suiteName: "group.com.lokesh.mirror")?.set(displayMode.rawValue, forKey: "widget.displayMode")
    }

    private var onboardingComplete: Bool {
        profiles.first?.onboardingComplete ?? false
    }

    /// True only when the rate-us gate is wanted AND the screen is free to show
    /// it — SwiftUI silently drops a second concurrent `.sheet`. Evaluated every
    /// render, so `.onChange` below fires the moment a blocking sheet clears.
    /// The milestone flag is consumed only on a real presentation, so a session
    /// that never clears just defers to the next qualifying entry save.
    private var canPresentRatePrompt: Bool {
        reviewPromptCoordinator.isPending
            && !ReviewRequestManager.hasShownEntryMilestonePrompt
            && !showPaywall && !showWhatsNew && !showRatePrompt && !showMoodCheckIn
            && onboardingComplete
    }

    /// The mood check-in sheet is triggered by tapping the daily reminder —
    /// present it once the screen is free of other modals. If it never clears
    /// in this session, `pending` simply carries to the next launch/tap.
    private var canPresentMoodCheckIn: Bool {
        moodCheckInPresenter.pending
            && !showPaywall && !showWhatsNew && !showRatePrompt && !showMoodCheckIn
            && !moodCheckInPresenter.blockedByOtherSheet
            && onboardingComplete
    }

    private var displayMode: DisplayMode {
        #if os(macOS)
        // Sentinel is not on Mac yet (default theme first), even if the profile synced it from iPhone.
        return .classic
        #else
        return profiles.first?.displayMode ?? .classic
        #endif
    }

    /// Runs on every foreground. Sets `MoodCheckInPresenter.pending` — which the
    /// existing modal-gated flow turns into a presentation — when the user is
    /// past their preferred time today and no mood (check-in or entry) is on the
    /// books for today yet.
    private func maybeAutoPromptMoodCheckIn() {
        #if os(macOS)
        // Off on Mac: "active" fires on every switch back to the app, so the sheet would pop up
        // unprompted. The Mac gets the check-in reminder as a notification instead (shown even
        // while the app is frontmost; clicking it opens this sheet), plus Go > Log Mood… (⌥⌘M).
        return
        #else
        guard onboardingComplete, moodCheckInEnabled, !isUITesting else { return }
        // Don't race the What's New sheet: SwiftUI drops the second concurrent sheet.
        guard !featureCardService.shouldShowWhatsNew else { return }

        let now = Date()
        let cal = Calendar.current
        let todayKey = DateHelpers.dayIdentifier(for: now)
        guard moodCheckInShownDay != todayKey, !moodCheckInPresenter.pending else { return }
        guard let preferred = cal.date(bySettingHour: moodCheckInHour, minute: moodCheckInMinute, second: 0, of: now),
              now >= preferred else { return }

        let startOfDay = cal.startOfDay(for: now)
        Task { @MainActor in
            // Let the legacy check-in migration (its own Task in mirrorApp's
            // `.active` block) land first, so a check-in imported for today isn't missed.
            try? await Task.sleep(for: .seconds(2))
            guard moodCheckInShownDay != todayKey, !moodCheckInPresenter.pending else { return }

            let checkIns = (try? modelContext.fetch(
                FetchDescriptor<MoodCheckIn>(predicate: #Predicate { $0.createdAt >= startOfDay })
            )) ?? []
            let todaysEntries = (try? modelContext.fetch(
                FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt >= startOfDay })
            )) ?? []
            // Single "what was the mood, and when" rule — merges both sources.
            let byDay = MoodLog.dailyMoods(entries: todaysEntries, checkIns: checkIns, calendar: cal)
            guard byDay[startOfDay] == nil else { return }

            moodCheckInPresenter.pending = true
        }
        #endif
    }

    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            if sizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
            }
            #endif
        }
        .environment(\.appDisplayMode, displayMode)
        // App Lock: the real cover is a window of its own (iOS) or one over every window (Mac),
        // which also covers sheets. This one only guarantees the first frame never shows the journal.
        .overlay {
            if appLock.hidesContent {
                AppLockScreen(interactive: false)
                    .environment(\.appDisplayMode, displayMode)
            }
        }
        #if os(iOS)
        .background(AppLockWindowInstaller())
        #endif
        .onAppear {
            PerfSignpost.endLaunchIfNeeded()
            applyColorScheme(appearanceMode)
            syncWidgetDisplayMode()
        }
        .onChange(of: appearanceMode) { _, new in applyColorScheme(new) }
        .onChange(of: displayMode) { _, newMode in
            if newMode == .sentinel {
                if appearanceMode == "system" || appearanceMode == "light" {
                    appearanceMode = "dark"
                }
            } else {
                appearanceMode = "system"
            }
            applyColorScheme(appearanceMode)
            syncWidgetDisplayMode()
        }
        .fullScreenCover(isPresented: .constant(!onboardingComplete && !isUITesting)) {
            OnboardingFlow()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(\.appDisplayMode, displayMode)
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet(mode: .whatsNew)
                .environment(\.appDisplayMode, displayMode)
        }
        #if os(iOS)
        // Write focuses its editor on launch, and these sheets open over it a moment later: put the
        // keyboard away so it doesn't sit on top of the sheet (2026-10-09).
        .onChange(of: showWhatsNew || showMoodCheckIn || showRatePrompt || showPaywall) { _, covered in
            if covered {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        #endif
        .sheet(isPresented: $showRatePrompt) {
            RateUsPromptSheet()
                .environment(\.appDisplayMode, displayMode)
        }
        .sheet(isPresented: $showMoodCheckIn) {
            MoodCheckInView()
                .environment(\.appDisplayMode, displayMode)
        }
        .sheet(isPresented: $showWriteFromWidgetPrompt) {
            NavigationStack {
                WriteView(autoFocus: true, initialText: widgetPromptText) {
                    showWriteFromWidgetPrompt = false
                }
            }
            .environment(\.appDisplayMode, displayMode)
        }
        .onChange(of: canPresentRatePrompt) { _, canPresent in
            // UI tests and synthetic runs must not consume the once-per-install prompt.
            guard canPresent, !isUITesting else { return }
            reviewPromptCoordinator.isPending = false
            ReviewRequestManager.markEntryMilestonePromptShown()
            showRatePrompt = true
        }
        .onChange(of: canPresentMoodCheckIn, initial: true) { _, canPresent in
            // `initial: true` covers the cold-launch-from-notification case
            // where `pending` was already set (by the delegate, in app init)
            // before this view's first render. If a same-tick race with the
            // rate sheet swallows this presentation, the daily reminder repeats
            // — the next tap re-sets `pending`.
            guard canPresent, !showRatePrompt else { return }
            moodCheckInPresenter.pending = false
            moodCheckInShownDay = DateHelpers.dayIdentifier(for: Date())
            showMoodCheckIn = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { maybeAutoPromptMoodCheckIn() }
        }
        .onChange(of: sizeClass) { _, newClass in
            if newClass == .regular {
                switch selectedTab {
                case 0: selectedSidebarItem = .entries
                case 2: selectedSidebarItem = .insights
                default: selectedSidebarItem = .write
                }
            } else {
                switch selectedSidebarItem {
                case .entries:  selectedTab = 0
                case .insights: selectedTab = 2
                case .settings: selectedTab = 1
                default:        selectedTab = 1
                }
            }
        }
        .onChange(of: onboardingComplete) { _, complete in
            if complete {
                selectedTab = 1
                selectedSidebarItem = .write
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if featureCardService.shouldShowWhatsNew {
                        showWhatsNew = true
                    }
                }
            }
        }
        .onAppear {
            if !onboardingComplete {
                selectedTab = 0
                selectedSidebarItem = .entries
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--showRatePrompt") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    showRatePrompt = true
                }
            }
            #endif
            if onboardingComplete && !isUITesting && featureCardService.shouldShowWhatsNew {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    showWhatsNew = true
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "mirror" else { return }
            #if os(macOS)
            if macHandleWidgetURL(url) { return }
            #endif
            switch url.host {
            case "write":
                if let indexString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "promptIndex" })?.value,
                   let index = Int(indexString), WritingPrompts.all.indices.contains(index) {
                    widgetPromptText = WritingPrompts.all[index]
                    showWriteFromWidgetPrompt = true
                } else {
                    selectedTab = 1
                    selectedSidebarItem = .write
                }
            case "entries":
                selectedTab = 0
                selectedSidebarItem = .entries
            case "insights", "nudge":
                selectedTab = 2
                selectedSidebarItem = .insights
            case "upgrade":
                showPaywall = true
            case "entry":
                if let idString = url.pathComponents.dropFirst().first,
                   let uuid = UUID(uuidString: idString) {
                    deepLinkEntryID = uuid
                    selectedTab = 0
                    selectedSidebarItem = .entries
                }
            default:
                break
            }
        }
    }

    // MARK: - iPhone layout (TabView)

    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            EntriesTabView(navResetID: entriesNavResetID, deepLinkEntryID: $deepLinkEntryID)
                .tabItem { Label(displayMode == .sentinel ? "Log" : "Entries", systemImage: displayMode == .sentinel ? "viewfinder" : "book.closed") }
                .tag(0)

            WriteTabView(onSave: {
                selectedTab = 0
                entriesNavResetID = UUID()
            })
            .tabItem { Label(displayMode == .sentinel ? "Transmission" : "Write", systemImage: displayMode == .sentinel ? "antenna.radiowaves.left.and.right" : "square.and.pencil") }
            .tag(1)

            InsightView(viewModel: insightViewModel)
                .tabItem { Label(displayMode == .sentinel ? "Briefing" : "Insights", systemImage: displayMode == .sentinel ? "target" : "sparkles") }
                .tag(2)
        }
        #if os(iOS)
        .toolbarBackground(MirrorTheme.inkMid, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        #endif
        .tint(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
    }

    // MARK: - Mac layout (sidebar + detail, list and reader side by side for Entries)

    #if os(macOS)
    /// Widget and deep links on Mac. True when handled here; the rest follow the shared routing.
    private func macHandleWidgetURL(_ url: URL) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        switch url.host {
        case "write":
            // A prompt tile seeds a new entry in the main window (no sheet on Mac).
            if let indexString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "promptIndex" })?.value,
               let index = Int(indexString), WritingPrompts.all.indices.contains(index) {
                macWriteInitialText = WritingPrompts.all[index] + "\n\n"
                macWriteID = UUID()
                macDestination = .write
                return true
            }
            return false
        case "entry":
            guard let idString = url.pathComponents.dropFirst().first, let id = UUID(uuidString: idString) else { return true }
            NotificationCenter.default.post(name: .mirrorMacOpenEntry, object: nil, userInfo: ["id": id])
            return true
        case "monthly-report":
            macDestination = .report
            return true
        case "mood-timeline":
            macDestination = .mood
            return true
        default:
            return false
        }
    }

    private var macLayout: some View {
        MacRootView(selection: $macDestination, sidebarVisible: $macSidebarVisible) {
            macDetailView
        }
        .frame(minWidth: 980, minHeight: 600)
        // The title bar is hidden, but the Window menu and Mission Control still show the title.
        .navigationTitle(macDestination.windowTitle)
        .onChange(of: selectedSidebarItem) { _, item in
            // Widget and URL deep links still set the shared selection.
            switch item {
            case .entries: macDestination = .entries
            case .write: macDestination = .write
            case .insights: macDestination = .today
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacNavigate)) { note in
            if let raw = note.userInfo?["destination"] as? String, let destination = MacDestination(rawValue: raw) {
                macDestination = destination
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacNewEntry)) { _ in
            macWriteInitialText = ""
            macWriteID = UUID()
            macDestination = .write
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacNewEntrySeeded)) { note in
            macWriteInitialText = note.userInfo?["text"] as? String ?? ""
            macWriteID = UUID()
            macDestination = .write
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacOpenEntry)) { note in
            // Set the selection here: the Entries view may not exist yet, and a binding that is
            // already set when a view appears never fires its onChange.
            if let id = note.userInfo?["id"] as? UUID {
                var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let entry = try? modelContext.fetch(descriptor).first {
                    macDestination = .entries
                    macSelectedEntry = entry
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacToggleSidebar)) { _ in
            macSidebarVisible.toggle()
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacDebugSelectFirstEntry)) { _ in
            var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = 1
            macSelectedEntry = try? modelContext.fetch(descriptor).first
        }
        .task {
            if MacSnapshot.isRequested { await MacSnapshot.run(context: modelContext) }
        }
        #endif
    }

    @ViewBuilder
    private var macDetailView: some View {
        switch macDestination {
        case .entries:
            HSplitView {
                EntriesTabView(navResetID: entriesNavResetID, deepLinkEntryID: $deepLinkEntryID, macSelection: $macSelectedEntry)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
                Group {
                    if let macSelectedEntry {
                        NavigationStack {
                            EntryDetailView(entry: macSelectedEntry) {
                                self.macSelectedEntry = nil
                            }
                        }
                        .ignoresSafeArea(.container, edges: .top)
                        .id(macSelectedEntry.id)
                        // An entry deleted elsewhere (sync, another window) closes the reader and editor.
                        .background(MacSelectionGuard(entryID: macSelectedEntry.id) { self.macSelectedEntry = nil })
                    } else {
                        ContentUnavailableView("Select an entry", systemImage: "book.closed")
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            // Without this the split view sizes itself to its content and floats in the middle.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .write:
            WriteTabView(initialText: macWriteInitialText, onSave: {
                macDestination = .entries
                entriesNavResetID = UUID()
            })
            .id(macWriteID)
        case .today:
            InsightView(viewModel: insightViewModel, macPage: .today)
        case .digest:
            InsightView(viewModel: insightViewModel, macPage: .digest)
        case .report:
            NavigationStack { MonthlyReportView(viewModel: insightViewModel) }
        case .mood:
            NavigationStack { MoodTimelineView() }
        case .ask:
            NavigationStack { AskView(viewModel: insightViewModel) }
        case .brain:
            NavigationStack { BrainView(viewModel: insightViewModel) }
        }
    }
    #endif

    // MARK: - iPad layout (NavigationSplitView)

    private var ipadLayout: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(AppSidebarItem.allCases, id: \.self, selection: $selectedSidebarItem) { item in
                Label(item.title, systemImage: item.icon)
            }
            .navigationTitle("MirrorNotes")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            ipadDetailView
        }
    }

    @ViewBuilder
    private var ipadDetailView: some View {
        switch selectedSidebarItem ?? .write {
        case .entries:
            EntriesTabView(navResetID: entriesNavResetID, deepLinkEntryID: $deepLinkEntryID)
        case .write:
            WriteTabView(onSave: {
                selectedSidebarItem = .entries
                entriesNavResetID = UUID()
            })
        case .insights:
            InsightView(viewModel: insightViewModel)
        case .settings:
            SettingsView()
        }
    }
}

// Write tab wraps WriteView in a NavigationStack for its toolbar + sheets.
private struct WriteTabView: View {
    var initialText: String = ""
    var onSave: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        // The Mac Write screen draws its own toolbar, so it needs no navigation bar.
        WriteView(autoFocus: true, initialText: initialText) {
            onSave?()
        }
        #else
        NavigationStack {
            WriteView(autoFocus: true) {
                onSave?()
            }
        }
        #endif
    }
}

