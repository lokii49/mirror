import SwiftUI
import SwiftData
import UserNotifications
import CloudKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) var entries: [Entry]
    @Environment(\.modelContext) var modelContext
    @State var subscriptionService = SubscriptionService.shared
    @State var error: Error?
    @State var showSubscription = false

    // Stats cache
    @State var cachedTotalWords: Int = 0
    @State var cachedStreak: Int = 0
    @State var cachedLatestEntryText: String = "None"

    // MIRROR settings
    @AppStorage("mirrorAppearanceMode") var appearanceMode: String = "system"
    @AppStorage("nudgeHour") var nudgeHour: Int = 8
    @AppStorage("nudgeMinute") var nudgeMinute: Int = 0
    @State var showNudgeTimePicker = false
    @AppStorage("writingReminderEnabled") var writingReminderEnabled: Bool = false
    @AppStorage("writingReminderHour") var writingReminderHour: Int = 9
    @AppStorage("writingReminderMinute") var writingReminderMinute: Int = 0
    @State var showWritingReminderPicker = false
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("transcriptionLanguage") var transcriptionLanguage: String = ""
    @State var showLanguagePicker = false
    @State var notificationPermission: UNAuthorizationStatus = .notDetermined

    // YOUR DATA
    @State var iCloudStatus: String = "Checking..."
    @State var showDeleteConfirmation = false
    @State var showHowItWorks = false
    @State var showFeatureGuide = false
    @State var showImportPicker = false
    @State var importResultMessage: String?
    @State var showImportResult = false
    @State var encryptionReport: String?

    var nudgeTime: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = nudgeHour
        c.minute = nudgeMinute
        return Calendar.current.date(from: c) ?? Date()
    }

    var writingReminderTime: Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = writingReminderHour
        c.minute = writingReminderMinute
        return Calendar.current.date(from: c) ?? Date()
    }

    var iCloudStatusColor: Color {
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
}
