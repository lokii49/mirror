#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

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
    /// Edit the entry the reader is showing (Return in the Entries list, Edit in the menu).
    static let mirrorMacEditEntry = Notification.Name("mirror.mac.editEntry")
    /// userInfo["data"]: image data pasted into the editor.
    static let mirrorMacPasteImage = Notification.Name("mirror.mac.pasteImage")
}

// MARK: - What the focused window offers the menu bar

/// Save for the window whose editor is showing.
struct MacEditorActions {
    var canSave: Bool
    var save: () -> Void
    /// Formatting from the Format menu, applied through the same path as the toolbar.
    var apply: (NoteTextCommand) -> Void
    /// What the caret or selection currently has, for the menu's checkmarks.
    var inline: InlineStyleSet
    var paragraph: NoteParagraphTextStyle
}

/// Pin for the window whose reader is showing an entry.
struct MacEntryActions {
    var isPinned: Bool
    var togglePin: () -> Void
    var share: () -> Void
    var exportPDF: () -> Void
    var delete: () -> Void
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
        let _ = MacMainWindow.openWindow = openWindow
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                unlocked { NotificationCenter.default.post(name: .mirrorMacNewEntry, object: nil) }
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("New Entry in New Window") { unlocked { openWindow(id: "new-entry") } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Save Entry") { unlocked { editor?.save() } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(editor?.canSave ?? false))
            Button(entry?.isPinned == true ? "Unpin Entry" : "Pin Entry") { unlocked { entry?.togglePin() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(entry == nil)
            Button("Share Entry…") { unlocked { entry?.share() } }
                .disabled(entry == nil)
            Button("Export as PDF…") { unlocked { entry?.exportPDF() } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(entry == nil)
            Button("Delete Entry…") { unlocked { entry?.delete() } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(entry == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Hide Sidebar") {
                unlocked { NotificationCenter.default.post(name: .mirrorMacToggleSidebar, object: nil) }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
        CommandMenu("Format") {
            paragraphItem("Title", .title, key: "t")
            paragraphItem("Heading", .heading, key: "h")
            paragraphItem("Subheading", .subheading, key: "j")
            paragraphItem("Body", .body, key: "b")
            paragraphItem("Monospaced", .monospaced, key: "m")
            paragraphItem("Block Quote", .blockQuote, key: nil)
            Divider()
            paragraphItem("Checklist", .checklistUnchecked, command: .checklist, key: "l")
            paragraphItem("Bulleted List", .bulletedList, key: "8")
            paragraphItem("Dashed List", .dashedList, key: "7")
            paragraphItem("Numbered List", .numberedList, key: "9")
            Divider()
            Toggle("Bold", isOn: styleBinding(.bold, editor?.inline.bold))
                .keyboardShortcut("b", modifiers: .command)
                .disabled(editor == nil)
            Toggle("Italic", isOn: styleBinding(.italic, editor?.inline.italic))
                .keyboardShortcut("i", modifiers: .command)
                .disabled(editor == nil)
            Toggle("Underline", isOn: styleBinding(.underline, editor?.inline.underline))
                .keyboardShortcut("u", modifiers: .command)
                .disabled(editor == nil)
            Toggle("Strikethrough", isOn: styleBinding(.strikethrough, editor?.inline.strikethrough))
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Divider()
            Button("Increase Indent") { unlocked { editor?.apply(.indentMore) } }
                .disabled(editor == nil)
                .keyboardShortcut("]", modifiers: .command)
            Button("Decrease Indent") { unlocked { editor?.apply(.indentLess) } }
                .disabled(editor == nil)
                .keyboardShortcut("[", modifiers: .command)
            Button("Clear Formatting") { unlocked { editor?.apply(.clearFormatting) } }
                .disabled(editor == nil)
        }
        CommandMenu("Go") {
            Button("Write") { unlocked { navigate("write") } }
                .keyboardShortcut("1", modifiers: .command)
            Button("Entries") { unlocked { navigate("entries") } }
                .keyboardShortcut("2", modifiers: .command)
            Button("Insights") { unlocked { navigate("today") } }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Find in Entries") {
                guard !AppLock.shared.isLocked else { return }
                navigate("entries")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .mirrorMacFocusSearch, object: nil)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Log Mood…") { unlocked { MoodCheckInPresenter.shared.pending = true } }
                .keyboardShortcut("m", modifiers: [.command, .option])
            // ⌘, belongs to the system Settings item in the app menu.
            SettingsLink { Text("Settings…") }
        }
    }

    /// A paragraph-style item with a checkmark when the caret is in that style.
    private func paragraphItem(_ title: LocalizedStringKey, _ style: NoteParagraphTextStyle, command: NoteTextCommand? = nil, key: KeyEquivalent?) -> some View {
        let toggle = Toggle(title, isOn: Binding(
            get: { editor?.paragraph == style },
            set: { _ in unlocked { editor?.apply(command ?? commandFor(style)) } }
        ))
        .disabled(editor == nil)
        return Group {
            if let key { toggle.keyboardShortcut(key, modifiers: [.command, .shift]) } else { toggle }
        }
    }

    private func commandFor(_ style: NoteParagraphTextStyle) -> NoteTextCommand {
        switch style {
        case .title: return .title
        case .heading: return .heading
        case .subheading: return .subheading
        case .monospaced: return .monospaced
        case .blockQuote: return .blockQuote
        case .bulletedList: return .bulletedList
        case .dashedList: return .dashedList
        case .numberedList: return .numberedList
        case .checklistUnchecked, .checklistChecked: return .checklist
        case .body: return .body
        }
    }

    private func styleBinding(_ command: NoteTextCommand, _ isOn: Bool?) -> Binding<Bool> {
        Binding(get: { isOn ?? false }, set: { _ in unlocked { editor?.apply(command) } })
    }

    /// App Lock: every command runs only while unlocked. SwiftUI doesn't re-evaluate these menus
    /// when the lock changes, so disabling them isn't enough (Export as PDF would still write the
    /// selected entry to disk behind the cover).
    private func unlocked(_ action: () -> Void) {
        guard !AppLock.shared.isLocked else { return }
        action()
    }

    private func navigate(_ destination: String) {
        NotificationCenter.default.post(
            name: .mirrorMacNavigate,
            object: nil,
            userInfo: ["destination": destination]
        )
    }
}

/// Brings the main window forward from code that has no view (the notification delegate, the global
/// hotkey). `openWindow` is captured from the menu commands, which live as long as the app does, so
/// a closed main window can still be reopened.
@MainActor
enum MacMainWindow {
    static var openWindow: OpenWindowAction?

    /// The main window: SwiftUI names WindowGroup(id: "main") windows "main-AppWindow-N".
    static var existing: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    static func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = existing {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
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

/// Export an entry from the Mac: a PDF on A4 pages (the same page and margins as iPhone), saved
/// where the user chooses. Plain text, like the iPhone PDF.
enum MacEntryExport {
    /// Writes the PDF to `url`. False when nothing could be written.
    @MainActor
    static func writePDF(for entry: Entry, to url: URL) -> Bool {
        let date = entry.createdAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        var header = date
        if let mood = entry.mood { header += " · " + MirrorTheme.localizedMoodName(for: mood) }

        let page = NSSize(width: 595, height: 842)
        let margin: CGFloat = 57
        let width = page.width - margin * 2

        let body = NSMutableParagraphStyle()
        body.lineSpacing = 6
        let text = NSMutableAttributedString(
            string: header + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.gray]
        )
        let plain = textWithPhotoTokensReplaced(entry.text, placeholder: "")
        text.append(NSAttributedString(string: plain, attributes: [
            .font: NSFont(name: "Georgia", size: 15) ?? NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.black,
            .paragraphStyle: body,
        ]))

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.textContainerInset = .zero
        view.isVerticallyResizable = true
        view.textStorage?.setAttributedString(text)
        if let container = view.textContainer, let layout = view.layoutManager {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            view.frame.size.height = ceil(layout.usedRect(for: container).height)
        }

        let info = NSPrintInfo(dictionary: [
            .jobDisposition: NSPrintInfo.JobDisposition.save,
            .jobSavingURL: url,
        ])
        info.paperSize = page
        info.topMargin = margin; info.bottomMargin = margin; info.leftMargin = margin; info.rightMargin = margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        return operation.run()
    }

    /// Asks where to save, then writes the PDF.
    @MainActor
    static func exportPDF(_ entry: Entry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "MirrorNotes \(entry.createdAt.formatted(.iso8601.year().month().day())).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !writePDF(for: entry, to: url) {
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't save the PDF")
            alert.runModal()
        }
    }
}
#endif
