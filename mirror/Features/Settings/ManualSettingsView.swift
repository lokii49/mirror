import SwiftUI

/// "About" in Classic, "Manual" in Sentinel — how the app works, what's
/// new, privacy policy, rating, feedback, version.
struct ManualSettingsView: View {
    @Environment(\.appDisplayMode) private var displayMode
    @State private var showHowItWorks = false
    @State private var showFeatureGuide = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsGroup(title: "About") {
                    Button { showHowItWorks = true } label: {
                        HStack {
                            SettingsRowLabel(title: "How mirror works", systemImage: "info.circle.fill", iconColor: .blue)
                            Spacer()
                            SettingsChevron()
                        }
                    }
                    .buttonStyle(.plain)

                    if FeatureCardService.shared.shouldShowWhatsNew {
                        SettingsDivider()

                        Button { showFeatureGuide = true } label: {
                            HStack {
                                SettingsRowLabel(title: "What's New", systemImage: "wand.and.stars", iconColor: MirrorTheme.violet)
                                Spacer()
                                if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                                    Text("v\(v)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(MirrorTheme.violetLight)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(MirrorTheme.violetDim, in: Capsule())
                                }
                                SettingsChevron()
                            }
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showFeatureGuide) { WhatsNewSheet(mode: .whatsNew).environment(\.appDisplayMode, displayMode) }
                    }

                    SettingsDivider()

                    if let privacyURL = AppConstants.privacyPolicyURL {
                        Link(destination: privacyURL) {
                            HStack {
                                SettingsRowLabel(title: "Privacy policy", systemImage: "hand.raised.fill", iconColor: .green)
                                Spacer()
                                SettingsChevron()
                            }
                        }
                        .foregroundStyle(MirrorTheme.textPrimary)
                    } else {
                        SettingsRowLabel(title: "Privacy policy", systemImage: "hand.raised.fill", iconColor: .green)
                    }

                    SettingsDivider()

                    if let reviewURL = AppConstants.appStoreReviewURL {
                        Button {
                            UIApplication.shared.open(reviewURL)
                        } label: {
                            HStack {
                                SettingsRowLabel(title: "Rate mirror", systemImage: "star.fill", iconColor: .yellow)
                                Spacer()
                                SettingsChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        SettingsRowLabel(title: "Rate mirror", systemImage: "star.fill", iconColor: .yellow)
                            .opacity(0.4)
                    }

                    SettingsDivider()

                    if let feedbackURL = AppConstants.feedbackURL {
                        Button {
                            UIApplication.shared.open(feedbackURL)
                        } label: {
                            HStack {
                                SettingsRowLabel(title: "Send feedback", systemImage: "envelope.fill", iconColor: .teal)
                                Spacer()
                                SettingsChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsDivider()

                    SettingsRowLabel(title: "Version \(appVersion)", systemImage: "info.circle", iconColor: .secondary)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(MirrorTheme.bgBase)
        .navigationTitle(displayMode == .sentinel ? "Manual" : "About")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showHowItWorks) { howMirrorWorksSheet }
    }

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

    private func privacyStep(number: String, title: LocalizedStringKey, body: LocalizedStringKey, icon: String, color: Color) -> some View {
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
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .themedCard(cornerRadius: 20)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
