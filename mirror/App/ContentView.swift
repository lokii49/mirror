import SwiftUI

struct ContentView: View {
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.82)
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.tintColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.tintColor]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            EntriesTabView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }

            InsightView()
                .tabItem { Label("Insights", systemImage: "sparkles") }

            AskView()
                .tabItem { Label("Ask", systemImage: "bubble.left.and.bubble.right") }

            SettingsView()
                .tabItem { Label("Profile", systemImage: "person.circle.fill") }
        }
        .tint(MirrorTheme.primary)
    }
}
