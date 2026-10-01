#if os(macOS) && DEBUG
import SwiftUI
import SwiftData
import AppKit

// DEBUG-only: renders the Mac UI to PNGs from inside the app, then quits. Run the app binary with
//   --macSnapshot --macSnapshotDir=/some/dir
// It uses an in-memory store and a throwaway encryption key (see MirrorEncryption.debugEphemeralKey
// and MirrorModelContainer.defaultConfiguration), so no real journal data or Keychain item is touched.
// Capturing the app's own window needs no Screen Recording permission.

enum MacSnapshot {
    static var isRequested: Bool { CommandLine.arguments.contains("--macSnapshot") }

    static var outputDirectory: URL {
        let prefix = "--macSnapshotDir="
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }) {
            return URL(fileURLWithPath: String(arg.dropFirst(prefix.count)), isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("mirror-mac-snapshots", isDirectory: true)
    }

    @MainActor
    static func capture(_ window: NSWindow?, name: String) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.displayIfNeeded()
        guard let window, let view = window.contentView?.superview ?? window.contentView else {
            NSLog("MacSnapshot: no window for %@", name)
            return
        }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // Window-server capture of our own window (shows vibrancy/sidebar content that
        // cacheDisplay can skip). Loaded dynamically because the symbol is deprecated.
        typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let fn = unsafeBitCast(sym, to: WindowImageFn.self)
            if let cg = fn(.null, 1 << 3, CGWindowID(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: outputDirectory.appendingPathComponent("\(name)-ws.png"))
                    NSLog("MacSnapshot: wrote %@-ws.png (%dx%d)", name, cg.width, cg.height)
                }
            }
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
            NSLog("MacSnapshot: wrote %@.png (%dx%d)", name, rep.pixelsWide, rep.pixelsHigh)
        }
    }

    @MainActor
    static func run(context: ModelContext) async {
        if MacEditorSelfTest.isRequested {
            let lines = MacEditorSelfTest.run()
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("editor-selftest.txt"), atomically: true, encoding: .utf8)
            for line in lines { NSLog("%@", line) }
            NSApp.terminate(nil)
            return
        }
        if (try? context.fetch(FetchDescriptor<UserProfile>()))?.isEmpty ?? true {
            let profile = UserProfile()
            profile.onboardingComplete = true
            context.insert(profile)
        }
        SampleData.seed(into: context)
        try? context.save()

        func mainWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) && $0.title != "" } ?? NSApp.windows.first { $0.isVisible }
        }
        func go(_ destination: String) {
            NotificationCenter.default.post(name: .mirrorMacNavigate, object: nil, userInfo: ["destination": destination])
        }

        try? await Task.sleep(for: .seconds(3))
        // The board's window size, regardless of any saved frame.
        mainWindow()?.setContentSize(NSSize(width: 1280, height: 800))
        try? await Task.sleep(for: .seconds(1))
        capture(mainWindow(), name: "1-write")

        go("entries")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "2-entries-list")

        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "3-entries-reader")

        NotificationCenter.default.post(name: .mirrorMacDebugOpenEditor, object: nil)
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "3b-editor")

        go("today")
        try? await Task.sleep(for: .seconds(3))
        capture(mainWindow(), name: "4-insights")

        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        try? await Task.sleep(for: .seconds(2))
        let settings = NSApp.windows.first { $0.isVisible && $0 !== mainWindow() }
        capture(settings, name: "5-settings")

        if !CommandLine.arguments.contains("--macSnapshotHold") { NSApp.terminate(nil) }
    }
}

extension Notification.Name {
    static let mirrorMacDebugOpenEditor = Notification.Name("mirror.mac.debug.openEditor")
    static let mirrorMacDebugSelectFirstEntry = Notification.Name("mirror.mac.debug.selectFirstEntry")
}
#endif

#if os(macOS) && DEBUG
// MARK: - Editor self-test

