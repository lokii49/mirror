import SwiftUI
import SwiftData
import UserNotifications

private enum NudgePreset: String, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case custom = "Custom"

    var hour: Int {
        switch self {
        case .morning:   return 8
        case .afternoon: return 13
        case .evening:   return 20
        case .custom:    return -1
        }
    }

    var timeLabel: String {
        switch self {
        case .morning:   return "8:00 AM"
        case .afternoon: return "1:00 PM"
        case .evening:   return "8:00 PM"
        case .custom:    return "Pick a time"
        }
    }

    var icon: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening:   return "moon.stars.fill"
        case .custom:    return "slider.horizontal.3"
        }
    }
}

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Int = 0
    @State private var selectedReason: String? = nil
    @State private var nudgePreset: NudgePreset = .evening
    @State private var customNudgeTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 20
        c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var firstEntryText: String = ""
    @FocusState private var editorFocused: Bool

    private let reasons: [(String, String, Color)] = [
        ("brain.head.profile", "Understand myself better",   .blue),
        ("moon.stars",         "Process stress and emotions", MirrorTheme.violet),
        ("target",             "Track goals and habits",      .orange),
        ("sparkles",           "Build a reflection practice", .green),
    ]

    // Derive suggested preset from selected reason
    private var suggestedPreset: NudgePreset {
        selectedReason == "Track goals and habits" ? .morning : .evening
    }

    private var suggestedRationale: String {
        nudgePreset == .morning
            ? "Great for intention-setting before the day starts."
            : "Best for capturing the full day before it fades."
    }

    var body: some View {
        ZStack {
            MirrorTheme.bgBase
                .ignoresSafeArea()

            // Ambient glow orbs
            Circle()
                .fill(MirrorTheme.primary.opacity(0.07))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: 120, y: -180)
                .ignoresSafeArea()
            Circle()
                .fill(MirrorTheme.violetDim.opacity(0.6))
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .offset(x: -100, y: 300)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressIndicator
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                ZStack {
                    if step == 0 { welcomeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                    if step == 1 { reasonStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                    if step == 2 { timeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                    if step == 3 { writeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ctaButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Progress

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i < step
                          ? AnyShapeStyle(MirrorTheme.primary.opacity(0.5))
                          : i == step
                            ? AnyShapeStyle(MirrorTheme.accentGradient)
                            : AnyShapeStyle(Color.secondary.opacity(0.15)))
                    .frame(width: i == step ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                welcomeHeroCard
                welcomeFeatureRows
                sampleNudgePreview
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private var welcomeHeroCard: some View {
        ZStack(alignment: .bottomLeading) {
            // Background
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(
                    colors: [MirrorTheme.inkBase, Color(red: 0.10, green: 0.08, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            // Ambient glow — violet
            Circle()
                .fill(MirrorTheme.violet.opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 160, y: -90)

            // Ambient glow — primary
            Circle()
                .fill(MirrorTheme.primary.opacity(0.22))
                .frame(width: 160, height: 160)
                .blur(radius: 45)
                .offset(x: -30, y: 30)

            // Content
            VStack(alignment: .leading, spacing: 18) {
                // Sparkle mark
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MirrorTheme.primary, MirrorTheme.violetLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                // Wordmark
                VStack(alignment: .leading, spacing: 4) {
                    Text("mirror")
                        .font(.system(size: 58, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(.white)
                        .tracking(-1)

                    Text("your private thinking space")
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.65))
                        .italic()
                }

                // Privacy pill
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                    Text("All AI runs on your phone. Nothing leaves.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.10), in: Capsule())
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: MirrorTheme.primary.opacity(0.18), radius: 32, x: 0, y: 14)
    }

    private var welcomeFeatureRows: some View {
        VStack(spacing: 10) {
            welcomeFeatureRow(
                icon: "sparkles",
                title: "Daily reflections",
                subtitle: "Insights drawn from your own writing",
                color: MirrorTheme.primary
            )
            welcomeFeatureRow(
                icon: "icloud.fill",
                title: "Private iCloud sync",
                subtitle: "Encrypted — only accessible by you",
                color: .blue
            )
            welcomeFeatureRow(
                icon: "lock.shield.fill",
                title: "On-device AI",
                subtitle: "Your words never leave your phone",
                color: .green
            )
        }
    }

    private func welcomeFeatureRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .inkSurface(cornerRadius: 16)
    }

    private var sampleNudgePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                Text("Daily Reflection")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.primary)
                Spacer()
                Text("Today")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Text("\"You've mentioned feeling overwhelmed three times this week. What would make tomorrow feel lighter?\"")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(MirrorTheme.textSecondary)
                .lineSpacing(4)
                .italic()
        }
        .padding(16)
        .inkSurface(cornerRadius: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MirrorTheme.violet.opacity(0.20), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(MirrorTheme.accentGradient)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What brings you here?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Pick the one that resonates most.")
                    .font(.system(size: 15))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(reasons, id: \.1) { icon, label, color in
                    reasonButton(icon: icon, label: label, color: color)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var timeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When should mirror nudge you?")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("One gentle reminder a day to reflect.")
                        .font(.system(size: 15))
                        .foregroundStyle(MirrorTheme.textSecondary)
                }
                .padding(.top, 12)

                // Recommended banner
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(MirrorTheme.primary.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MirrorTheme.primary)
                    }
                    Text("Suggested: **\(suggestedPreset.rawValue)** (\(suggestedPreset.timeLabel)) — \(suggestedRationale)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MirrorTheme.violet.opacity(0.20), lineWidth: 1)
                }

                VStack(spacing: 10) {
                    ForEach(NudgePreset.allCases, id: \.self) { preset in
                        nudgePresetButton(preset)
                    }
                }

                if nudgePreset == .custom {
                    DatePicker("", selection: $customNudgeTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: nudgePreset)
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
    }

    private var writePrompt: String {
        switch selectedReason {
        case "Understand myself better":
            return "What's something you've been trying to figure out about yourself lately?"
        case "Process stress and emotions":
            return "What's weighing on you most right now? Even a few words helps."
        case "Track goals and habits":
            return "What are you working toward? Where are you at with it today?"
        case "Build a reflection practice":
            return "What happened today that's worth remembering?"
        default:
            return "What's on your mind right now?"
        }
    }

    private var writeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Write your first entry")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("A sentence is enough. Mirror learns from everything you write.")
                    .font(.system(size: 15))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            .padding(.top, 12)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MirrorTheme.inkMid)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                editorFocused
                                    ? AnyShapeStyle(MirrorTheme.violet.opacity(0.45))
                                    : AnyShapeStyle(MirrorTheme.inkBorder),
                                lineWidth: editorFocused ? 1.5 : 1
                            )
                    }
                    .shadow(
                        color: editorFocused ? MirrorTheme.violet.opacity(0.15) : .clear,
                        radius: 16, x: 0, y: 4
                    )

                if firstEntryText.isEmpty {
                    Text(writePrompt)
                        .foregroundStyle(MirrorTheme.textTertiary)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                }

                TextEditor(text: $firstEntryText)
                    .focused($editorFocused)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .animation(.easeInOut(duration: 0.2), value: editorFocused)

            HStack {
                Spacer()
                Text("\(firstEntryText.split(separator: " ").count) words")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(MirrorTheme.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editorFocused = false }
            }
        }
    }

    // MARK: - Choice Buttons

    private func reasonButton(icon: String, label: String, color: Color) -> some View {
        let isSelected = selectedReason == label
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedReason = label
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? color : Color.secondary.opacity(0.09))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : color.opacity(0.7))
                }
                .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: 8, x: 0, y: 3)

                Text(label)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background(isSelected ? color.opacity(0.08) : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? color.opacity(0.45) : MirrorTheme.inkBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .shadow(color: isSelected ? color.opacity(0.08) : .clear, radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedReason)
    }

    @ViewBuilder
    private func nudgePresetButton(_ preset: NudgePreset) -> some View {
        let isSelected = nudgePreset == preset
        let isRecommended = preset == suggestedPreset

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                nudgePreset = preset
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(MirrorTheme.accentGradient)
                              : AnyShapeStyle(Color.secondary.opacity(0.09)))
                        .frame(width: 44, height: 44)
                    Image(systemName: preset.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                .shadow(color: isSelected ? MirrorTheme.primary.opacity(0.3) : .clear, radius: 8, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(preset.rawValue)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        if isRecommended {
                            Text("Suggested")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MirrorTheme.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MirrorTheme.primary.opacity(0.10), in: Capsule())
                                .overlay(Capsule().stroke(MirrorTheme.primary.opacity(0.2), lineWidth: 1))
                        }
                    }
                    if preset != .custom {
                        Text(preset.timeLabel)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? AnyShapeStyle(MirrorTheme.primary.opacity(0.7)) : AnyShapeStyle(.tertiary))
                    }
                    if isRecommended && isSelected {
                        Text(suggestedRationale)
                            .font(.system(size: 12))
                            .foregroundStyle(MirrorTheme.primary.opacity(0.8))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(MirrorTheme.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background(isSelected ? MirrorTheme.violetDim : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected
                            ? AnyShapeStyle(MirrorTheme.violet.opacity(0.50))
                            : AnyShapeStyle(MirrorTheme.inkBorder),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .shadow(color: isSelected ? MirrorTheme.violet.opacity(0.10) : .clear, radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: nudgePreset)
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            advanceStep()
        } label: {
            HStack {
                Spacer()
                Text(step == 3 ? "Start journaling" : (step == 0 ? "Get started" : "Continue"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 54)
            .background(
                ctaEnabled ? AnyShapeStyle(MirrorTheme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.3)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!ctaEnabled)
        .shadow(color: ctaEnabled ? MirrorTheme.primary.opacity(0.28) : .clear, radius: 16, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.2), value: ctaEnabled)
    }

    private var ctaEnabled: Bool {
        switch step {
        case 0: return true
        case 1: return selectedReason != nil
        case 2: return true
        case 3: return true
        default: return false
        }
    }

    // MARK: - Logic

    private func advanceStep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if step == 1 {
            // Pre-select suggested preset based on reason
            nudgePreset = suggestedPreset
        }
        if step < 3 {
            withAnimation {
                step += 1
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        let nudgeHour: Int
        let nudgeMinute: Int

        if nudgePreset == .custom {
            let c = Calendar.current.dateComponents([.hour, .minute], from: customNudgeTime)
            nudgeHour = c.hour ?? 20
            nudgeMinute = c.minute ?? 0
        } else {
            nudgeHour = nudgePreset.hour
            nudgeMinute = 0
        }

        UserDefaults.standard.set(nudgeHour, forKey: "nudgeHour")
        UserDefaults.standard.set(nudgeMinute, forKey: "nudgeMinute")

        let text = firstEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let entry = Entry(text: text, source: .typed)
            modelContext.insert(entry)
        }

        let profile: UserProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfile()
            modelContext.insert(profile)
        }
        profile.onboardingComplete = true

        try? modelContext.save()

        // Prevent What's New sheet from firing for new installs — they have no "old version" to upgrade from
        FeatureCardService.shared.markWhatsNewSeen()

        // Request notification permission now — user just set their nudge time so
        // they understand why the prompt appears. Schedule the write-reminder immediately
        // after permission is granted so the first nudge fires at their chosen time.
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                await NotificationService.rescheduleContextualNudge(
                    hasWrittenToday: !firstEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    insightReady: false,
                    hour: nudgeHour,
                    minute: nudgeMinute
                )
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: UserProfile.self, Entry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return OnboardingFlow()
        .modelContainer(container)
}
