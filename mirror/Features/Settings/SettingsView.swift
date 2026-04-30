import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var authService = AuthService.shared
    @State private var subscriptionService = SubscriptionService.shared
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showSubscription = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    statsGrid
                    accountSection
                    appSection
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MirrorTheme.bgBase)
            .navigationTitle("Profile")
            .alert("Something went wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "")
            }
            .task {
                await authService.checkSession()
                await subscriptionService.refresh()
                await subscriptionService.loadProducts()
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 16) {
            // Avatar with gradient
            ZStack {
                Circle()
                    .fill(MirrorTheme.accentGradient)
                    .frame(width: 58, height: 58)
                Image(systemName: "person.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: MirrorTheme.primary.opacity(0.25), radius: 10, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mirror Journal")
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    if subscriptionService.isSubscribed {
                        Label("Core", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MirrorTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(MirrorTheme.primary.opacity(0.12), in: Capsule())
                    } else {
                        Text(authService.isAuthenticated ? "Signed in" : "Local only")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if subscriptionService.isSubscribed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(MirrorTheme.primary)
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 26)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your journal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 14)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                statCard(value: "\(entries.count)", label: "Entries", icon: "book.pages", color: MirrorTheme.primary)
                statCard(value: totalWords.formatted(), label: "Words", icon: "text.word.spacing", color: .blue)
                statCard(value: "\(currentStreak)", label: currentStreak == 1 ? "Day streak" : "Day streak", icon: "flame.fill", color: .orange)
                statCard(value: latestEntryText, label: "Last entry", icon: "clock.fill", color: .green)
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 24)
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .futureSurface(cornerRadius: 16)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        settingsGroup("Account") {
            Button { showSubscription = true } label: {
                HStack {
                    settingsRowLabel(
                        subscriptionService.isSubscribed ? "Core · Active" : "Free plan",
                        systemImage: subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal",
                        iconColor: subscriptionService.isSubscribed ? MirrorTheme.primary : .secondary
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSubscription) { SubscriptionView() }

            Divider().padding(.leading, 48)

            if authService.isAuthenticated {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack {
                        settingsRowLabel("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", iconColor: .red)
                        Spacer()
                        if isLoading { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        settingsRowLabel("Sign in with Apple", systemImage: "apple.logo", iconColor: MirrorTheme.primary)
                        Spacer()
                        if isLoading { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - App Section

    private var appSection: some View {
        settingsGroup("App") {
            settingsRow("Version \(appVersion)", systemImage: "info.circle", iconColor: .blue)
            Divider().padding(.leading, 48)
            settingsRow("Data stored on device", systemImage: "lock.shield.fill", iconColor: .green)
        }
    }

    // MARK: - Debug

    #if DEBUG
    @Environment(\.modelContext) private var debugModelContext

    private var debugSection: some View {
        settingsGroup("Developer") {
            Button {
                SampleData.seed(into: debugModelContext)
            } label: {
                HStack {
                    settingsRowLabel("Load Sample Entries", systemImage: "doc.badge.plus", iconColor: .orange)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button(role: .destructive) {
                SampleData.clearInsights(from: debugModelContext)
            } label: {
                HStack {
                    settingsRowLabel("Clear Insight Cache", systemImage: "sparkles.slash", iconColor: .orange)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button(role: .destructive) {
                SampleData.clear(from: debugModelContext)
            } label: {
                HStack {
                    settingsRowLabel("Clear All Data", systemImage: "trash", iconColor: .red)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    // MARK: - Helpers

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 14)
            VStack(spacing: 0) {
                content()
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 24)
    }

    private func settingsRow(_ title: String, systemImage: String, iconColor: Color) -> some View {
        settingsRowLabel(title, systemImage: systemImage, iconColor: iconColor)
    }

    private func settingsRowLabel(_ title: String, systemImage: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func signIn() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signInWithApple()
            await subscriptionService.refresh()
        } catch {
            self.error = error
        }
    }

    private func signOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signOut()
            await subscriptionService.refresh()
        } catch {
            self.error = error
        }
    }

    private var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    private var latestEntryText: String {
        guard let latest = entries.first?.createdAt else { return "None" }
        if Calendar.current.isDateInToday(latest) { return "Today" }
        if Calendar.current.isDateInYesterday(latest) { return "Yesterday" }
        return latest.formatted(date: .abbreviated, time: .omitted)
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let days = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        let today = calendar.startOfDay(for: Date())
        var day = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
