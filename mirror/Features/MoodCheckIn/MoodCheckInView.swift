import SwiftUI
import SwiftData
import WidgetKit

/// Coordinates presentation of the standalone mood check-in sheet. The
/// notification delegate sets `pending` when the daily reminder is tapped;
/// `ContentView` observes it and presents `MoodCheckInView`. Kept as a
/// shared object (not a direct binding) because the trigger comes from
/// `UNUserNotificationCenterDelegate`, which has no view of its own.
@Observable
final class MoodCheckInPresenter {
    static let shared = MoodCheckInPresenter()
    private init() {}

    /// Set by any entry point (reminder tap, foreground auto-prompt, the
    /// Insights "Log mood" button). `ContentView` presents when the screen is
    /// clear; if it can't, this stays set and presents on the next chance.
    var pending = false

    /// InsightView owns sheets ContentView can't see (`showPaywallAfterFirstNudge`
    /// especially — a once-per-user conversion moment). It reports them here so
    /// `pending` waits its turn instead of racing them into a dropped sheet.
    var blockedByOtherSheet = false
}

/// A dedicated mood log, fully independent of journal entries and of the
/// Write screen. Reached from the daily reminder notification, from the
/// auto-prompt when the app opens past the preferred check-in time with no
/// mood logged today, and from the "Log mood" button on Insights. Pick a
/// mood (tap to select, tap again to deselect), then confirm with the button
/// — nothing is saved on the first tap, so an accidental wrong tap is
/// harmless.
struct MoodCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selected: String?
    @State private var logged: String?
    /// The picker's own height: the sheet is exactly that tall (`.medium` left a band under
    /// "Not now"). iOS 26's floating sheet adds the bottom safe area to a `.height` detent,
    /// so that is taken back off there.
    @State private var pickerHeight: CGFloat = 480
    @State private var floatingBottomInset: CGFloat = 0

    private func log(_ mood: String) {
        modelContext.insert(MoodCheckIn(mood: mood))
        try? modelContext.save()
        // Rebuild the widget mood-map blob (entries + check-ins) and refresh so
        // the Mood Map widget reflects today's check-in right away.
        mirrorApp.updateWidgetHeatmaps(context: modelContext)
        WidgetCenter.shared.reloadAllTimelines()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.85)) { logged = mood }
    }

    private var isSentinel: Bool { displayMode == .sentinel }

    var body: some View {
        VStack(spacing: 0) {
            if let logged {
                confirmation(mood: logged)
            } else {
                // Scrolls only when the picker is taller than the sheet can be (large Dynamic Type).
                ScrollView { picker }
                    .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { inset in
            if #available(iOS 26, macOS 26, *) { floatingBottomInset = inset }
        }
        // inkRaised is the "elevated card / sheet" token — near-white in Classic
        // light so the pastel mood chips read against it, not the pale page bg.
        .background(MirrorTheme.inkRaised)
        .presentationDetents([.height(max(320, pickerHeight - floatingBottomInset))])
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

            moodGrid

            VStack(spacing: 10) {
                Button {
                    guard let selected else { return }
                    log(selected)
                } label: {
                    Text(selected == nil
                         ? "Select a mood"
                         : "Log \(MirrorTheme.localizedMoodName(for: selected!))")
                        .font(.system(size: 15, weight: .semibold))
                        // White on the 30%-grey disabled fill was unreadable in
                        // light mode — use a real muted style when nothing's picked.
                        .foregroundStyle(selected == nil ? AnyShapeStyle(MirrorTheme.textPrimary.opacity(0.5)) : AnyShapeStyle(Color.white))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selected == nil
                                ? AnyShapeStyle(MirrorTheme.inkBorder)
                                : (isSentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selected == nil)
                .animation(.easeInOut(duration: 0.2), value: selected)

                Button { dismiss() } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 20)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pickerHeight = ceil($0) }
    }

    private var moodGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 10)], spacing: 10) {
            ForEach(MirrorTheme.moodOptions, id: \.self) { mood in
                moodChip(mood)
            }
        }
        // Room for the chips' outlines: a scroll view clipped the top row's top edge.
        .padding(3)
    }

    private func moodChip(_ mood: String) -> some View {
        let isSelected = selected == mood
        let color = MirrorTheme.moodColor(for: mood)
        let onColor = MirrorTheme.moodOnColorText(for: mood)
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.8)) {
                selected = isSelected ? nil : mood
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            // Long names (Overwhelmed, Energiegeladen) drop the dot before they shrink: the
            // chip's tint already carries the mood's colour, and a shrunk label looks uneven
            // next to its neighbours.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    swatch(color: color, onColor: onColor, isSelected: isSelected)
                    moodLabel(mood, isSelected: isSelected, color: color, onColor: onColor)
                }
                moodLabel(mood, isSelected: isSelected, color: color, onColor: onColor)
                moodLabel(mood, isSelected: isSelected, color: color, onColor: onColor, shrinks: true)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.16)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(color.opacity(isSelected ? 0.9 : 0.6), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    // Colour swatch carries the mood identity; the label stays a high-contrast text colour so
    // pale moods (Numb, Joyful) are still readable on the near-white sheet.
    private func swatch(color: Color, onColor: Color, isSelected: Bool) -> some View {
        Circle()
            .fill(isSelected ? onColor : color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(MirrorTheme.textPrimary.opacity(isSelected ? 0 : 0.18), lineWidth: 0.5))
    }

    /// `shrinks`: the last resort, scaled down to fit; otherwise full size (so ViewThatFits can
    /// tell whether it fits).
    private func moodLabel(_ mood: String, isSelected: Bool, color: Color, onColor: Color, shrinks: Bool = false) -> some View {
        Text(MirrorTheme.localizedMoodName(for: mood))
            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(onColor) : (isSentinel ? AnyShapeStyle(color) : AnyShapeStyle(MirrorTheme.textPrimary)))
            .lineLimit(1)
            .minimumScaleFactor(shrinks ? 0.7 : 1)
            .fixedSize(horizontal: !shrinks, vertical: false)
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
            Text("Added to your mood timeline.")
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
