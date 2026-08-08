import SwiftUI
import SwiftData
import UserNotifications
import CloudKit
import UniformTypeIdentifiers

enum ICloudStatus {
    case checking, active, noAccount, restricted, unavailable, unknown, error

    var color: Color {
        switch self {
        case .active:      return .green
        case .noAccount:   return .orange
        case .restricted, .error: return .red
        default:           return .secondary
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .checking:    return "Checking..."
        case .active:      return "Active"
        case .noAccount:   return "No account"
        case .restricted:  return "Restricted"
        case .unavailable: return "Unavailable"
        case .unknown:     return "Unknown"
        case .error:       return "Error"
        }
    }
}

struct SettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) var entries: [Entry]
    @Query var profiles: [UserProfile]
    @Environment(\.modelContext) var modelContext

    var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { profiles.first?.displayMode ?? .classic },
            set: { newValue in
                profiles.first?.displayMode = newValue
                try? modelContext.save()
            }
        )
    }
    @State var subscriptionService = SubscriptionService.shared
    @State var error: Error?
    @State var showSubscription = false

    // Stats cache
    @State var cachedTotalWords: Int = 0
    @State var cachedStreak: Int = 0
    @State var cachedLatestEntryText: String = String(localized: "None")

    // MIRROR settings
    @AppStorage("mirrorAppearanceMode") var appearanceMode: String = "system"
    var appearanceModeLabel: String {
        switch appearanceMode {
        case "light": return String(localized: "Light")
        case "dark": return String(localized: "Dark")
        default: return String(localized: "System")
        }
    }
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
    @State var iCloudStatus: ICloudStatus = .checking
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

    var iCloudStatusColor: Color { iCloudStatus.color }

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
                    if count > 0 {
                        importResultMessage = count == 1
                            ? String(localized: "Imported 1 entry.")
                            : String(localized: "Imported \(count) entries.")
                    } else {
                        importResultMessage = String(localized: "No entries found in file.")
                    }
                    showImportResult = true
                case .failure:
                    importResultMessage = String(localized: "Could not read file.")
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
