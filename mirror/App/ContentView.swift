import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @State private var selectedTab = 1  // 0=Entries, 1=Write, 2=Insights

    private var onboardingComplete: Bool {
        profiles.first?.onboardingComplete ?? false
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            EntriesTabView()
                .tabItem { Label("Entries", systemImage: "book.closed") }
                .tag(0)

            WriteTabView()
                .tabItem { Label("Write", systemImage: "square.and.pencil") }
                .tag(1)

            InsightView()
                .tabItem { Label("Insights", systemImage: "sparkles") }
                .tag(2)
        }
        .fullScreenCover(isPresented: .constant(!onboardingComplete)) {
            OnboardingFlow()
        }
        .onChange(of: onboardingComplete) { _, complete in
            if complete { selectedTab = 1 }
        }
        .onAppear {
            // Don't open Write tab (and its keyboard) while onboarding is showing
            if !onboardingComplete { selectedTab = 0 }
        }
    }
}

// Write tab wraps WriteView in a NavigationStack so it can push VoiceInputSheet
private struct WriteTabView: View {
    var body: some View {
        NavigationStack {
            WriteView(autoFocus: true)
        }
    }
}
