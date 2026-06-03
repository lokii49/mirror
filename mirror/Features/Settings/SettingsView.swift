import SwiftUI
import SwiftData
import UserNotifications
import CloudKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var modelContext
    @State private var subscriptionService = SubscriptionService.shared
    @State private var error: Error?
    @State private var showSubscription = false

    // Stats cache
    @State private var cachedTotalWords: Int = 0
    @State private var cachedStreak: Int = 0
    @State private var cachedLatestEntryText: String = "None"

    // MIRROR settings
    @AppStorage("nudgeHour") private var nudgeHour: Int = 8
    @AppStorage("nudgeMinute") private var nudgeMinute: Int = 0
    @State private var showNudgeTimePicker = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage: String = ""
    @State private var showLanguagePicker = false
    @State private var notificationPermission: UNAuthorizationStatus = .notDetermined

    // YOUR DATA
    @State private var iCloudStatus: String = "Checking..."
    @State private var showDeleteConfirmation = false
    @State private var showHowItWorks = false
    @State private var showFeatureGuide = false
    @State private var showImportPicker = false
    @State private var importResultMessage: String?
    @State private var showImportResult = false

    var nudgeTime: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = nudgeHour
        c.minute = nudgeMinute
        return Calendar.current.date(from: c) ?? Date()
    }

    private var iCloudStatusColor: Color {
        switch iCloudStatus {
        case "Active":    return .green
        case "No account": return .orange
        case "Restricted", "Error": return .red
        default:          return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    statsGrid
                    accountSection
                    mirrorSection
                    dataSection
                    aboutSection
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MirrorTheme.bgBase)
            .navigationTitle("Settings")
            .alert("Something went wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "")
            }
            .sheet(isPresented: $showHowItWorks) { howMirrorWorksSheet }
            .sheet(isPresented: $showFeatureGuide) { WhatsNewSheet(mode: .allFeatures) }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let count = importEntries(from: url)
                    importResultMessage = count > 0
                        ? "Imported \(count) entr\(count == 1 ? "y" : "ies")."
                        : "No entries found in file."
                    showImportResult = true
                case .failure:
                    importResultMessage = "Could not read file."
                    showImportResult = true
                }
            }
            .alert("Import", isPresented: $showImportResult) {
                Button("OK") { importResultMessage = nil }
            } message: {
                Text(importResultMessage ?? "")
            }
            .task {
                await subscriptionService.refresh()
                await subscriptionService.loadProducts()
                await checkNotificationPermission()
                await checkiCloudStatus()
            }
            .task(id: entries.count) {
                let snapshot = entries
                cachedTotalWords = snapshot.reduce(0) { $0 + $1.wordCount }
                cachedStreak = computeStreak(from: snapshot)
                cachedLatestEntryText = computeLatestEntryText(from: snapshot)
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                avatarView
                    .shadow(color: MirrorTheme.primary.opacity(0.25), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MirrorNotes")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)

                    if subscriptionService.isSubscribed {
                        let tierLabel = subscriptionService.isDeep ? "Deep" : "Core"
                        let tierColor = subscriptionService.isDeep ? Color.purple : MirrorTheme.primary
                        Label(tierLabel, systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tierColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(tierColor.opacity(0.12), in: Capsule())
                    } else {
                        Text("Free plan")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if subscriptionService.isSubscribed {
                    let tierColor = subscriptionService.isDeep ? Color.purple : MirrorTheme.primary
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(tierColor)
                }
            }

            if !subscriptionService.isSubscribed {
                Divider()
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Button { showSubscription = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Unlock daily reflections with Core")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(MirrorTheme.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MirrorTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .futureSurface(cornerRadius: 26)
    }

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(MirrorTheme.accentGradient)
                .frame(width: 58, height: 58)
            Image(systemName: "person.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
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

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                statCard(value: "\(entries.count)", label: "Entries", icon: "book.pages", color: MirrorTheme.primary)
                statCard(value: cachedTotalWords.formatted(), label: "Words", icon: "text.word.spacing", color: .blue)
                statCard(value: "\(cachedStreak)", label: "Day streak", icon: "flame.fill", color: .orange)
                statCard(value: cachedLatestEntryText, label: "Last entry", icon: "clock.fill", color: .green)
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
                        "Subscription",
                        systemImage: subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal",
                        iconColor: subscriptionService.isSubscribed ? MirrorTheme.primary : .secondary
                    )
                    Spacer()
                    Text(subscriptionService.isDeep ? "Deep" : subscriptionService.isSubscribed ? "Core" : "Free")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSubscription) { SubscriptionView() }
        }
    }

    // MARK: - Mirror Section

    private var mirrorSection: some View {
        settingsGroup("MirrorNotes") {
            // Daily nudge time — Core only
            if subscriptionService.isSubscribed {
                Button { withAnimation { showNudgeTimePicker.toggle() } } label: {
                    HStack {
                        settingsRowLabel("Daily nudge time", systemImage: "bell.fill", iconColor: .orange)
                        Spacer()
                        Text(nudgeTime, style: .time)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        chevron
                            .rotationEffect(.degrees(showNudgeTimePicker ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: showNudgeTimePicker)
                    }
                }
                .buttonStyle(.plain)

                if showNudgeTimePicker {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { nudgeTime },
                            set: { date in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                nudgeHour = c.hour ?? 8
                                nudgeMinute = c.minute ?? 0
                                Task {
                                    let insightReady = mirrorApp.hasDailyNudgeForToday(context: modelContext)
                                    let hasWritten = mirrorApp.hasEntryToday(context: modelContext)
                                    await NotificationService.rescheduleContextualNudge(
                                        hasWrittenToday: hasWritten,
                                        insightReady: insightReady,
                                        hour: nudgeHour,
                                        minute: nudgeMinute
                                    )
                                }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                Button { showSubscription = true } label: {
                    HStack {
                        settingsRowLabel("Daily nudge time", systemImage: "bell.fill", iconColor: .orange)
                            .opacity(0.45)
                        Spacer()
                        Label("Core", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MirrorTheme.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(MirrorTheme.primary.opacity(0.12), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSubscription) { SubscriptionView() }
            }

            Divider().padding(.leading, 48)

            HStack {
                settingsRowLabel("Weekly digest day", systemImage: "calendar", iconColor: .blue)
                    .opacity(subscriptionService.isSubscribed ? 1 : 0.45)
                Spacer()
                if subscriptionService.isSubscribed {
                    Text("Sunday")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Label("Core", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MirrorTheme.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(MirrorTheme.primary.opacity(0.12), in: Capsule())
                }
            }

            Divider().padding(.leading, 48)

            Button { showLanguagePicker = true } label: {
                HStack {
                    settingsRowLabel("Voice transcription language", systemImage: "mic.fill", iconColor: .purple)
                    Spacer()
                    let langName = VoiceTranscriptionService.pickerLanguages.first(where: { $0.id == transcriptionLanguage })?.displayName ?? "Automatic"
                    Text(langName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    chevron
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showLanguagePicker) {
                TranscriptionLanguagePickerView(selected: $transcriptionLanguage)
            }

            Divider().padding(.leading, 48)

            HStack {
                settingsRowLabel("Notifications", systemImage: "bell.badge.fill", iconColor: MirrorTheme.primary)
                Spacer()
                if notificationPermission == .denied {
                    Text("Disabled in Settings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .onChange(of: notificationsEnabled) { _, enabled in
                            if enabled {
                                requestNotificationPermission()
                            } else {
                                NotificationService.cancelAll()
                            }
                        }
                }
            }
        }
    }

    // MARK: - Your Data Section

    private var dataSection: some View {
        settingsGroup("Your Data") {
            ShareLink(
                item: exportedText,
                subject: Text("MirrorNotes Export"),
                message: Text("My journal entries from Mirror")
            ) {
                HStack {
                    settingsRowLabel("Export all entries", systemImage: "square.and.arrow.up", iconColor: .green)
                    Spacer()
                    chevron
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button { showImportPicker = true } label: {
                HStack {
                    settingsRowLabel("Import entries", systemImage: "square.and.arrow.down", iconColor: .blue)
                    Spacer()
                    chevron
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            HStack {
                settingsRowLabel("iCloud sync", systemImage: "icloud.fill", iconColor: .blue)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(iCloudStatusColor)
                        .frame(width: 7, height: 7)
                    Text(iCloudStatus)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.leading, 48)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    settingsRowLabel("Delete all data", systemImage: "trash.fill", iconColor: .red)
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Delete all journal data?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently deletes all entries and insights from this device and iCloud. Cannot be undone.")
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        settingsGroup("About") {
            Button { showHowItWorks = true } label: {
                HStack {
                    settingsRowLabel("How mirror works", systemImage: "sparkles", iconColor: MirrorTheme.primary)
                    Spacer()
                    chevron
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button { showFeatureGuide = true } label: {
                HStack {
                    settingsRowLabel("What's New & features", systemImage: "square.grid.3x3", iconColor: MirrorTheme.primary)
                    Spacer()
                    chevron
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            if let privacyURL = AppConstants.privacyPolicyURL {
                Link(destination: privacyURL) {
                    HStack {
                        settingsRowLabel("Privacy policy", systemImage: "hand.raised.fill", iconColor: .green)
                        Spacer()
                        chevron
                    }
                }
                .foregroundStyle(.primary)
            } else {
                settingsRow("Privacy policy", systemImage: "hand.raised.fill", iconColor: .green)
            }

            Divider().padding(.leading, 48)

            if let reviewURL = AppConstants.appStoreReviewURL {
                Button {
                    UIApplication.shared.open(reviewURL)
                } label: {
                    HStack {
                        settingsRowLabel("Rate mirror", systemImage: "star.fill", iconColor: .yellow)
                        Spacer()
                        chevron
                    }
                }
                .buttonStyle(.plain)
            } else {
                settingsRow("Rate mirror", systemImage: "star.fill", iconColor: .yellow)
                    .opacity(0.4)
            }

            Divider().padding(.leading, 48)

            settingsRow("Version \(appVersion)", systemImage: "info.circle", iconColor: .blue)
        }
    }

    // MARK: - How Mirror Works Sheet

    private var howMirrorWorksSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    privacyStep(
                        number: "1",
                        title: "You write on your device",
                        body: "Your entries are stored locally using SwiftData and backed up privately to your iCloud. Nothing leaves your device without your action.",
                        icon: "pencil.and.outline",
                        color: MirrorTheme.primary
                    )
                    privacyStep(
                        number: "2",
                        title: "AI runs on your device",
                        body: "mirror uses an on-device language model to generate insights. Your journal text never touches our servers. Ever.",
                        icon: "cpu.fill",
                        color: .blue
                    )
                    privacyStep(
                        number: "3",
                        title: "Only the insight is saved",
                        body: "The generated nudge or reflection is saved to your device. Not what you wrote — only what MirrorNotes noticed.",
                        icon: "sparkles",
                        color: .orange
                    )
                    privacyStep(
                        number: "4",
                        title: "Your data is always yours",
                        body: "Free users keep full access to all their entries forever. Cancelling a subscription never deletes your journal.",
                        icon: "lock.shield.fill",
                        color: .green
                    )
                }
                .padding(20)
            }
            .background(MirrorTheme.bgBase)
            .navigationTitle("How mirror works")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showHowItWorks = false }
                }
            }
        }
    }

    private func privacyStep(number: String, title: String, body: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(body)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .futureSurface(cornerRadius: 20)
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        settingsGroup("Developer") {
            Button {
                SampleData.seed(into: modelContext)
            } label: {
                HStack {
                    settingsRowLabel("Load Sample Entries (Mixed)", systemImage: "doc.badge.plus", iconColor: .orange)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button {
                SampleData.seedYearLongMixed(into: modelContext)
            } label: {
                HStack {
                    settingsRowLabel("Load Year Long Entries (Mixed)", systemImage: "calendar.badge.plus", iconColor: .orange)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button {
                SampleData.seedVoiceOnly(into: modelContext)
            } label: {
                HStack {
                    settingsRowLabel("Load Voice Notes Only", systemImage: "mic.badge.plus", iconColor: .orange)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button(role: .destructive) {
                SampleData.clearSampleEntries(from: modelContext)
            } label: {
                HStack {
                    settingsRowLabel("Clear Sample Entries Only", systemImage: "doc.badge.minus", iconColor: .red)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button(role: .destructive) {
                SampleData.clearInsights(from: modelContext)
            } label: {
                HStack {
                    settingsRowLabel("Clear Insight Cache", systemImage: "sparkles.slash", iconColor: .orange)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 48)

            Button(role: .destructive) {
                SampleData.clear(from: modelContext)
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

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var exportedText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return entries.map { entry in
            var block = "[\(formatter.string(from: entry.createdAt))]"
            if let mood = entry.mood { block += "\n[Mood: \(mood)]" }
            block += "\n\(entry.text)"
            return block
        }
        .joined(separator: "\n\n---\n\n")
    }

    private func deleteAllData() {
        if let all = try? modelContext.fetch(FetchDescriptor<Entry>()) {
            all.forEach { modelContext.delete($0) }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<Insight>()) {
            all.forEach { modelContext.delete($0) }
        }
        try? modelContext.save()
    }

    private func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = settings.authorizationStatus
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            // keep AppStorage value as-is
        } else if settings.authorizationStatus == .denied {
            notificationsEnabled = false
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                notificationPermission = granted ? .authorized : .denied
                if !granted { notificationsEnabled = false }
            }
        }
    }

    private func checkiCloudStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            await MainActor.run {
                switch status {
                case .available: iCloudStatus = "Active"
                case .noAccount: iCloudStatus = "No account"
                case .restricted: iCloudStatus = "Restricted"
                case .temporarilyUnavailable: iCloudStatus = "Unavailable"
                default: iCloudStatus = "Unknown"
                }
            }
        } catch {
            await MainActor.run { iCloudStatus = "Error" }
        }
    }

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

    private func computeLatestEntryText(from snapshot: [Entry]) -> String {
        guard let latest = snapshot.first?.createdAt else { return "None" }
        if Calendar.current.isDateInToday(latest) { return "Today" }
        if Calendar.current.isDateInYesterday(latest) { return "Yesterday" }
        return latest.formatted(date: .abbreviated, time: .omitted)
    }

    private func computeStreak(from snapshot: [Entry]) -> Int {
        let calendar = Calendar.current
        let days = Set(snapshot.map { calendar.startOfDay(for: $0.createdAt) })
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

    // MARK: - Import

    @discardableResult
    private func importEntries(from url: URL) -> Int {
        guard url.startAccessingSecurityScopedResource() else { return 0 }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return 0 }

        let separator = "\n\n---\n\n"
        var count = 0

        if raw.contains(separator) {
            // Mirror export format: split by separator, parse each block
            let blocks = raw.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for block in blocks {
                if insertEntry(fromBlock: block) { count += 1 }
            }
        } else {
            // Plain text — whole file becomes one entry dated today
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let entry = Entry(text: trimmed, source: .typed)
                modelContext.insert(entry)
                count = 1
            }
        }

        try? modelContext.save()
        return count
    }

    /// Returns `true` if an entry was successfully inserted.
    private func insertEntry(fromBlock block: String) -> Bool {
        var lines = block.components(separatedBy: "\n")
        var date = Date()
        var mood: String? = nil

        // Parse date header: "[May 27, 2026 at 6:07 PM]"
        if let header = lines.first, header.hasPrefix("["), header.hasSuffix("]") {
            let inner = String(header.dropFirst().dropLast())
            if !inner.hasPrefix("Mood:") {
                date = parseMirrorDate(inner) ?? Date()
                lines.removeFirst()
            }
        }

        // Parse optional mood line: "[Mood: Hopeful]"
        if let moodLine = lines.first,
           moodLine.hasPrefix("[Mood: "), moodLine.hasSuffix("]") {
            let moodStr = String(moodLine.dropFirst("[Mood: ".count).dropLast())
            if MirrorTheme.moodOptions.contains(moodStr) {
                mood = moodStr
                lines.removeFirst()
            }
        }

        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let entry = Entry(text: text, mood: mood, source: .typed)
        entry.createdAt = date
        entry.weekIdentifier = DateHelpers.weekIdentifier(for: date)
        modelContext.insert(entry)
        return true
    }

    private func parseMirrorDate(_ string: String) -> Date? {
        // Use the same style as exportedText — locale-matched round-trip
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.date(from: string)
    }
}

struct TranscriptionLanguagePickerView: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Download language models", systemImage: "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Some languages (e.g. Telugu, Tamil, Kannada) use Apple's on-device speech model. If transcription fails, the model may not be downloaded yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("To download: **iOS Settings → General → Language & Region → Add Language**")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(VoiceTranscriptionService.pickerLanguages) { lang in
                        Button {
                            selected = lang.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected == lang.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voice Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
