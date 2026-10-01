#if os(macOS)
import SwiftUI

// macOS-only app plumbing: menu commands, the Settings window, and the notifications that let
// the menu bar drive navigation inside ContentView (the commands live at App scope, the
// selection state lives in ContentView).

extension Notification.Name {
    /// userInfo["destination"]: a `MacDestination` raw value ("write", "entries", "today", "digest",
    /// "report", "mood", "ask", "brain").
    static let mirrorMacNavigate = Notification.Name("mirror.mac.navigate")
    /// Start a fresh entry (Write destination, new editor).
    static let mirrorMacNewEntry = Notification.Name("mirror.mac.newEntry")
    static let mirrorMacToggleSidebar = Notification.Name("mirror.mac.toggleSidebar")
}

struct MirrorMacCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                NotificationCenter.default.post(name: .mirrorMacNewEntry, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button("Hide Sidebar") {
                NotificationCenter.default.post(name: .mirrorMacToggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
        CommandMenu("Go") {
            Button("Write") { navigate("write") }
                .keyboardShortcut("1", modifiers: .command)
            Button("Entries") { navigate("entries") }
                .keyboardShortcut("2", modifiers: .command)
            Button("Insights") { navigate("today") }
                .keyboardShortcut("3", modifiers: .command)
        }
    }

    private func navigate(_ destination: String) {
        NotificationCenter.default.post(
            name: .mirrorMacNavigate,
            object: nil,
            userInfo: ["destination": destination]
        )
    }
}

/// Content of the standard Settings window (Cmd-,). Reuses the shared SettingsView; the
/// tabbed Mac layout from the design comes in the polish milestone.
struct MacSettingsRoot: View {
    var body: some View {
        NavigationStack {
            SettingsView()
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 560)
        .environment(\.appDisplayMode, .classic)
    }
}
#endif
