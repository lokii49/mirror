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
    @State private var selectedTab = 1  // 0=Entries, 1=Write, 2=Insights
    @State private var selectedSidebarItem: AppSidebarItem? = .write
    @State private var insightViewModel = InsightViewModel()
    @State private var showPaywall = false
    @State private var entriesNavResetID = UUID()
    @State private var showWhatsNew = false
    @State private var showRatePrompt = false
    @State private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    @State private var showMoodCheckIn = false
    @State private var moodCheckInPresenter = MoodCheckInPresenter.shared
    @State private var deepLinkEntryID: UUID? = nil
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
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
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
        profiles.first?.displayMode ?? .classic
    }

    /// Runs on every foreground. Sets `MoodCheckInPresenter.pending` — which the
    /// existing modal-gated flow turns into a presentation — when the user is
    /// past their preferred time today and no mood (check-in or entry) is on the
    /// books for today yet.
    private func maybeAutoPromptMoodCheckIn() {
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
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
            }
        }
        .environment(\.appDisplayMode, displayMode)
        .onAppear {
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
        .sheet(isPresented: $showRatePrompt) {
            RateUsPromptSheet()
                .environment(\.appDisplayMode, displayMode)
        }
        .sheet(isPresented: $showMoodCheckIn) {
            MoodCheckInView()
                .environment(\.appDisplayMode, displayMode)
        }
        .onChange(of: canPresentRatePrompt) { _, canPresent in
            guard canPresent else { return }
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
            if onboardingComplete && !isUITesting && featureCardService.shouldShowWhatsNew {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    showWhatsNew = true
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme == "mirror" else { return }
            switch url.host {
            case "write":
                selectedTab = 1
                selectedSidebarItem = .write
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
        .toolbarBackground(MirrorTheme.inkMid, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
    }

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

// Write tab wraps WriteView in a NavigationStack so it can push VoiceInputSheet
private struct WriteTabView: View {
    var onSave: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            WriteView(autoFocus: true) {
                onSave?()
            }
        }
    }
}
