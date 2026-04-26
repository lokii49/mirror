import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var authService = AuthService.shared
    @State private var subscriptionService = SubscriptionService.shared
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                profileSection
                journalSection
                accountSection
                appSection
                }
                .padding(16)
            }
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

    private var profileSection: some View {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: MirrorTheme.moodSpectrum, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 62, height: 62)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Mirror")
                        .font(.headline)
                    Text(authService.isAuthenticated ? "Signed in with Apple" : "Local journal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .futureSurface(cornerRadius: 26)
    }

    private var journalSection: some View {
        settingsGroup("Journal") {
            settingsRow("Entries", value: entries.count.formatted(), systemImage: "book.pages")
            settingsRow("Words", value: totalWords.formatted(), systemImage: "text.word.spacing")
            settingsRow("Current Streak", value: "\(currentStreak) \(currentStreak == 1 ? "day" : "days")", systemImage: "flame")
            settingsRow("Latest Entry", value: latestEntryText, systemImage: "clock")
        }
    }

    private var accountSection: some View {
        settingsGroup("Account") {
            settingsRow(
                "Subscription",
                value: subscriptionService.isSubscribed ? "Core active" : "Free",
                systemImage: subscriptionService.isSubscribed ? "checkmark.seal" : "seal"
            )

            if authService.isAuthenticated {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                        if isLoading { ProgressView() }
                    }
                }
            } else {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        Label("Sign in with Apple", systemImage: "apple.logo")
                        Spacer()
                        if isLoading { ProgressView() }
                    }
                }
            }
        }
    }

    private var appSection: some View {
        settingsGroup("App") {
            settingsRow("Version", value: appVersion, systemImage: "info.circle")
            settingsRow("Data", value: "Stored on device", systemImage: "lock")
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 14) {
                content()
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 24)
    }

    private func settingsRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MirrorTheme.primary)
                .frame(width: 30, height: 30)
                .background(MirrorTheme.primary.opacity(0.10), in: Circle())
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
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
