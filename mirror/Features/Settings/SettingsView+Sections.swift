import SwiftUI
import SwiftData

extension SettingsView {
    // MARK: - Profile Card

    var profileCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                avatarView
                    .shadow(color: (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary).opacity(0.25), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MirrorNotes")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)

                    if SubscriptionService.allFeaturesFree {
                        planChip("Early Access", systemImage: "sparkles", color: displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary)
                    } else if subscriptionService.isSubscribed {
                        let tierLabel: LocalizedStringKey = subscriptionService.isDeep ? "Deep" : "Core"
                        let tierColor = displayMode == .sentinel ? MirrorTheme.ember : (subscriptionService.isDeep ? MirrorTheme.violet : MirrorTheme.primary)
                        planChip(tierLabel, systemImage: "checkmark.seal.fill", color: tierColor)
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
                    let accent = displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Start 7-day free trial")
                            .font(displayMode == .sentinel ? MirrorTheme.mono(13, weight: .bold) : .system(size: 14, weight: .semibold))
                            .textCase(displayMode == .sentinel ? .uppercase : nil)
                        Spacer(minLength: 4)
                        Text("Core · $2.99/mo")
                            .font(displayMode == .sentinel ? MirrorTheme.mono(11.5) : .system(size: 12, weight: .medium))
                            .opacity(0.65)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 12, style: .continuous)
                            .stroke(accent.opacity(displayMode == .sentinel ? 0.35 : 0.18), lineWidth: 1)
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

    // There's no account system and no profile photo — a person-silhouette
    // avatar implies personalization that doesn't exist. The app icon is
    // the only identity this screen actually has, same mark the welcome
    // screen uses.
    var avatarView: some View {
        let corner: CGFloat = displayMode == .sentinel ? 10 : 14
        return Image("AppIconDisplay")
            .resizable()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(MirrorTheme.ember.opacity(0.35), lineWidth: 1)
                }
            }
    }

    // MARK: - Stats Grid

    var statsGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayMode == .sentinel ? "Log stats" : "Your journal")
                .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .semibold))
                .foregroundStyle(MirrorTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(displayMode == .sentinel ? 0.6 : 1.0)
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
                RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(color.opacity(0.3), lineWidth: 1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(displayMode == .sentinel ? MirrorTheme.mono(19, weight: .bold) : .system(size: 20, weight: .bold, design: .rounded))
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
            .sheet(isPresented: $showSubscription) { SubscriptionView().environment(\.appDisplayMode, displayMode) }
        }
    }

    /// Small preview card for the Classic/Sentinel picker — deliberately
    /// duplicated from OnboardingFlow's modeCard (private there) rather than
    /// sharing, since the two need different bindings and this is short
    /// enough that a shared abstraction wouldn't earn its keep.
    func displayModePickerCard(mode: DisplayMode, title: LocalizedStringKey, accent: Color) -> some View {
        let isSelected = displayModeBinding.wrappedValue == mode
        return Button {
            displayModeBinding.wrappedValue = mode
        } label: {
            let cardCorner: CGFloat = displayMode == .sentinel ? 7 : 12
            HStack(spacing: 6) {
                Text(title)
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12.5, weight: .bold) : .system(size: 13, weight: .semibold))
                    .textCase(displayMode == .sentinel ? .uppercase : nil)
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
            .background(isSelected ? accent.opacity(0.10) : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
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
                        SettingsValueText(text: appearanceModeLabel)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MirrorTheme.textSecondary)
                    }
                }
                .disabled(displayMode == .sentinel)
                .opacity(displayMode == .sentinel ? 0.4 : 1)
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

    /// Plan/tier chip on the profile card — rectangular mono in Sentinel,
    /// matching SettingsTierBadge's shape swap, since it's the same kind
    /// of status readout.
    func planChip(_ label: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(displayMode == .sentinel ? MirrorTheme.mono(11, weight: .bold) : .system(size: 12, weight: .semibold))
            .textCase(displayMode == .sentinel ? .uppercase : nil)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                color.opacity(0.12),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
            )
            .overlay {
                if displayMode == .sentinel {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(color.opacity(0.3), lineWidth: 1)
                }
            }
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
