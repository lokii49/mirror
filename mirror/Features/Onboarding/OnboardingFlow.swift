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

    var hint: LocalizedStringKey {
        switch self {
        case .understandSelf:  return "Notice patterns in how you think and feel."
        case .processEmotions: return "Write it out and get a little distance."
        case .trackGoals:      return "See how you're doing week by week."
        case .buildPractice:   return "A few quiet minutes a day."
        }
    }
}

struct OnboardingFlow: View {
    /// Called when the user taps Get started, and after the final step saves. ContentView keeps the
    /// flow up in between, even if an already-onboarded profile syncs in from iCloud.
    var onBegin: () -> Void = {}
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var selectedDisplayMode: DisplayMode = .classic
    @State private var welcomeAppeared = false
    @State private var askingNotificationPermission = false
    /// The reminder step wrote `moodCheckInEnabled = false` for what looked like a new user.
    @State private var defaultedMoodCheckInOff = false
    @State private var writeBreathe = false
    @Namespace private var reasonAccentNS
    @Namespace private var presetAccentNS
    @Namespace private var modeAccentNS

    // Derive suggested preset from selected reason
    private var suggestedPreset: NudgePreset {
        selectedReason == .trackGoals ? .morning : .evening
    }

    var body: some View {
        ZStack {
            MirrorTheme.bgBase
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
                    if step == 4 { modeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ctaButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        #if os(macOS)
        // Shown in a Mac sheet, which has no size of its own: without one the steps collapse.
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 760, minHeight: 640, idealHeight: 720, maxHeight: 860)
        #endif
        #if DEBUG && os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .mirrorMacDebugOnboardingStep)) { note in
            if let value = note.userInfo?["step"] as? Int { step = value }
        }
        #endif
        .onAppear { preselectSyncedDisplayMode() }
        .onChange(of: profiles.count) { preselectSyncedDisplayMode() }
    }

    /// A profile synced from the user's other device keeps its theme (owner, 2026-10-17): the mode
    /// step shows it selected, and `completeOnboarding` never writes over it.
    private func preselectSyncedDisplayMode() {
        guard let synced = UserProfile.canonical(in: profiles) else { return }
        selectedDisplayMode = synced.displayMode
    }

    // MARK: - Progress

    /// The signature motif — the connected-dot mark from the app icon,
    /// reused as the progress thread here and as the selection mark on
    /// every choice row below. One shape, three jobs, so it reads as
    /// deliberate rather than decorative.
    private var threadDoneColor: Color {
        isSentinelPreview ? MirrorTheme.ember.opacity(0.5) : MirrorTheme.violet
    }

    private var threadActiveColor: Color {
        isSentinelPreview ? MirrorTheme.ember : MirrorTheme.violetLight
    }

    @ViewBuilder
    private func threadNode(_ i: Int) -> some View {
        let size: CGFloat = i == step ? 8 : 6
        let fill: Color = i < step ? threadDoneColor : (i == step ? threadActiveColor : .clear)
        Circle()
            .fill(fill)
            .overlay {
                if i > step {
                    Circle().stroke(MirrorTheme.inkBorder, lineWidth: 1.5)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: i == step ? threadActiveColor.opacity(0.35) : .clear, radius: 5)
    }

    // Shared selection-bar renderer for the three choice-row groups below.
    // Matches EntryRow's leading mood-bar (EntryListView.swift): a small
    // radius sized to the bar's own width, inset from the card's top/bottom
    // so it reads as a floating accent rather than colliding with the
    // card's much larger 16pt corner curve. The old topLeading/bottomLeading
    // radius of 16 on a 3pt-wide bar way overshot the shape's own width,
    // so the corner arcs ate almost the whole bar — it looked like a short
    // stub with gaps top and bottom instead of a clean line.
    // Under Reduce Motion, the sliding matchedGeometryEffect is dropped
    // entirely (not just re-eased) so the bar only cross-fades in place.
    @ViewBuilder
    private func accentBar(color: Color, id: String, in ns: Namespace.ID) -> some View {
        let bar = RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 4)
            .padding(.vertical, 12)

        if reduceMotion {
            bar
        } else {
            bar.matchedGeometryEffect(id: id, in: ns)
        }
    }

