import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Int = 0
    @State private var selectedReason: String? = nil
    @State private var selectedTime: String? = nil
    @State private var firstEntryText: String = ""
    @FocusState private var editorFocused: Bool

    private let reasons = [
        ("brain.head.profile", "Understand myself better"),
        ("moon.stars", "Process stress and emotions"),
        ("target",             "Track goals and habits"),
        ("sparkles",           "Build a reflection practice"),
    ]

    private let times = [
        ("sunrise",    "Morning",    "Before the day starts"),
        ("sun.max",    "Afternoon",  "Mid-day reset"),
        ("moon",       "Evening",    "After everything settles"),
        ("questionmark.circle", "Whenever",  "No set routine"),
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    MirrorTheme.primary.opacity(0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                progressIndicator
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                // Animated step content
                ZStack {
                    if step == 0 { welcomeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                    if step == 1 { reasonStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                    if step == 2 { timeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                    if step == 3 { writeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))) }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // CTA button
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
                    .fill(i <= step ? MirrorTheme.primary : Color.secondary.opacity(0.2))
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(MirrorTheme.accentGradient)
                        .frame(width: 72, height: 72)
                        .shadow(color: MirrorTheme.primary.opacity(0.35), radius: 20, x: 0, y: 8)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 8)

                Text("Welcome to Mirror")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("A private space to understand yourself through writing. No audience. No performance. Just you.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What brings you here?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Pick the one that resonates most.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(reasons, id: \.1) { icon, label in
                    reasonButton(icon: icon, label: label)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var timeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("When do you reflect?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Mirror will learn your rhythm.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(times, id: \.1) { icon, label, caption in
                    timeButton(icon: icon, label: label, caption: caption)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var writeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Write your first entry")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Anything on your mind — a sentence is enough.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(MirrorTheme.bgCard)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(editorFocused ? MirrorTheme.primary.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                    }

                if firstEntryText.isEmpty {
                    Text("What's on your mind right now?")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 16))
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                }

                TextEditor(text: $firstEntryText)
                    .focused($editorFocused)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .animation(.easeInOut(duration: 0.2), value: editorFocused)

            HStack {
                Spacer()
                Text("\(firstEntryText.split(separator: " ").count) words")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
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

    private func reasonButton(icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedReason = label
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedReason == label ? MirrorTheme.primary.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selectedReason == label ? MirrorTheme.primary : .secondary)
                }
                Text(label)
                    .font(.system(size: 16, weight: selectedReason == label ? .semibold : .regular))
                    .foregroundStyle(selectedReason == label ? .primary : .secondary)
                Spacer()
                if selectedReason == label {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MirrorTheme.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background(
                selectedReason == label ? MirrorTheme.primary.opacity(0.07) : MirrorTheme.bgCard,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selectedReason == label ? MirrorTheme.primary.opacity(0.3) : Color.primary.opacity(0.07),
                        lineWidth: selectedReason == label ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedReason)
    }

    private func timeButton(icon: String, label: String, caption: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTime = label
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selectedTime == label ? MirrorTheme.primary.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selectedTime == label ? MirrorTheme.primary : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16, weight: selectedTime == label ? .semibold : .regular))
                        .foregroundStyle(selectedTime == label ? .primary : .secondary)
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if selectedTime == label {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MirrorTheme.primary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background(
                selectedTime == label ? MirrorTheme.primary.opacity(0.07) : MirrorTheme.bgCard,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selectedTime == label ? MirrorTheme.primary.opacity(0.3) : Color.primary.opacity(0.07),
                        lineWidth: selectedTime == label ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedTime)
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
        case 2: return selectedTime != nil
        case 3: return true
        default: return false
        }
    }

    // MARK: - Logic

    private func advanceStep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if step < 3 {
            withAnimation {
                step += 1
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        // Save first entry if written
        let text = firstEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let entry = Entry(text: text, source: .typed)
            modelContext.insert(entry)
        }

        // Mark onboarding complete
        let profile: UserProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfile()
            modelContext.insert(profile)
        }
        profile.onboardingComplete = true

        try? modelContext.save()
    }
}
