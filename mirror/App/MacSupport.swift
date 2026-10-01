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
            Divider()
            Button("Log Mood…") { MoodCheckInPresenter.shared.pending = true }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Find in Entries") {
                navigate("entries")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .mirrorMacFocusSearch, object: nil)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
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
