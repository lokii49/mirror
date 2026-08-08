import SwiftUI
import SwiftData

extension SettingsView {
    // MARK: - Profile Card

    var profileCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                avatarView
                    .shadow(color: MirrorTheme.primary.opacity(0.25), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MirrorNotes")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)

                    if SubscriptionService.allFeaturesFree {
                        Label("Early Access", systemImage: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MirrorTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(MirrorTheme.primary.opacity(0.12), in: Capsule())
                    } else if subscriptionService.isSubscribed {
                        let tierLabel: LocalizedStringKey = subscriptionService.isDeep ? "Deep" : "Core"
                        let tierColor = subscriptionService.isDeep ? MirrorTheme.violet : MirrorTheme.primary
                        Label(tierLabel, systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tierColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(tierColor.opacity(0.12), in: Capsule())
                    } else {
                        Text("Free plan")
                            .font(.system(size: 13))
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                }

                Spacer()

                if SubscriptionService.allFeaturesFree {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22))
                        .foregroundStyle(MirrorTheme.primary)
                } else if subscriptionService.isSubscribed {
                    let tierColor = subscriptionService.isDeep ? MirrorTheme.violet : MirrorTheme.primary
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(tierColor)
                }
            }

            if !SubscriptionService.allFeaturesFree && !subscriptionService.isSubscribed {
                Divider()
                    .overlay(MirrorTheme.inkBorder)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        upgradeChip("Daily Reflection", icon: "sparkles")
                        upgradeChip("Ask", icon: "bubble.left.and.bubble.right")
                        upgradeChip("Weekly Digest", icon: "calendar.badge.clock")
                        upgradeChip("Auto Mood", icon: "face.smiling")
                    }
                    .padding(.horizontal, 1)
                }
                .padding(.bottom, 10)

                Button { showSubscription = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Start 7-day free trial")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer(minLength: 4)
                        Text("Core · $2.99/mo")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.65)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(MirrorTheme.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(MirrorTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MirrorTheme.primary.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .themedCard(cornerRadius: 26)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    subscriptionService.isDeep ? MirrorTheme.violet.opacity(0.22)
                    : subscriptionService.isSubscribed ? MirrorTheme.primary.opacity(0.22)
                    : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    var avatarView: some View {
        ZStack {
            Circle()
                .fill(subscriptionService.isDeep
                    ? LinearGradient(colors: [MirrorTheme.violet, MirrorTheme.violetLight], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : MirrorTheme.accentGradient)
                .frame(width: 58, height: 58)
            Image(systemName: "person.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Stats Grid

    var statsGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your journal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MirrorTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(1.0)
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
        .themedCard(cornerRadius: 24)
    }

    func statCard(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
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
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Account Section

    var accountSection: some View {
        SettingsGroup(title: "Account") {
            Button { showSubscription = true } label: {
                HStack {
                    SettingsRowLabel(
                        title: "Subscription",
                        systemImage: SubscriptionService.allFeaturesFree ? "sparkles" : (subscriptionService.isSubscribed ? "checkmark.seal.fill" : "seal"),
                        iconColor: SubscriptionService.allFeaturesFree ? MirrorTheme.primary : (subscriptionService.isSubscribed ? MirrorTheme.primary : .secondary)
                    )
                    Spacer()
                    Text(SubscriptionService.allFeaturesFree ? "Early Access" : (subscriptionService.isDeep ? "Deep" : subscriptionService.isSubscribed ? "Core" : "Free"))
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                    SettingsChevron()
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSubscription) { SubscriptionView() }
        }
    }

    /// Small preview card for the Classic/Sentinel picker — deliberately
    /// duplicated from OnboardingFlow's modeCard (private there) rather than
    /// sharing, since the two need different bindings and this is short
    /// enough that a shared abstraction wouldn't earn its keep.
    func displayModePickerCard(mode: DisplayMode, title: String, accent: Color) -> some View {
        let isSelected = displayModeBinding.wrappedValue == mode
        return Button {
            displayModeBinding.wrappedValue = mode
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? MirrorTheme.textPrimary : MirrorTheme.textSecondary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? accent.opacity(0.10) : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.5) : MirrorTheme.inkBorder, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appearance Section

    var appearanceSection: some View {
        SettingsGroup(title: "Appearance") {
            HStack {
                SettingsRowLabel(title: "Appearance", systemImage: "circle.lefthalf.filled", iconColor: .indigo)
                Spacer()
                Menu {
                    Button("System") { appearanceMode = "system" }
                    Button("Light") { appearanceMode = "light" }
                    Button("Dark") { appearanceMode = "dark" }
                } label: {
                    HStack(spacing: 4) {
                        Text(appearanceModeLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(MirrorTheme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                }
            }

            SettingsDivider()

            VStack(alignment: .leading, spacing: 10) {
                SettingsRowLabel(title: "Display mode", systemImage: "square.stack.3d.up.fill", iconColor: MirrorTheme.violet)
                HStack(spacing: 10) {
                    displayModePickerCard(mode: .classic, title: "Classic", accent: MirrorTheme.violet)
                    displayModePickerCard(mode: .sentinel, title: "Sentinel", accent: MirrorTheme.ember)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    func upgradeChip(_ label: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(MirrorTheme.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(MirrorTheme.primary.opacity(0.08), in: Capsule())
    }

    func computeLatestEntryText(from snapshot: [Entry]) -> String {
        guard let latest = snapshot.first?.createdAt else { return String(localized: "None") }
        if Calendar.current.isDateInToday(latest) { return String(localized: "Today") }
        if Calendar.current.isDateInYesterday(latest) { return String(localized: "Yesterday") }
        return latest.formatted(date: .abbreviated, time: .omitted)
    }

    func computeStreak(from snapshot: [Entry]) -> Int {
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
}
