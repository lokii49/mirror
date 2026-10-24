import AppIntents
import SwiftUI
import WidgetKit

#if os(iOS)
// Controls for Control Center, the Lock Screen and the Action button (iOS 18+; UI pass
// 2026-10-24). Each one only opens the app on the matching screen through its mirror:// link, so
// nothing is stored here and both work on every tier.

@available(iOS 18.0, *)
struct MirrorNewEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lokesh.mirror.control.newEntry") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "mirror://write")!)) {
                Label("New Entry", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Entry")
        .description("Opens MirrorNotes ready to write.")
    }
}

@available(iOS 18.0, *)
struct MirrorLogMoodControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lokesh.mirror.control.logMood") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "mirror://mood-checkin")!)) {
                Label("Log Mood", systemImage: "face.smiling")
            }
        }
        .displayName("Log Mood")
        .description("Opens the mood check-in.")
    }
}
#endif
