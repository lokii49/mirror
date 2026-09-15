import SwiftUI
import UserNotifications

private let appGroupID = "group.com.lokesh.mirror"

// Mirrors mirror/Widget/WidgetTheme.swift's frozen-dark-hex pattern — this extension is its own
// target with no access to that file (or to the app's adaptive MirrorTheme), so the handful of
// colors it needs are duplicated here rather than shared across targets.
private enum NudgeExtensionTheme {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static let inkRaised = hex(0x1C1830)
    static let inkMid = hex(0x110E1C)
    static let violet = hex(0x7C5CE4)
    static let violetLight = hex(0xA78BFA)
    static let ember = hex(0xF97B8B)
    static let sentinelBg = hex(0x0B0B0E)
}

// Mirrors MirrorTheme.moodColor(for:) (mirror/Core/Utilities/MirrorTheme.swift) — app-target only,
// same duplication reasoning as NudgeExtensionTheme above.
private func moodColor(for mood: String) -> Color {
    switch mood {
    case "Joyful":      return Color(red: 1.000, green: 0.835, blue: 0.310)
    case "Grateful":    return Color(red: 0.400, green: 0.733, blue: 0.416)
    case "Peaceful":    return Color(red: 0.506, green: 0.831, blue: 0.980)
    case "Content":     return Color(red: 0.302, green: 0.714, blue: 0.675)
    case "Energized":   return Color(red: 1.000, green: 0.596, blue: 0.000)
    case "Hopeful":     return Color(red: 0.584, green: 0.459, blue: 0.804)
    case "Anxious":     return Color(red: 1.000, green: 0.757, blue: 0.027)
    case "Overwhelmed": return Color(red: 0.937, green: 0.325, blue: 0.314)
    case "Frustrated":  return Color(red: 0.961, green: 0.486, blue: 0.000)
    case "Drained":     return Color(red: 0.620, green: 0.620, blue: 0.620)
    case "Sad":         return Color(red: 0.259, green: 0.647, blue: 0.961)
    case "Numb":        return Color(red: 0.812, green: 0.847, blue: 0.863)
    default:            return NudgeExtensionTheme.violet
    }
}

struct NudgeContentState {
    let isSentinel: Bool
    let bodyText: String
    let mood: String?

    init(content: UNNotificationContent) {
        let defaults = UserDefaults(suiteName: appGroupID)
        isSentinel = defaults?.string(forKey: "widget.displayMode") == "sentinel"
        // Today's mood is only meaningful alongside today's actual nudge — a stale mood from a
        // previous day would mismatch whatever body text this notification is currently showing.
        let moodDate = defaults?.string(forKey: "widget.nudge.date")
        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        let isToday = moodDate == dayFormatter.string(from: Date())
        mood = isToday ? defaults?.string(forKey: "widget.nudge.mood") : nil
        bodyText = content.body
    }
}

struct NudgeContentView: View {
    let state: NudgeContentState
    let onWriteNow: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            if !state.isSentinel { quoteMark }
            VStack(alignment: .leading, spacing: 12) {
                if let mood = state.mood {
                    HStack(spacing: 7) {
                        Circle().fill(moodColor(for: mood)).frame(width: 9, height: 9)
                        Text(state.isSentinel ? mood.uppercased() : mood)
                            .font(state.isSentinel
                                ? .system(size: 11, weight: .medium, design: .monospaced)
                                : .system(size: 12, weight: .regular, design: .serif).italic())
                            .foregroundStyle(state.isSentinel ? Color(white: 0.55) : Color(white: 0.80))
                    }
                }
                Text(state.bodyText)
                    .font(state.isSentinel
                        ? .system(size: 13, weight: .regular, design: .monospaced)
                        : .system(size: 15, weight: .regular, design: .serif).italic())
                    .foregroundStyle(state.isSentinel ? Color(white: 0.85) : Color(white: 0.95))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(action: onWriteNow) {
                        Text(state.isSentinel ? "Open log" : "Write now")
                            .font(state.isSentinel
                                ? .system(size: 12, weight: .medium, design: .monospaced)
                                : .system(size: 13, weight: .semibold))
                            .textCase(state.isSentinel ? .uppercase : nil)
                            .foregroundStyle(state.isSentinel ? NudgeExtensionTheme.ember : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(ctaBackground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var background: some View {
        Group {
            if state.isSentinel {
                NudgeExtensionTheme.sentinelBg
            } else {
                LinearGradient(
                    colors: [NudgeExtensionTheme.inkRaised, NudgeExtensionTheme.inkMid],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
    }

    private var quoteMark: some View {
        Text("\u{201C}")
            .font(.system(size: 72, weight: .black, design: .serif))
            .foregroundStyle(NudgeExtensionTheme.violetLight.opacity(0.13))
            .offset(x: 4, y: -14)
    }

    private var ctaBackground: some View {
        Group {
            if state.isSentinel {
                RoundedRectangle(cornerRadius: 5).strokeBorder(NudgeExtensionTheme.ember, lineWidth: 1)
            } else {
                Capsule().fill(NudgeExtensionTheme.violet)
            }
        }
    }
}
