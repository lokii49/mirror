import SwiftUI
import SwiftData

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

/// Root Settings screen ("Config" in Sentinel) — profile, stats, the
/// Appearance/Display-mode switch (kept inline since it's the one control
/// worth surfacing immediately), and a short list of category rows pushing
/// to ProtocolSettingsView / ArchiveSettingsView / ManualSettingsView /
/// DiagnosticsSettingsView. Previously this screen held every individual
/// row (~25 of them) inline — moved out once that made it unmanageable
/// and hard to give Sentinel screens of their own.
struct SettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) var entries: [Entry]
    @Query var profiles: [UserProfile]
    @Environment(\.modelContext) var modelContext
    @Environment(\.appDisplayMode) private var displayMode

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

    @State var cachedTotalWords: Int = 0
    @State var cachedStreak: Int = 0
    @State var cachedLatestEntryText: String = String(localized: "None")

    @AppStorage("mirrorAppearanceMode") var appearanceMode: String = "system"
    var appearanceModeLabel: String {
        switch appearanceMode {
        case "light": return String(localized: "Light")
        case "dark": return String(localized: "Dark")
        default: return String(localized: "System")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    profileCard
                    statsGrid
                    accountSection
                    appearanceSection

                    VStack(spacing: 10) {
                        NavigationLink {
                            ProtocolSettingsView()
                        } label: {
                            SettingsCategoryRow(
                                title: displayMode == .sentinel ? "Protocol" : "Journal",
                                subtitle: "Nudges, digest, transcription",
                                systemImage: "bell.and.waves.left.and.right.fill",
                                iconColor: .orange
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ArchiveSettingsView()
                        } label: {
                            SettingsCategoryRow(
                                title: displayMode == .sentinel ? "Archive" : "Your Data",
                                subtitle: "Export, import, iCloud sync",
                                systemImage: "archivebox.fill",
                                iconColor: .blue
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ManualSettingsView()
                        } label: {
                            SettingsCategoryRow(
                                title: displayMode == .sentinel ? "Manual" : "About",
                                subtitle: "How it works, privacy, feedback",
                                systemImage: "book.fill",
                                iconColor: .green
                            )
                        }
                        .buttonStyle(.plain)

                        #if DEBUG
                        NavigationLink {
                            DiagnosticsSettingsView()
                        } label: {
                            SettingsCategoryRow(
                                title: displayMode == .sentinel ? "Diagnostics" : "Developer",
                                subtitle: "Debug-only tools",
                                systemImage: "wrench.and.screwdriver.fill",
                                iconColor: .red
                            )
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MirrorTheme.bgBase)
            .navigationTitle(displayMode == .sentinel ? "Config" : "Settings")
            .alert("Something went wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "")
            }
            .task {
                await subscriptionService.refresh()
                await subscriptionService.loadProducts()
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
