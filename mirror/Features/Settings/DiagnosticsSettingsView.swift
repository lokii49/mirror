#if DEBUG
import SwiftUI
import SwiftData

/// "Developer" in Classic, "Diagnostics" in Sentinel — debug-only tools,
/// never shown in release builds.
struct DiagnosticsSettingsView: View {
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appDisplayMode) private var displayMode
    @State private var encryptionReport: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsGroup(title: "Developer") {
                    Button {
                        let unreadable = entries.filter(\.textDecryptionFailed).count
                        encryptionReport = MirrorEncryption.diagnosticsReport()
                            + "\nentries unreadable: \(unreadable)/\(entries.count)"
                    } label: {
                        SettingsRowLabel(title: "Encryption Diagnostics", systemImage: "key.viewfinder", iconColor: .orange)
                    }
                    .buttonStyle(.plain)
                    .alert("Encryption Diagnostics", isPresented: .init(
                        get: { encryptionReport != nil },
                        set: { if !$0 { encryptionReport = nil } }
                    )) {
                        Button("Copy") { UIPasteboard.general.string = encryptionReport }
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(encryptionReport ?? "")
                    }

                    SettingsDivider()

                    Button(role: .destructive) {
                        ModelDownloadManager.shared.deleteInstalledModelForTesting()
                    } label: {
                        SettingsRowLabel(title: "Delete Downloaded AI Model", systemImage: "brain.head.profile", iconColor: .red)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        SampleData.seed(into: modelContext)
                    } label: {
                        SettingsRowLabel(title: "Load Sample Entries (Mixed)", systemImage: "doc.badge.plus", iconColor: .orange)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        SampleData.seedYearLongMixed(into: modelContext)
                    } label: {
                        SettingsRowLabel(title: "Load Year Long Entries (Mixed)", systemImage: "calendar.badge.plus", iconColor: .orange)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        SampleData.seedVoiceOnly(into: modelContext)
                    } label: {
                        SettingsRowLabel(title: "Load Voice Notes Only", systemImage: "mic.badge.plus", iconColor: .orange)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button(role: .destructive) {
                        SampleData.clearSampleEntries(from: modelContext)
                    } label: {
                        SettingsRowLabel(title: "Clear Sample Entries Only", systemImage: "doc.badge.minus", iconColor: .red)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button(role: .destructive) {
                        SampleData.clearInsights(from: modelContext)
                    } label: {
                        SettingsRowLabel(title: "Clear Insight Cache", systemImage: "sparkles.slash", iconColor: .orange)
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button(role: .destructive) {
                        SampleData.clear(from: modelContext)
                    } label: {
                        SettingsRowLabel(title: "Clear All Data", systemImage: "trash", iconColor: .red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle(displayMode == .sentinel ? "Diagnostics" : "Developer")
        .navigationBarTitleDisplayMode(.large)
    }
}
#endif
