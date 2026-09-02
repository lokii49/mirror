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

/// A dedicated mood log, fully independent of journal entries and of the
/// Write screen. Reached only from the daily reminder notification. Pick a
/// mood (tap to select, tap again to deselect), then confirm with the button
/// — nothing is saved on the first tap, so an accidental wrong tap is
/// harmless.
struct MoodCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode

    @State private var selected: String?
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
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(isSentinel ? "◆ MOOD CHECK-IN" : "How are you feeling right now?")
                    .font(isSentinel ? MirrorTheme.mono(15, weight: .bold) : .system(size: 21, weight: .bold, design: .rounded))
                    .kerning(isSentinel ? 0.4 : 0)
                    .foregroundStyle(isSentinel ? MirrorTheme.ember : MirrorTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Pick one, then confirm below.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(MirrorTheme.moodOptions, id: \.self) { mood in
                        moodChip(mood)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }

            VStack(spacing: 10) {
                Button {
                    guard let selected else { return }
                    MoodCheckInStore.add(mood: selected)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { logged = selected }
                } label: {
                    Text(selected == nil
                         ? "Select a mood"
                         : "Log \(MirrorTheme.localizedMoodName(for: selected!))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selected == nil
                                ? AnyShapeStyle(Color.secondary.opacity(0.3))
                                : (isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selected == nil)
                .animation(.easeInOut(duration: 0.2), value: selected)

                Button("Not now") { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 24)
    }

    private func moodChip(_ mood: String) -> some View {
        let isSelected = selected == mood
        let color = MirrorTheme.moodColor(for: mood)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selected = isSelected ? nil : mood
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(MirrorTheme.localizedMoodName(for: mood))
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(color.opacity(isSelected ? 0.9 : 0.35), lineWidth: isSelected ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
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
            // Auto-cancels when the view goes away, so a manual "Done" tap
            // won't leave a stale dismiss() firing later against another sheet.
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        }
    }
}