/// Drives the real Mac editor (text view, coordinator, codec) through typing and commands and
/// checks the documents it would save. Run with `--macEditorSelfTest`; prints PASS/FAIL lines.
enum MacEditorSelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--macEditorSelfTest") }

    private final class Box {
        var text: String
        var style: Data?
        var inline: Data?
        var canUndo = false
        var canRedo = false
        var active: NoteParagraphTextStyle = .body
        var flags = InlineStyleSet()
        var command: NoteTextCommand?
        var revision = 0
        init(text: String, style: Data? = nil, inline: Data? = nil) { self.text = text; self.style = style; self.inline = inline }
    }

    @MainActor
    private static func makeEditor(_ box: Box) -> (MirrorNSTextView, NoteEditorTextView.Coordinator) {
        let view = NoteEditorTextView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            textStyleData: Binding(get: { box.style }, set: { box.style = $0 }),
            inlineStyleData: Binding(get: { box.inline }, set: { box.inline = $0 }),
            photoDataArray: .constant([]),
            command: Binding(get: { box.command }, set: { box.command = $0 }),
            commandRevision: Binding(get: { box.revision }, set: { box.revision = $0 }),
            isFocused: .constant(false),
            activeParagraphStyle: Binding(get: { box.active }, set: { box.active = $0 }),
            activeInlineStyles: Binding(get: { box.flags }, set: { box.flags = $0 }),
            showFormattingPanel: .constant(false),
            canUndo: Binding(get: { box.canUndo }, set: { box.canUndo = $0 }),
            canRedo: Binding(get: { box.canRedo }, set: { box.canRedo = $0 }),
            fontChoiceRaw: .constant(WritingFontChoice.system.rawValue),
            panelState: FormattingPanelState(),
            displayMode: .classic,
            onPhotoTapped: nil
        )
        let coordinator = NoteEditorTextView.Coordinator(parent: view)
        let textView = NoteEditorTextView.makeConfiguredTextView(coordinator: coordinator)
        // An undo manager needs a window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = textView
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        return (textView, coordinator)
    }

    private static func styles(_ data: Data?) -> [String] {
        NoteEditorCodec.decodeTextStyleDocument(data)?.paragraphStyles.map(\.rawValue) ?? []
    }
    private static func ranges(_ data: Data?) -> [InlineStyleRange] {
        NoteEditorCodec.decodeInlineStyleDocument(data)?.ranges ?? []
    }

    @MainActor
    static func run() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            out.append("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — " + detail())")
        }

        // 1. A paragraph style applies to the selected paragraph and is saved.
        do {
            let box = Box(text: "Title line\nsecond")
            let (tv, c) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 2, length: 0))
            c.apply(.heading, to: tv)
            check("heading on first paragraph", styles(box.style) == ["heading", "body"], "\(styles(box.style))")
            check("text unchanged by styling", box.text == "Title line\nsecond", box.text)
        }

        // 2. Inline bold on a selection is saved as a logical range; toggling again removes it.
        do {
            let box = Box(text: "Title line\nsecond")
            let (tv, c) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 11, length: 6))
            c.apply(.bold, to: tv)
            check("bold range", ranges(box.inline).map { [$0.location, $0.length] } == [[11, 6]] && ranges(box.inline).first?.bold == true, "\(ranges(box.inline))")
            c.apply(.bold, to: tv)
            check("bold toggles off", box.inline == nil, "\(ranges(box.inline))")
        }

        // 3. Return at the end of a styled paragraph continues that style; typing lands in it.
        do {
            let box = Box(text: "Title line\nsecond", style: try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: [.heading, .body], indentLevels: nil, fontChoices: ["system", "system"])))
            let (tv, _) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 10, length: 0))
            tv.insertNewline(nil)
            tv.insertText("abc", replacementRange: tv.selectedRange())
            check("return continues heading", box.text == "Title line\nabc\nsecond", box.text)
            check("styles after return", styles(box.style) == ["heading", "heading", "body"], "\(styles(box.style))")
        }

        // 4. A list continues on Return, including an empty trailing item that iOS also stores.
        do {
            let box = Box(text: "one")
            let (tv, c) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 3, length: 0))
            c.apply(.bulletedList, to: tv)
            tv.setSelectedRange(NSRange(location: 3, length: 0))
            tv.insertNewline(nil)
            check("list text", box.text == "one\n", box.text.debugDescription)
            check("empty trailing list item stored", styles(box.style) == ["bulletedList", "bulletedList"], "\(styles(box.style))")
            tv.insertText("two", replacementRange: tv.selectedRange())
            check("typed second item", box.text == "one\ntwo" && styles(box.style) == ["bulletedList", "bulletedList"], "\(box.text.debugDescription) \(styles(box.style))")
        }

        // 5. Backspace joining two paragraphs keeps the preceding paragraph's style.
        do {
            let box = Box(text: "Head\nbody", style: try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: [.heading, .body], indentLevels: nil, fontChoices: ["system", "system"])))
            let (tv, _) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 5, length: 0))
            tv.deleteBackward(nil)
            check("merged text", box.text == "Headbody", box.text)
            check("merge keeps preceding style", styles(box.style) == ["heading"], "\(styles(box.style))")
        }

        // 6. Undo reverses a formatting change.
        do {
            let box = Box(text: "undo me")
            let (tv, c) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 0, length: 4))
            c.apply(.italic, to: tv)
            check("italic applied", ranges(box.inline).first?.italic == true, "\(ranges(box.inline))")
            check("can undo", box.canUndo)
            c.apply(.undo, to: tv)
            check("undo removes italic", ranges(tv.textStorage.map { NoteEditorCodec.extractInlineStyleData(from: $0) } ?? nil).isEmpty)
        }

        // 7. Stored documents survive load → save unchanged (iOS-authored fixture).
        do {
            let styleDoc = try? JSONEncoder().encode(NoteTextStyleDocument(
                paragraphStyles: [.title, .body, .numberedList, .numberedList, .checklistUnchecked],
                indentLevels: [0, 0, 0, 1, 0], fontChoices: Array(repeating: "system", count: 5)))
            let inlineDoc = try? JSONEncoder().encode(InlineStyleDocument(ranges: [
                InlineStyleRange(location: 6, length: 4, bold: true, italic: false, underline: true, strikethrough: false, highlightIndex: 1, linkURL: nil, textColorIndex: nil)]))
            let box = Box(text: "Title\nbody text\nstep one\nsub step\ntodo", style: styleDoc, inline: inlineDoc)
            let (tv, c) = makeEditor(box)
            // Touch the document without changing it.
            tv.setSelectedRange(NSRange(location: 3, length: 0))
            tv.insertText("x", replacementRange: tv.selectedRange())
            tv.deleteBackward(nil)
            check("untouched documents round trip", box.style == styleDoc || styles(box.style) == styles(styleDoc), "\(styles(box.style)) vs \(styles(styleDoc))")
            check("indent preserved", NoteEditorCodec.decodeTextStyleDocument(box.style)?.indentLevels == [0, 0, 0, 1, 0], "\(String(describing: NoteEditorCodec.decodeTextStyleDocument(box.style)?.indentLevels))")
            check("inline preserved", ranges(box.inline).map { [$0.location, $0.length] } == [[6, 4]] && ranges(box.inline).first?.highlightIndex == 1, "\(ranges(box.inline))")
            _ = c
        }

        // 8. Pasting is plain text.
        do {
            let box = Box(text: "")
            let (tv, _) = makeEditor(box)
            NSPasteboard.general.clearContents()
            let rich = NSAttributedString(string: "rich", attributes: [.font: NSFont.boldSystemFont(ofSize: 30), .foregroundColor: NSColor.red])
            NSPasteboard.general.writeObjects([rich])
            tv.paste(nil)
            check("paste inserts text", box.text == "rich", box.text)
            check("paste adds no inline styles", box.inline == nil, "\(ranges(box.inline))")
        }

        return out
    }
}
#endif