    private func threadSegment(_ i: Int) -> some View {
        let fill: Color = i < step ? threadDoneColor.opacity(0.55) : MirrorTheme.inkBorder
        return Rectangle()
            .fill(fill)
            .frame(width: 22, height: 1)
    }

    /// Mac has only the default theme for now, so its flow ends before the "Choose your view" step.
    private var lastStep: Int {
        #if os(macOS)
        return 3
        #else
        return 4
        #endif
    }

    private var progressIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0...lastStep, id: \.self) { i in
                threadNode(i)
                if i < lastStep {
                    threadSegment(i)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
        .animation(.easeInOut(duration: 0.2), value: selectedDisplayMode)
    }

    // MARK: - Steps

    // Was a plain ScrollView — inside a ScrollView, Spacer(minLength:) collapses
    // to its minLength instead of expanding (the scroll axis proposes unbounded
    // height), so short content pinned to the top and left a dead gap above the
    // CTA instead of centering. Pinning the inner VStack's minHeight to the
    // container's actual height gives Spacer real room to expand — content
    // centers when it's shorter than the screen, and still scrolls normally
    // at larger Dynamic Type sizes where it's taller.
    private var welcomeStep: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Fixed, not flexible: only the bottom Spacer absorbs leftover space.
                    Spacer().frame(height: 8)

                    HStack(spacing: 12) {
                        Image("AppIconDisplay")
                            .resizable()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .shadow(color: MirrorTheme.primary.opacity(0.28), radius: 14, x: 0, y: 6)
                        Text("MirrorNotes")
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .foregroundStyle(MirrorTheme.textPrimary)
                            .tracking(-0.4)
                    }
                    .welcomeReveal(welcomeAppeared, delay: 0)

                    Text("Understand yourself\nthrough writing.")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(MirrorTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 14)
                        .welcomeReveal(welcomeAppeared, delay: 0.12)

                    WelcomeReflectionDemo(reduceMotion: reduceMotion)
                        .padding(.top, 30)
                        .welcomeReveal(welcomeAppeared, delay: 0.25)

                    VStack(alignment: .leading, spacing: 10) {
                        welcomeFeatureItem(icon: "lock.shield.fill", text: "AI runs on your device", color: .green)
                        welcomeFeatureItem(icon: "icloud.fill", text: "iCloud backup, private and encrypted", color: .blue)
                    }
                    .padding(.top, 26)
                    .welcomeReveal(welcomeAppeared, delay: 0.4)

                    Spacer(minLength: 16)
                }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            welcomeAppeared = true
        }
    }

    private func welcomeFeatureItem(icon: String, text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MirrorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Every question step opens the same way: the welcome screen's serif voice for the question,
    /// a plain line under it.
    private func stepHeader(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .tracking(-0.3)
                .foregroundStyle(MirrorTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(MirrorTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var reasonStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader("What brings you here?", "Pick the one that resonates most.")

                VStack(spacing: 10) {
                    ForEach(OnboardingReason.allCases, id: \.self) { reason in
                        reasonButton(reason)
                    }
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
    }

    private var timeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader("When should MirrorNotes nudge you?", "One gentle reminder a day to reflect.")

                notificationPreview

                VStack(spacing: 10) {
                    ForEach(NudgePreset.allCases, id: \.self) { preset in
                        nudgePresetButton(preset)
                    }
                }

                if nudgePreset == .custom {
                    DatePicker("", selection: $customNudgeTime, displayedComponents: .hourAndMinute)
                        .platformWheelDatePicker()
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

    private var nudgeTimeLabel: String {
        nudgePreset == .custom
            ? customNudgeTime.formatted(date: .omitted, time: .shortened)
            : nudgePreset.timeLabel
    }

    /// The reminder as it will arrive: the real title and the real body of the daily writing nudge
    /// (MirrorNotifications), at the time picked below. Permission is asked later, not here.
    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("AppIconDisplay")
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "MirrorNotes")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MirrorTheme.textPrimary)
                    Spacer()
                    Text(nudgeTimeLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                        .contentTransition(.numericText())
                }
                Text("What's on your mind? Take a moment to write.")
                    .font(.system(size: 14))
                    .foregroundStyle(MirrorTheme.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.2), value: nudgeTimeLabel)
        .accessibilityElement(children: .combine)
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
            stepHeader("Write your first entry", "A sentence is enough. MirrorNotes learns from everything you write.")

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MirrorTheme.inkMid)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                editorFocused
                                    ? AnyShapeStyle(MirrorTheme.violet.opacity(0.45))
                                    : (firstEntryText.isEmpty
                                       ? AnyShapeStyle(MirrorTheme.violet.opacity(writeBreathe ? 0.28 : 0.12))
                                       : AnyShapeStyle(MirrorTheme.inkBorder)),
                                lineWidth: editorFocused ? 1.5 : 1
                            )
                    }
                    .shadow(
                        color: editorFocused
                            ? MirrorTheme.violet.opacity(0.15)
                            : (firstEntryText.isEmpty ? MirrorTheme.violet.opacity(writeBreathe ? 0.14 : 0.04) : .clear),
                        radius: editorFocused ? 16 : (writeBreathe ? 22 : 10), x: 0, y: 4
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
            .frame(minHeight: 200, maxHeight: 320)
            .animation(.easeInOut(duration: 0.2), value: editorFocused)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    writeBreathe = true
                }
            }

            HStack {
                if firstEntryText.isEmpty {
                    Text("Even one line teaches MirrorNotes something.")
                        .font(.system(size: 12.5, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(MirrorTheme.textTertiary)
                }
                Spacer()
                let wordCount = segmentedWordCount(firstEntryText)
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

    private var modeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader("Choose your view", "Same journal, same on-device AI. Switch anytime in Settings.")

                VStack(spacing: 12) {
                    modeCard(
                        mode: .classic,
                        title: "Classic",
                        subtitle: "Calm, card-based, quiet.",
                        accent: MirrorTheme.violet
                    )
                    modeCard(
                        mode: .sentinel,
                        title: "Sentinel",
                        subtitle: "HUD, mono readouts, rank + streaks.",
                        accent: MirrorTheme.ember
                    )
                }

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 24)
        }
    }

    private func modeCard(mode: DisplayMode, title: LocalizedStringKey, subtitle: LocalizedStringKey, accent: Color) -> some View {
        let isSelected = selectedDisplayMode == mode
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75)) {
                selectedDisplayMode = mode
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MirrorTheme.textPrimary)
                    Spacer()
                    Circle()
                        .fill(isSelected ? accent : .clear)
                        .overlay {
                            if !isSelected {
                                Circle().stroke(MirrorTheme.inkBorder, lineWidth: 1.5)
                            }
                        }
                        .frame(width: 7, height: 7)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MirrorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                modePreview(mode: mode, accent: accent)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isSelected ? accent.opacity(0.08) : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.4) : MirrorTheme.inkBorder, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    accentBar(color: accent, id: "modeAccent", in: modeAccentNS)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: selectedDisplayMode)
    }

    /// The signature moment: a miniature render of each mode's real chrome —
    /// not an adjective describing it — so tapping between cards shows the
    /// whole app's skin swap rather than asking the user to imagine it.
    @ViewBuilder
    private func modePreview(mode: DisplayMode, accent: Color) -> some View {
        let isSelected = selectedDisplayMode == mode
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MirrorTheme.inkBase)

            if mode == .sentinel {
                SentinelGridBackground(lineColor: accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 90, height: 90)
                    .blur(radius: 30)
                    .offset(x: 20, y: -30)
            }

            VStack(spacing: 10) {
                // Sample chip — mirrors WriteView's real mood/signal control per mode.
                Group {
                    if mode == .sentinel {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform")
                                .font(.system(size: 9, weight: .semibold))
                            Text("SIGNAL")
                                .font(MirrorTheme.mono(9.5, weight: .semibold))
                                .kerning(0.3)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(accent.opacity(0.35), lineWidth: 1))
                    } else {
                        HStack(spacing: 5) {
                            Circle().fill(accent).frame(width: 6, height: 6)
                            Text("Grateful")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.12), in: Capsule())
                    }
                }

                // Sample glyph — the two type voices, shown rather than named.
                Text("Aa")
                    .font(mode == .sentinel
                          ? MirrorTheme.mono(26, weight: .bold)
                          : .system(size: 26, weight: .regular, design: .serif).italic())
                    .foregroundStyle(MirrorTheme.textPrimary.opacity(0.85))

                // Sample journal line — ties the type swatch back to what it's for.
                Text(mode == .sentinel ? "LOG_042 // ENTRY RECORDED" : "Today felt lighter.")
                    .font(mode == .sentinel
                          ? MirrorTheme.mono(9, weight: .medium)
                          : .system(size: 12, weight: .regular, design: .serif).italic())
                    .kerning(mode == .sentinel ? 0.3 : 0)
                    .foregroundStyle(MirrorTheme.textTertiary)
            }

            if mode == .sentinel {
                ViewfinderCorners(inset: 6, length: 10, color: accent.opacity(isSelected ? 0.7 : 0.35))
                    .padding(8)
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
        }
    }

    // MARK: - Choice Buttons

    private func reasonButton(_ reason: OnboardingReason) -> some View {
        let isSelected = selectedReason == reason
        let color = reason.color
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75)) {
                selectedReason = reason
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: reason.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(isSelected ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(reason.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MirrorTheme.textPrimary)
                    Text(reason.hint)
                        .font(.system(size: 13))
                        .foregroundStyle(MirrorTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)

                Circle()
                    .fill(isSelected ? color : .clear)
                    .overlay {
                        if !isSelected {
                            Circle().stroke(MirrorTheme.inkBorder, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 7, height: 7)
                    .transition(.scale.combined(with: .opacity))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? color.opacity(0.08) : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.35) : MirrorTheme.inkBorder, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    accentBar(color: color, id: "reasonAccent", in: reasonAccentNS)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: selectedReason)
    }

    @ViewBuilder
    private func nudgePresetButton(_ preset: NudgePreset) -> some View {
        let isSelected = nudgePreset == preset
        let isRecommended = preset == suggestedPreset

        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75)) {
                nudgePreset = preset
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preset.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? MirrorTheme.violet : MirrorTheme.textSecondary)
                    .frame(width: 16)

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
                            .foregroundStyle(isSelected ? AnyShapeStyle(MirrorTheme.primary.opacity(0.8)) : AnyShapeStyle(MirrorTheme.textSecondary))
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

                Circle()
                    .fill(isSelected ? MirrorTheme.violet : .clear)
                    .overlay {
                        if !isSelected {
                            Circle().stroke(MirrorTheme.inkBorder, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 7, height: 7)
                    .transition(.scale.combined(with: .opacity))
            }
            .padding(16)
            .background(isSelected ? MirrorTheme.violet.opacity(0.08) : MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? MirrorTheme.violet.opacity(0.35) : MirrorTheme.inkBorder, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    accentBar(color: MirrorTheme.violet, id: "presetAccent", in: presetAccentNS)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.75), value: nudgePreset)
    }

    // MARK: - CTA

    // Steps 0-3 render before any mode choice exists (no back-nav, and
    // UserProfile.displayMode defaults to .classic until completeOnboarding
    // writes it) so they cannot preview Sentinel. Step 4's own CTA previews
    // whichever card the user has tapped, since selectedDisplayMode is live.
    private var isSentinelPreview: Bool { step == 4 && selectedDisplayMode == .sentinel }

    private var ctaButton: some View {
        Button {
            advanceStep()
        } label: {
            HStack {
                Spacer()
                Group {
                    if isSentinelPreview {
                        Text(step == 4 ? "INITIATE" : "CONTINUE")
                            .font(MirrorTheme.mono(15, weight: .bold))
                    } else {
                        Text(ctaTitle)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 54)
            .background(
                ctaEnabled
                    ? (isSentinelPreview ? AnyShapeStyle(LinearGradient(colors: [MirrorTheme.ember, .orange], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(MirrorTheme.accentGradient))
                    : AnyShapeStyle(Color.secondary.opacity(0.3)),
                in: isSentinelPreview ? AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) : AnyShape(Capsule())
            )
        }
        .buttonStyle(.plain)
        .disabled(!ctaEnabled || askingNotificationPermission)
        .shadow(color: ctaEnabled && isSentinelPreview ? MirrorTheme.ember.opacity(0.28) : .clear, radius: 16, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.2), value: ctaEnabled)
        .animation(.easeInOut(duration: 0.2), value: selectedDisplayMode)
    }

    private var ctaTitle: LocalizedStringKey {
        if step == lastStep { return "Start journaling" }
        if step == 0 { return "Get started" }
        if step == 3 && firstEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Skip for now" }
        return "Continue"
    }

    private var ctaEnabled: Bool {
        switch step {
        case 0: return true
        case 1: return selectedReason != nil
        case 2: return true
        case 3: return true
        case 4: return true
        default: return false
        }
    }

    // MARK: - Logic

    private func advanceStep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if step == 0 { onBegin() }
        if step == 1 {
            // Pre-select suggested preset based on reason
            nudgePreset = suggestedPreset
        }
        if step == 2 {
            // Ask right after the time is picked, so the reminder starts tonight: waiting for the
            // first reflection (day 4-7) left the habit-forming first days with no reminder at all,
            // while this screen shows one. The step advances once the system prompt is answered.
            askingNotificationPermission = true
            Task { @MainActor in
                await enableDailyReminder()
                askingNotificationPermission = false
                withAnimation { step += 1 }
            }
            return
        }
        if step < lastStep {
            withAnimation {
                step += 1
            }
        } else {
            completeOnboarding()
        }
    }

    private var chosenNudgeTime: (hour: Int, minute: Int) {
        if nudgePreset == .custom {
            let c = Calendar.current.dateComponents([.hour, .minute], from: customNudgeTime)
            return (c.hour ?? 20, c.minute ?? 0)
        }
        return (nudgePreset.hour, 0)
    }

    private func saveNudgeTime() {
        let time = chosenNudgeTime
        UserDefaults.standard.set(time.hour, forKey: "nudgeHour")
        UserDefaults.standard.set(time.minute, forKey: "nudgeMinute")
    }

    /// Saves the picked time, asks for notification permission (only if never asked), and schedules
    /// the daily writing reminder with its generic body. A "no" just moves on; Settings can turn
    /// reminders on later.
    private func enableDailyReminder() async {
        saveNudgeTime()
        // New users start with the mood check-in reminder off (owner, 2026-10-16): with permission
        // now asked here, its default-on 9:00 notification would otherwise start on day one next
        // to the writing reminder. Written before the prompt, because answering it makes the app
        // active and mirrorApp's reArmUserReminders schedules the check-in right then. Only when
        // unset, so anyone who chose a value keeps it. Settings can turn it on. Not for someone
        // already using MirrorNotes on another device (a synced profile or entries are here): on a
        // reinstall or new device they keep the default-on reminder they had.
        if UserDefaults.standard.object(forKey: "moodCheckInEnabled") == nil, !isReturningUser {
            UserDefaults.standard.set(false, forKey: "moodCheckInEnabled")
            defaultedMoodCheckInOff = true
        }
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let time = chosenNudgeTime
        // Returns without scheduling unless authorized.
        await NotificationService.rescheduleContextualNudge(
            hasWrittenToday: false, insightReady: false, hour: time.hour, minute: time.minute
        )
    }

    /// Someone who already uses MirrorNotes on another device: their onboarded profile or their
    /// entries have synced in.
    private var isReturningUser: Bool {
        profiles.contains { $0.onboardingComplete }
            || ((try? modelContext.fetchCount(FetchDescriptor<Entry>())) ?? 0) > 0
    }

    private func completeOnboarding() {
        saveNudgeTime()

        // Read before the first entry below is inserted, which would count as "entries synced in".
        let returning = isReturningUser
        // The reminder step turned the check-in off for a new user, but their synced profile or
        // entries arrived since: give the reinstall/new-device default back.
        if returning && defaultedMoodCheckInOff {
            UserDefaults.standard.removeObject(forKey: "moodCheckInEnabled")
        }

        let text = firstEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let entry = Entry(text: text, source: .typed)
            modelContext.insert(entry)
        }

        // A profile synced from another device keeps its theme there and here (owner, 2026-10-17):
        // the mode is written only on a profile created now.
        var createdProfile: UserProfile?
        if let existing = UserProfile.canonical(in: profiles) {
            existing.onboardingComplete = true
        } else {
            let profile = UserProfile()
            profile.onboardingComplete = true
            profile.displayMode = selectedDisplayMode
            modelContext.insert(profile)
            createdProfile = profile
        }

        try? modelContext.save()  // non-fatal: SwiftData will persist on next autosave cycle
        if let createdProfile { UserProfile.recordCreatedByOnboarding(createdProfile) }
        UserProfile.mergeDuplicates(in: modelContext)

        // Prevent What's New sheet from firing for new installs — they have no "old version" to upgrade from
        FeatureCardService.shared.markWhatsNewSeen()
        onFinish()

        // Notification permission was asked on the reminder step (enableDailyReminder), right
        // after the time was picked (owner, 2026-10-16). mirrorApp's
        // requestNotificationPermissionIfNeeded() still asks anyone who onboarded before that.
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

private extension View {
    /// The welcome step's staggered fade-up.
    func welcomeReveal(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .animation(.easeOut(duration: 0.5).delay(delay), value: shown)
    }
}

/// The welcome screen's demo: a short entry types itself, then the reflection the app would write
/// for it appears, quoting the entry's own sentence. The reflection uses the same fixed lines as a
/// real one (English `groundedNudgeMoodLines`, other languages `groundedLocales`) for a good-mood
/// entry, which gets no tip, so the screen never shows something the app can't produce. The entry
/// text is synthetic sample text, never anyone's journal.
private struct WelcomeReflectionDemo: View {
    let reduceMotion: Bool
    @State private var typed = 0
    @State private var showsReflection = false

    private let opening = String(localized: "Walked home the long way tonight.")
    private let quote = String(localized: "I finally finished the chapter I'd been putting off.")

    /// The UI language's code as `groundedLocales` keys it ("pt-BR" → "pt", "zh-Hans" → "zh").
    private static var languageCode: String {
        let id = Bundle.main.preferredLocalizations.first ?? "en"
        return String(id.prefix { $0 != "-" && $0 != "_" })
    }

    private var entry: String {
        ["ja", "zh"].contains(Self.languageCode) ? opening + quote : opening + " " + quote
    }

    private var reflectionParts: (lead: String, tail: String) {
        if let loc = InsightService.groundedLocales[Self.languageCode] {
            return (loc.youWrote + loc.open, loc.close + loc.joiner + (loc.feel[.good]?.first ?? ""))
        }
        return (InsightService.groundedNudgePrefix, "\" " + (InsightService.groundedNudgeMoodLines[.good] ?? ""))
    }

    var body: some View {
        VStack(spacing: 0) {
            entryCard
            thread
            reflectionCard
            Text("After a few entries, MirrorNotes reflects your own words back to you.")
                .font(.system(size: 13))
                .foregroundStyle(MirrorTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .opacity(showsReflection ? 1 : 0)
        }
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry + "\n" + reflectionParts.lead + quote + reflectionParts.tail)
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            ZStack(alignment: .topLeading) {
                // The full text, hidden, holds the card's final height so nothing shifts while typing.
                Text(entry).hidden()
                Text(typedEntry)
            }
            .font(.system(size: 17, design: .serif))
            .lineSpacing(4)
            .foregroundStyle(MirrorTheme.textPrimary)
            // Grow to every line; inside a ScrollView the Mac otherwise truncates to one.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MirrorTheme.inkBorder, lineWidth: 1)
        }
    }

    private var typedEntry: AttributedString {
        var text = AttributedString(String(entry.prefix(typed)))
        if showsReflection, let range = text.range(of: quote) {
            text[range].backgroundColor = MirrorTheme.violet.opacity(0.18)
        }
        if typed < entry.count {
            var caret = AttributedString("|")
            caret.foregroundColor = MirrorTheme.violetLight
            text += caret
        }
        return text
    }

    /// The app icon's connected-dot mark, linking the quoted sentence to the reflection.
    private var thread: some View {
        VStack(spacing: 0) {
            Circle().fill(MirrorTheme.violetLight).frame(width: 6, height: 6)
            Rectangle().fill(MirrorTheme.violetLight.opacity(0.5)).frame(width: 1.5, height: 16)
            Circle().fill(MirrorTheme.violetLight).frame(width: 6, height: 6)
        }
        .padding(.vertical, 4)
        .opacity(showsReflection ? 1 : 0)
    }

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Daily Reflection", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MirrorTheme.violetLight)
            Text(reflectionText)
                .font(.system(size: 15))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MirrorTheme.violetDim.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(showsReflection ? 1 : 0)
        .offset(y: showsReflection || reduceMotion ? 0 : 10)
    }

    private var reflectionText: AttributedString {
        let parts = reflectionParts
        var lead = AttributedString(parts.lead)
        lead.foregroundColor = MirrorTheme.textSecondary
        var quoted = AttributedString(quote)
        quoted.foregroundColor = MirrorTheme.textPrimary
        quoted.font = .system(size: 15, weight: .semibold)
        var tail = AttributedString(parts.tail)
        tail.foregroundColor = MirrorTheme.textSecondary
        return lead + quoted + tail
    }

    private func play() async {
        guard !reduceMotion else {
            typed = entry.count
            showsReflection = true
            return
        }
        guard (try? await Task.sleep(for: .seconds(0.9))) != nil else { return }
        for count in 1...entry.count {
            typed = count
            guard (try? await Task.sleep(for: .milliseconds(26))) != nil else { return }
        }
        guard (try? await Task.sleep(for: .seconds(0.45))) != nil else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showsReflection = true }
    }
}

