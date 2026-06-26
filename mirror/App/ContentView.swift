import SwiftUI
import SwiftData

private enum AppSidebarItem: String, CaseIterable, Hashable {
    case entries, write, insights, settings

    var title: String {
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
    @State private var selectedTab = 1  // 0=Entries, 1=Write, 2=Insights
    @State private var selectedSidebarItem: AppSidebarItem? = .write
    @State private var insightViewModel = InsightViewModel()
    @State private var showPaywall = false
    @State private var entriesNavResetID = UUID()
    @State private var showWhatsNew = false
    private let featureCardService = FeatureCardService.shared
    @AppStorage("mirrorAppearanceMode") private var appearanceMode: String = "system"

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    private var onboardingComplete: Bool {
        profiles.first?.onboardingComplete ?? false
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
            }
        }
        .preferredColorScheme(preferredScheme)
        .fullScreenCover(isPresented: .constant(!onboardingComplete && !isUITesting)) {
            OnboardingFlow()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet(mode: .whatsNew)
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
            case "insights":
                selectedTab = 2
                selectedSidebarItem = .insights
            case "upgrade":
                showPaywall = true
            default:
                break
            }
        }
    }

    // MARK: - iPhone layout (TabView)

    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            EntriesTabView(navResetID: entriesNavResetID)
                .tabItem { Label("Entries", systemImage: "book.closed") }
                .tag(0)

            WriteTabView(onSave: {
                selectedTab = 0
                entriesNavResetID = UUID()
            })
            .tabItem { Label("Write", systemImage: "square.and.pencil") }
            .tag(1)

            InsightView(viewModel: insightViewModel)
                .tabItem { Label("Insights", systemImage: "sparkles") }
                .tag(2)
        }
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
            EntriesTabView(navResetID: entriesNavResetID)
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
