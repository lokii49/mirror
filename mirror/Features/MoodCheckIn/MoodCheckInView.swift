import SwiftUI

/// Coordinates presentation of the standalone mood check-in sheet. The
/// notification delegate sets `pending` when the daily reminder is tapped;
/// `ContentView` observes it and presents `MoodCheckInView`. Kept as a
/// shared object (not a direct binding) because the trigger comes from
/// `UNUserNotificationCenterDelegate`, which has no view of its own.
@Observable
final class MoodCheckInPresenter {
    static let shared = MoodCheckInPresenter()
    private init() {}
    var pending = false
}

/// A dedicated one-tap mood log, fully independent of journal entries and of
/// the Write screen. Reached only from the daily reminder notification.
struct MoodCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode

    @State private var logged: String?

    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        VStack(spacing: 0) {
            if let logged {
                confirmation(mood: logged)
            } else {
                picker
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MirrorTheme.bgBase)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var picker: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(isSentinel ? "◆ MOOD CHECK-IN" : "How are you feeling right now?")
                    .font(isSentinel ? MirrorTheme.mono(15, weight: .bold) : .system(size: 21, weight: .bold, design: .rounded))
                    .kerning(isSentinel ? 0.4 : 0)
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("One tap. No writing.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(MirrorTheme.moodOptions, id: \.self) { mood in
                    Button {
                        MoodCheckInStore.add(mood: mood)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { logged = mood }
                    } label: {
                        Text(MirrorTheme.localizedMoodName(for: mood))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(MirrorTheme.moodColor(for: mood))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                MirrorTheme.moodColor(for: mood).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(MirrorTheme.moodColor(for: mood).opacity(0.35), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Button("Not now") { dismiss() }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    private func confirmation(mood: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Circle()
                .fill(MirrorTheme.moodColor(for: mood).opacity(0.18))
                .frame(width: 76, height: 76)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(MirrorTheme.moodColor(for: mood))
                }
            Text(isSentinel ? "LOGGED — \(MirrorTheme.localizedMoodName(for: mood).uppercased())" : "\(MirrorTheme.localizedMoodName(for: mood)), logged.")
                .font(isSentinel ? MirrorTheme.mono(14, weight: .bold) : .system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(MirrorTheme.textPrimary)
            Text("See you tomorrow.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 13)
                .background(
                    isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient),
                    in: Capsule()
                )
                .padding(.bottom, 24)
        }
        .task {
            // Auto-cancels when the view goes away — a manual "Done" tap won't
            // leave a stale dismiss() firing 1.6s later against another sheet.
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        }
    }
}