// MARK: - One profile per iCloud account

/// Onboarding on a new device can finish before CloudKit has imported the user's existing profile,
/// leaving two synced `UserProfile` rows; an unsorted `profiles.first` then flips between them (and
/// with it the theme). `canonical(in:)` picks the same row every time; `mergeDuplicates(in:)`
/// cleans up where that is safe on every device at once.
///
/// UserProfile has no creation date or synced ID (adding one is a CloudKit schema change), and
/// `persistentModelID` is different on each device. So a row is deleted only when content alone
/// picks the keeper (onboarded, badges, streak, last written: values a merge only grows), which
/// every device works out the same way. Rows whose content ties are never deleted: two devices
/// could each delete a different one and lose both. Instead the device whose onboarding created one
/// of them in the last few days gives its row the other's theme, so the synced theme wins (owner,
/// 2026-10-17) and both rows read the same.
extension UserProfile {
    private static let onboardingCreatedKey = "onboardingCreatedProfile"
    private static let onboardingCreatedWindow: TimeInterval = 3 * 24 * 60 * 60

    private var contentRank: (Int, Int, Int, Date) {
        (onboardingComplete ? 1 : 0, badges.count, streakCount, lastWritten ?? .distantPast)
    }

    /// The profile the app reads (theme, onboarding state) when more than one has synced in.
    static func canonical(in profiles: [UserProfile]) -> UserProfile? {
        guard profiles.count > 1 else { return profiles.first }
        let createdHere = recentlyCreatedHereID()
        return profiles.min { a, b in
            if a.contentRank != b.contentRank { return a.contentRank > b.contentRank }
            // A tie: the profile that synced in comes before the one this device just created.
            let aHere = a.persistentModelID == createdHere
            let bHere = b.persistentModelID == createdHere
            if aHere != bHere { return bHere }
            return a.persistentModelID < b.persistentModelID
        }
    }

