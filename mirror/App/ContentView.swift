import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @State private var selectedTab = 1  // 0=Entries, 1=Write, 2=Insights
    @State private var insightViewModel = InsightViewModel()
    @State private var showPaywall = false
    @State private var entriesNavResetID = UUID()

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    private var onboardingComplete: Bool {
        profiles.first?.onboardingComplete ?? false
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            EntriesTabView(navResetID: entriesNavResetID)
                .tabItem { Label("Entries", systemImage: "book.closed") }
                .tag(0)

            WriteTabView(selectedTab: $selectedTab, onSave: {
                selectedTab = 0
                entriesNavResetID = UUID()
            })
                .tabItem { Label("Write", systemImage: "square.and.pencil") }
                .tag(1)

            InsightView(viewModel: insightViewModel)
                .tabItem { Label("Insights", systemImage: "sparkles") }
                .tag(2)
        }
        .fullScreenCover(isPresented: .constant(!onboardingComplete && !isUITesting)) {
            OnboardingFlow()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onChange(of: onboardingComplete) { _, complete in
            if complete { selectedTab = 1 }
        }
        .onAppear {
            // Don't open Write tab (and its keyboard) while onboarding is showing
            if !onboardingComplete { selectedTab = 0 }
        }
        .onOpenURL { url in
            guard url.scheme == "mirror" else { return }
            switch url.host {
            case "write":    selectedTab = 1
            case "entries":  selectedTab = 0
            case "insights": selectedTab = 2
            case "upgrade":  showPaywall = true
            default:         break
            }
        }
    }
}

// Write tab wraps WriteView in a NavigationStack so it can push VoiceInputSheet
private struct WriteTabView: View {
    @Binding var selectedTab: Int
    var onSave: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            WriteView(autoFocus: true) {
                onSave?()
            }
        }
    }
}
