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

    var displayName: LocalizedStringKey {
        switch self {
        case .morning:   return "Morning"
        case .afternoon: return "Afternoon"
        case .evening:   return "Evening"
        case .custom:    return "Custom"
        }
    }

    // A locale-correct clock reading (12h/24h per the user's region), not a
    // translated phrase — "8:00 AM" would be nonsensical to hand-translate.
    var timeLabel: String {
        guard self != .custom else { return String(localized: "Pick a time") }
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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

private enum OnboardingReason: CaseIterable, Hashable {
    case understandSelf
    case processEmotions
    case trackGoals
    case buildPractice

    var icon: String {
        switch self {
        case .understandSelf:  return "brain.head.profile"
        case .processEmotions: return "moon.stars"
        case .trackGoals:      return "target"
        case .buildPractice:   return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .understandSelf:  return .blue
        case .processEmotions: return MirrorTheme.violet
        case .trackGoals:      return .orange
        case .buildPractice:   return .green
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .understandSelf:  return "Understand myself better"
        case .processEmotions: return "Process stress and emotions"
        case .trackGoals:      return "Track goals and habits"
        case .buildPractice:   return "Build a reflection practice"
        }
    }
}

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Int = 0
    @State private var selectedReason: OnboardingReason? = nil
    @State private var nudgePreset: NudgePreset = .evening
    @State private var customNudgeTime: Date = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = 20
        c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var firstEntryText: String = ""
    @FocusState private var editorFocused: Bool

    // Derive suggested preset from selected reason
    private var suggestedPreset: NudgePreset {
        selectedReason == .trackGoals ? .morning : .evening
    }

    private var suggestionText: LocalizedStringKey {
        suggestedPreset == .morning
            ? "Suggested: **Morning** (\(suggestedPreset.timeLabel)) — great for intention-setting before the day starts."
            : "Suggested: **Evening** (\(suggestedPreset.timeLabel)) — best for capturing the full day before it fades."
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
                            : AnyShapeStyle(MirrorTheme.inkBorder))
                    .frame(width: i == step ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 20)

                // App icon
                Image("AppIconDisplay")
                    .resizable()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: MirrorTheme.primary.opacity(0.32), radius: 36, x: 0, y: 16)

                // Title — New York serif, tight tracking, strong weight
                Text("MirrorNotes")
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(MirrorTheme.textPrimary)
                    .tracking(-0.5)
                    .padding(.top, 32)

                // Tagline — same serif family, lighter, italic
                Text("Understand yourself\nthrough writing.")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.top, 10)

                // Divider — visual rhythm break
                Divider()
                    .overlay(MirrorTheme.inkBorder)
                    .padding(.top, 40)
                    .padding(.bottom, 36)
                    .padding(.horizontal, 4)

                // Feature list
                VStack(alignment: .leading, spacing: 22) {
                    welcomeFeatureItem(icon: "sparkles",   text: "Daily AI reflections from your writing", color: MirrorTheme.primary)
                    welcomeFeatureItem(icon: "cpu.fill",    text: "All AI runs on device — nothing leaves", color: .green)
                    welcomeFeatureItem(icon: "icloud.fill", text: "iCloud backup, private and encrypted",   color: .blue)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 36)
        }
    }

    private func welcomeFeatureItem(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(MirrorTheme.textPrimary)
            Spacer()
        }
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
                ForEach(OnboardingReason.allCases, id: \.self) { reason in
                    reasonButton(reason)
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
                    Text(suggestionText)
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
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

    private var writePrompt: LocalizedStringKey {
        switch selectedReason {
        case .understandSelf:
            return "What's something you've been trying to figure out about yourself lately?"
        case .processEmotions:
            return "What's weighing on you most right now? Even a few words helps."
        case .trackGoals:
            return "What are you working toward? Where are you at with it today?"
        case .buildPractice:
            return "What happened today that's worth remembering?"
        case nil:
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
                let wordCount = firstEntryText.split(separator: " ").count
                Text(wordCount == 1 ? "1 word" : "\(wordCount) words")
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

    private func reasonButton(_ reason: OnboardingReason) -> some View {
        let isSelected = selectedReason == reason
        let color = reason.color
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedReason = reason
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? color : MirrorTheme.inkRaised)
                        .frame(width: 44, height: 44)
                    Image(systemName: reason.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : color.opacity(0.7))
                }
                .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: 8, x: 0, y: 3)

                Text(reason.label)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? MirrorTheme.textPrimary : MirrorTheme.textSecondary)
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
                              : AnyShapeStyle(MirrorTheme.inkRaised))
                        .frame(width: 44, height: 44)
                    Image(systemName: preset.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : MirrorTheme.textSecondary)
                }
                .shadow(color: isSelected ? MirrorTheme.primary.opacity(0.3) : .clear, radius: 8, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(preset.displayName)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? MirrorTheme.textPrimary : MirrorTheme.textSecondary)
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
                        Text(preset == .morning
                             ? "Great for intention-setting before the day starts."
                             : "Best for capturing the full day before it fades.")
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

        try? modelContext.save()  // non-fatal: SwiftData will persist on next autosave cycle

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