    /// Onboarding created this profile because none had synced in yet.
    static func recordCreatedByOnboarding(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile.persistentModelID) else { return }
        UserDefaults.standard.set(["id": data, "at": Date()], forKey: onboardingCreatedKey)
    }

    private static func recentlyCreatedHereID() -> PersistentIdentifier? {
        guard let record = UserDefaults.standard.dictionary(forKey: onboardingCreatedKey),
              let at = record["at"] as? Date, Date().timeIntervalSince(at) < onboardingCreatedWindow,
              let data = record["id"] as? Data
        else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }

    /// Run when profiles change or the app becomes active. Deletes nothing but redundant profile rows.
    static func mergeDuplicates(in context: ModelContext) {
        guard let profiles = try? context.fetch(FetchDescriptor<UserProfile>()), profiles.count > 1,
              let keeper = canonical(in: profiles) else { return }
        let others = profiles.filter { $0 !== keeper }

        if others.allSatisfy({ $0.contentRank < keeper.contentRank }) {
            for other in others {
                keeper.badges += other.badges.filter { !keeper.badges.contains($0) }
                keeper.streakCount = max(keeper.streakCount, other.streakCount)
                if let written = other.lastWritten, written > keeper.lastWritten ?? .distantPast {
                    keeper.lastWritten = written
                }
                context.delete(other)
            }
            try? context.save()
            return
        }

        guard let createdHere = recentlyCreatedHereID(), keeper.persistentModelID != createdHere,
              let mine = others.first(where: { $0.persistentModelID == createdHere }),
              mine.contentRank == keeper.contentRank
        else { return }
        if mine.displayMode != keeper.displayMode {
            mine.displayMode = keeper.displayMode
            try? context.save()
        }
        UserDefaults.standard.removeObject(forKey: onboardingCreatedKey)
    }
}
