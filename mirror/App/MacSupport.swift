#if os(macOS)
import SwiftUI
import SwiftData

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
    /// userInfo["id"]: an entry's UUID. Shows Entries with that entry selected.
    static let mirrorMacOpenEntry = Notification.Name("mirror.mac.openEntry")
    /// userInfo["text"]: starts a new entry with that text in it.
    static let mirrorMacNewEntrySeeded = Notification.Name("mirror.mac.newEntrySeeded")
    /// userInfo["data"]: image data pasted into the editor.
    static let mirrorMacPasteImage = Notification.Name("mirror.mac.pasteImage")
}

// MARK: - What the focused window offers the menu bar

/// Save for the window whose editor is showing.
struct MacEditorActions {
    var canSave: Bool
    var save: () -> Void
}

/// Pin for the window whose reader is showing an entry.
struct MacEntryActions {
    var isPinned: Bool
    var togglePin: () -> Void
}

private struct MacEditorActionsKey: FocusedValueKey { typealias Value = MacEditorActions }
private struct MacEntryActionsKey: FocusedValueKey { typealias Value = MacEntryActions }

extension FocusedValues {
    var macEditorActions: MacEditorActions? {
        get { self[MacEditorActionsKey.self] }
        set { self[MacEditorActionsKey.self] = newValue }
    }
    var macEntryActions: MacEntryActions? {
        get { self[MacEntryActionsKey.self] }
        set { self[MacEntryActionsKey.self] = newValue }
    }
}

private struct MacStandaloneWindowKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True in a window of its own (New Entry in New Window): no sidebar to hide, and the traffic
    /// lights sit at the left of the toolbar.
    var macStandaloneWindow: Bool {
        get { self[MacStandaloneWindowKey.self] }
        set { self[MacStandaloneWindowKey.self] = newValue }
    }
}

// MARK: - Menu bar (the board's File and Go menus)

struct MirrorMacCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.macEditorActions) private var editor
    @FocusedValue(\.macEntryActions) private var entry

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                NotificationCenter.default.post(name: .mirrorMacNewEntry, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("New Entry in New Window") { openWindow(id: "new-entry") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Save Entry") { editor?.save() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(editor?.canSave ?? false))
            Button(entry?.isPinned == true ? "Unpin Entry" : "Pin Entry") { entry?.togglePin() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(entry == nil)
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
            Divider()
            Button("Find in Entries") {
                navigate("entries")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .mirrorMacFocusSearch, object: nil)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Log Mood…") { MoodCheckInPresenter.shared.pending = true }
                .keyboardShortcut("m", modifiers: [.command, .option])
            // ⌘, belongs to the system Settings item in the app menu.
            SettingsLink { Text("Settings…") }
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

/// A fresh entry in a window of its own (File > New Entry in New Window).
struct MacNewEntryWindow: View {
    var body: some View {
        WriteView(autoFocus: true) {
            NSApp.keyWindow?.close()
        }
        .environment(\.appDisplayMode, .classic)
        .environment(\.macStandaloneWindow, true)
        .background(MacWindowConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 560, idealWidth: 760, maxWidth: .infinity, minHeight: 480, idealHeight: 800, maxHeight: .infinity)
    }
}

/// Calls `onGone` when the entry with this id no longer exists, so a reader or editor that still
/// holds it can be dismissed instead of showing, or saving to, a deleted record.
struct MacSelectionGuard: View {
    let onGone: () -> Void
    @Query private var matches: [Entry]

    init(entryID: UUID, onGone: @escaping () -> Void) {
        self.onGone = onGone
        _matches = Query(filter: #Predicate<Entry> { $0.id == entryID })
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: matches.isEmpty) { _, gone in
                if gone { onGone() }
            }
    }
}

/// An entry in its own window (the reader's "open in new window").
struct MacEntryWindow: View {
    @Query private var matches: [Entry]

    init(entryID: UUID?) {
        let id = entryID ?? UUID()
        _matches = Query(filter: #Predicate<Entry> { $0.id == id })
    }

    var body: some View {
        Group {
            if let entry = matches.first {
                NavigationStack { EntryDetailView(entry: entry) }
            } else {
                ContentUnavailableView("Entry not found", systemImage: "book.closed")
            }
        }
        .environment(\.appDisplayMode, .classic)
        .background(MacWindowConfigurator())
        .frame(minWidth: 560, minHeight: 480)
    }
}
#endif
