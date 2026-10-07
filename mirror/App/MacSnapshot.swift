#if os(macOS) && DEBUG
import SwiftUI
import SwiftData
import AppKit
import SceneKit
import PDFKit

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

    /// Re-applied before every capture: the app refreshes the plan and appearance on its own.
    @MainActor
    static func applyOverrides() {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--macSnapshotTier=") }),
           let tier = SubscriptionTier(rawValue: String(arg.dropFirst("--macSnapshotTier=".count))) {
            SubscriptionService.shared.debugSetTier(tier)
        }
        if CommandLine.arguments.contains("--macSnapshotDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Settings > Appearance preferences: Write and the reader at other sizes and widths, changed
    /// while the screens are open (the live-update path), then put back.
    @MainActor
    static func prefsPass(mainWindow: () -> NSWindow?, go: (String) -> Void) async {
        let defaults = UserDefaults.standard
        func set(_ size: Double, _ width: String, font: String = "serif") {
            defaults.set(size, forKey: MacPrefs.sizeKey)
            defaults.set(width, forKey: MacPrefs.widthKey)
            defaults.set(font, forKey: MacPrefs.fontKey)
        }
        set(22, "wide")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "8a-write-22-wide")
        set(14, "narrow")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "8b-write-14-narrow")
        go("entries")
        try? await Task.sleep(for: .seconds(1.5))
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "8c-reader-14-narrow")
        set(22, "wide")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "8d-reader-22-wide")
        set(18, "comfortable")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "8e-reader-18-comfortable")
        go("write")
        try? await Task.sleep(for: .seconds(1.5))
        defaults.removeObject(forKey: MacPrefs.sizeKey)
        defaults.removeObject(forKey: MacPrefs.widthKey)
        defaults.removeObject(forKey: MacPrefs.fontKey)
    }

    private static func describeMenus(_ label: String) {
        NSLog("MacSnapshot: [%@] app active = %@, key window = %@", label, NSApp.isActive ? "yes" : "no", NSApp.keyWindow != nil ? "yes" : "no")
        NSApp.mainMenu?.update()
        // SwiftUI refreshes item states as a menu opens; do that for the menus we read.
        for menu in NSApp.mainMenu?.items ?? [] { menu.submenu?.delegate?.menuNeedsUpdate?(menu.submenu!) }
        guard let menus = NSApp.mainMenu?.items else { return }
        NSLog("MacSnapshot: menu bar = %@", menus.map(\.title).joined(separator: " | "))
        for menu in menus where ["File", "Format", "Go"].contains(menu.title) {
            for item in menu.submenu?.items ?? [] {
                let mods = item.keyEquivalentModifierMask
                let keys = (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "") + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "") + (item.keyEquivalent == "\r" ? "↩" : item.keyEquivalent)
                NSLog("MacSnapshot: [%@] %@ > %@ %@ %@%@", label, menu.title, item.isSeparatorItem ? "—" : item.title, item.isSeparatorItem ? "" : keys, item.isEnabled ? "" : "(disabled)", item.state == .on ? " ✓" : "")
            }
        }
    }

    /// The File and Go menus as the app really builds them, in Write and in the reader, and the
    /// New Entry in New Window item.
    @MainActor
    static func menusPass(mainWindow: () -> NSWindow?, go: (String) -> Void) async {
        mainWindow()?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(2))
        describeMenus("write")
        go("entries")
        try? await Task.sleep(for: .seconds(1.5))
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(2))
        describeMenus("reader")
        if let file = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu,
           let index = file.items.firstIndex(where: { $0.title.hasSuffix("Pin Entry") }) {
            NSLog("MacSnapshot: pin item = %@ enabled=%@", file.items[index].title, file.items[index].isEnabled ? "yes" : "no")
            file.performActionForItem(at: index)
            try? await Task.sleep(for: .seconds(1))
            describeMenus("after-pin")
        }
        let before = NSApp.windows.filter(\.isVisible).count
        if let file = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu,
           let index = file.items.firstIndex(where: { $0.title == "New Entry in New Window" }) {
            file.performActionForItem(at: index)
        }
        try? await Task.sleep(for: .seconds(2.5))
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
        NSLog("MacSnapshot: windows %d -> %d", before, windows.count)
        if let fresh = windows.first(where: { $0 !== mainWindow() }) {
            NSLog("MacSnapshot: new window size = %@", NSStringFromSize(fresh.frame.size))
            capture(fresh, name: "9-new-entry-window")
            try? await Task.sleep(for: .seconds(3))
            capture(fresh, name: "9b-new-entry-window-later")
            fresh.setContentSize(NSSize(width: 900, height: 820))
            try? await Task.sleep(for: .seconds(2))
            capture(fresh, name: "9c-new-entry-window-resized")
        }
    }

    /// The quick-capture popover in an ordinary window (a menu bar panel can't be captured the
    /// same way), saved through the same model the popover uses.
    @MainActor
    static func quickCapturePass(context: ModelContext) async {
        let model = MacQuickCaptureModel.shared
        if CommandLine.arguments.contains("--macSnapshotQuickAlign") {
            let host = NSHostingController(rootView: MacQuickCaptureView().environment(\.modelContext, context).modelContainer(context.container))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.borderless]
            window.setContentSize(NSSize(width: 400, height: 420))
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            model.text = ""
            try? await Task.sleep(for: .seconds(2))
            capture(window, name: "q-empty")
            model.text = "What's on your mind?"
            try? await Task.sleep(for: .seconds(1.5))
            capture(window, name: "q-typed")
            return
        }
        model.text = "Left the meeting early and felt relieved, which says something. Want to write about it properly tonight."
        model.mood = "Hopeful"
        let host = NSHostingController(rootView: MacQuickCaptureView().environment(\.modelContext, context).modelContainer(context.container))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.borderless]
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 400, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(2))
        capture(window, name: "10-quick-capture")

        model.showAllMoods = true
        try? await Task.sleep(for: .seconds(1))
        capture(window, name: "10b-quick-capture-all-moods")
        model.showAllMoods = false
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .seconds(1))
        capture(window, name: "10d-quick-capture-light")
        NSApp.appearance = nil

        let before = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1
        let saved = model.save(in: context)
        let after = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1
        NSLog("MacSnapshot: quick capture saved = %@, entries %d -> %d, draft cleared = %@", saved ? "yes" : "no", before, after, model.text.isEmpty ? "yes" : "no")
        try? await Task.sleep(for: .seconds(1.5))
        capture(window, name: "10c-quick-capture-saved")
        model.text = ""
        let blocked = model.save(in: context)
        NSLog("MacSnapshot: quick capture empty save blocked = %@", blocked ? "no" : "yes")
    }

    /// Mac-vs-iPhone parity checks, one section per surface, each reading real state.
    @MainActor
    static func parityPass(context: ModelContext, mainWindow: () -> NSWindow?, go: (String) -> Void) async {
        mainWindow()?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        go("write")
        try? await Task.sleep(for: .seconds(2))

        // Write: the entry date sheet.
        NotificationCenter.default.post(name: .mirrorMacDebugWrite, object: nil, userInfo: ["action": "openDate"])
        try? await Task.sleep(for: .seconds(1.5))
        let popover = NSApp.windows.first { $0.isVisible && $0.className.contains("Popover") }
        NSLog("MacSnapshot: date popover presented = %@ size = %@", popover != nil ? "yes" : "no", NSStringFromSize(popover?.frame.size ?? .zero))
        capture(popover ?? mainWindow(), name: "11-write-date-popover")

        // The popover's rule for combining a picked day with the chosen time.
        do {
            let cal = Calendar.current
            let now = cal.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!
            let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
            let evening = cal.date(bySettingHour: 21, minute: 15, second: 0, of: now)!
            let a = MacEntryDatePopover.combining(day: yesterday, time: evening, now: now)
            let b = MacEntryDatePopover.combining(day: now, time: evening, now: now)
            NSLog("MacSnapshot: date combine: yesterday keeps 21:15 = %@, today at a later time is held to now = %@",
                  (cal.isDate(a, inSameDayAs: yesterday) && cal.component(.hour, from: a) == 21 && cal.component(.minute, from: a) == 15) ? "yes" : "no",
                  b == now ? "yes" : "no")
        }
        // Change the date the way the popover does and save; read the stored entry back.
        let target = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        NotificationCenter.default.post(name: .mirrorMacDebugWrite, object: nil, userInfo: ["action": "setDate", "date": target])
        try? await Task.sleep(for: .seconds(1))
        capture(mainWindow(), name: "11b-write-date-changed")
        NotificationCenter.default.post(name: .mirrorMacDebugWrite, object: nil, userInfo: ["action": "save"])
        try? await Task.sleep(for: .seconds(2))
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        if let saved = all.first(where: { $0.text.hasPrefix("Slow morning. I made coffee") }) {
            let sameDay = Calendar.current.isDate(saved.createdAt, inSameDayAs: target)
            NSLog("MacSnapshot: saved entry on chosen day = %@, weekIdentifier matches = %@", sameDay ? "yes" : "no", saved.weekIdentifier == DateHelpers.weekIdentifier(for: target) ? "yes" : "no")
        } else {
            NSLog("MacSnapshot: saved entry not found")
        }

        // Entries calendar in Year mode (and Month, for comparison).
        for mode in ["Year", "Month"] {
            UserDefaults.standard.set(mode, forKey: "heatmapMode")
            go("entries")
            try? await Task.sleep(for: .seconds(1.5))
            NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["calendar": true])
            try? await Task.sleep(for: .seconds(1.5))
            capture(mainWindow(), name: "13-calendar-\(mode.lowercased())")
        }
        UserDefaults.standard.removeObject(forKey: "heatmapMode")
        NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["calendar": false])

        // The photo viewer, opened from Write's photo tile.
        go("write"); try? await Task.sleep(for: .seconds(2))
        NotificationCenter.default.post(name: .mirrorMacDebugWrite, object: nil, userInfo: ["action": "openPhoto"])
        try? await Task.sleep(for: .seconds(2))
        let viewer = mainWindow()?.attachedSheet
        NSLog("MacSnapshot: photo viewer presented = %@ size = %@", viewer != nil ? "yes" : "no", NSStringFromSize(viewer?.frame.size ?? .zero))
        capture(viewer ?? mainWindow(), name: "15-photo-viewer")
        if let viewer { mainWindow()?.endSheet(viewer) }
        try? await Task.sleep(for: .seconds(1))

        // Export a real entry to PDF and read it back.
        if let first = (try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?.first {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mirror-parity-export.pdf")
            try? FileManager.default.removeItem(at: url)
            let wrote = MacEntryExport.writePDF(for: first, to: url)
            let doc = PDFDocument(url: url)
            let text = doc?.string ?? ""
            NSLog("MacSnapshot: pdf written = %@, pages = %d, contains entry text = %@", wrote ? "yes" : "no", doc?.pageCount ?? 0, text.contains(String(first.text.prefix(12))) ? "yes" : "no")
        }
        for dest in ["write", "entries", "today", "ask"] {
            go(dest)
            try? await Task.sleep(for: .seconds(1))
            NSLog("MacSnapshot: window title on %@ = %@", dest, mainWindow()?.title ?? "none")
        }

        // Entries: keyboard navigation with real key events.
        go("entries")
        try? await Task.sleep(for: .seconds(2))
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(1.5))
        if let window = mainWindow() {
            func key(_ code: UInt16, _ chars: String, to target: NSWindow? = nil) {
                let w = target ?? window
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                                    isARepeat: false, keyCode: code) { w.sendEvent(event) }
                }
            }
            key(125, "\u{F701}"); try? await Task.sleep(for: .seconds(0.6))
            key(125, "\u{F701}"); try? await Task.sleep(for: .seconds(0.6))
            key(126, "\u{F700}"); try? await Task.sleep(for: .seconds(0.6))
            capture(window, name: "12-entries-keyboard-moved")
            let before = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1
            key(51, "\u{7F}"); try? await Task.sleep(for: .seconds(1.5))
            NSLog("MacSnapshot: delete key shows confirmation = %@", window.attachedSheet != nil ? "yes" : "no")
            capture(window.attachedSheet ?? window, name: "12c-entries-delete-confirm")
            if let sheet = window.attachedSheet { key(53, "\u{1b}", to: sheet) }
            try? await Task.sleep(for: .seconds(1.5))
            let after = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1
            NSLog("MacSnapshot: after Esc entries %d -> %d, dialog closed = %@", before, after, window.attachedSheet == nil ? "yes" : "no")
            key(36, "\r"); try? await Task.sleep(for: .seconds(1.5))
            capture(window, name: "12b-entries-return-edits")
        }
    }

    /// Opens Settings the way a user does (the app menu item), captures every tab, then checks a
    /// sheet opened from a settings row, the Appearance choice, and closing and reopening.
    @MainActor
    static func settingsPass(mainWindow: () -> NSWindow?) async {
        UserDefaults.standard.set("general", forKey: "macSettingsTab")

        func openSettings() async {
            // Key focus may sit in a window from an earlier step; make the main window key first.
            mainWindow()?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .seconds(1))
            var opened = false
            if let appMenu = NSApp.mainMenu?.items.first?.submenu {
                for (index, item) in appMenu.items.enumerated() where item.keyEquivalent == "," {
                    appMenu.performActionForItem(at: index)
                    opened = true
                }
            }
            if !opened {
                NSLog("MacSnapshot: no Settings menu item (menu items: %d)", NSApp.mainMenu?.items.count ?? -1)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            try? await Task.sleep(for: .seconds(2))
        }
        func settingsWindow() -> NSWindow? { NSApp.windows.first { $0.isVisible && abs($0.frame.width - 720) < 1 } }

        await openSettings()
        for tab in MacSettingsTab.visible {
            UserDefaults.standard.set(tab.rawValue, forKey: "macSettingsTab")
            try? await Task.sleep(for: .seconds(1.5))
            capture(settingsWindow(), name: "5-settings-\(tab.rawValue)")
        }
        NSLog("MacSnapshot: settings window title = %@", settingsWindow()?.title ?? "none")

        // Rapid switching exercises hosting-view updates that settled screenshots miss.
        // The window and traffic-light positions must remain fixed throughout every tab.
        if let window = settingsWindow() {
            let frame = window.frame
            let closeFrame = window.standardWindowButton(.closeButton)?.frame
            var stable = true
            var samples = 0
            for _ in 0..<3 {
                for tab in MacSettingsTab.visible {
                    UserDefaults.standard.set(tab.rawValue, forKey: "macSettingsTab")
                    for _ in 0..<3 {
                        try? await Task.sleep(for: .milliseconds(30))
                        samples += 1
                        stable = stable && window.frame == frame
                            && window.standardWindowButton(.closeButton)?.frame == closeFrame
                            && window.title == String(localized: "Settings")
                    }
                }
            }
            NSLog("MacSnapshot: rapid settings switching geometry/title = %@ (%d samples)", stable ? "PASS" : "FAIL", samples)
        }

        // A sheet opened from a settings row (General > Voice transcription language), closed by Escape.
        UserDefaults.standard.set("general", forKey: "macSettingsTab")
        try? await Task.sleep(for: .seconds(1.5))
        if let window = settingsWindow() {
            window.makeKeyAndOrderFront(nil)
            let pressed = pressElement(labelContaining: "transcription language", in: window.contentView)
            NSLog("MacSnapshot: pressed settings row = %@", pressed ? "yes" : "no")
            try? await Task.sleep(for: .seconds(1.5))
            let sheet = window.attachedSheet
            NSLog("MacSnapshot: settings row sheet presented = %@", sheet != nil ? "yes" : "no")
            capture(sheet ?? window, name: "5b-settings-row-sheet")
            if let sheet { sendEscape(to: sheet) }
            try? await Task.sleep(for: .seconds(1.5))
            NSLog("MacSnapshot: settings row sheet closed by Escape = %@", window.attachedSheet == nil ? "yes" : "no")
        }

        // The Appearance choice, written the way the control does, reaches both windows.
        UserDefaults.standard.set("appearance", forKey: "macSettingsTab")
        UserDefaults.standard.set("dark", forKey: "mirrorAppearanceMode")
        try? await Task.sleep(for: .seconds(2))
        capture(settingsWindow(), name: "5c-settings-chose-dark")
        capture(mainWindow(), name: "5d-main-chose-dark")
        UserDefaults.standard.set(CommandLine.arguments.contains("--macSnapshotDark") ? "dark" : "system", forKey: "mirrorAppearanceMode")
        if !CommandLine.arguments.contains("--macSnapshotDark") { NSApp.appearance = nil }

        // Close and reopen: the board's chrome must come back.
        settingsWindow()?.performClose(nil)
        try? await Task.sleep(for: .seconds(1.5))
        NSLog("MacSnapshot: settings closed = %@", settingsWindow() == nil ? "yes" : "no")
        await openSettings()
        capture(settingsWindow(), name: "5e-settings-reopened")
        NSLog("MacSnapshot: settings reopened title = %@", settingsWindow()?.title ?? "none")
    }

    @MainActor
    static func capture(_ window: NSWindow?, name: String) {
        applyOverrides()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Let activation land before the window-server capture, or the first capture of a run shows
        // inactive (grey) traffic lights.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
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

        applyOverrides()
        UserDefaults.standard.set(CommandLine.arguments.contains("--macSnapshotDark") ? "dark" : "system", forKey: "mirrorAppearanceMode")

        func mainWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) && abs($0.frame.width - 720) > 1 } ?? NSApp.windows.first { $0.isVisible }
        }
        func go(_ destination: String) {
            NotificationCenter.default.post(name: .mirrorMacNavigate, object: nil, userInfo: ["destination": destination])
        }

        try? await Task.sleep(for: .seconds(3))
        // The board's window size, regardless of any saved frame.
        mainWindow()?.setContentSize(NSSize(width: 1280, height: 800))
        try? await Task.sleep(for: .seconds(1))
        if CommandLine.arguments.contains("--macSnapshotFiltersOnly") {
            go("entries")
            try? await Task.sleep(for: .seconds(1))
            NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["filters": true])
            try? await Task.sleep(for: .seconds(1))
            capture(mainWindow()?.sheets.first ?? mainWindow(), name: "archive-filter-controls")
            NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil,
                                            userInfo: ["filters": false, "filterMoods": ["Content", "Anxious"]])
            try? await Task.sleep(for: .seconds(1))
            capture(mainWindow(), name: "archive-active-filters")
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotSearchOnly") {
            go("entries")
            try? await Task.sleep(for: .seconds(1))
            for (name, query) in [("archive-search", "coffee -zzzz"), ("archive-invalid-filter", "has:video")] {
                NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["search": query])
                try? await Task.sleep(for: .seconds(1))
                capture(mainWindow(), name: name)
            }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotQuickCaptureOnly") {
            await quickCapturePass(context: context)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotNightlyCheck") {
            let cal = Calendar.current
            func at(_ h: Int, _ m: Int = 0, daysAgo: Int = 0) -> Date {
                let base = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
                return cal.date(bySettingHour: h, minute: m, second: 0, of: base)!
            }
            let cases: [(String, Bool)] = [
                ("2am", mirrorApp.macNightlyIsDue(now: at(2), lastRun: nil)),
                ("3:30am never run", mirrorApp.macNightlyIsDue(now: at(3, 30), lastRun: nil)),
                ("3:30am ran yesterday", mirrorApp.macNightlyIsDue(now: at(3, 30), lastRun: at(4, daysAgo: 1))),
                ("4am already ran 3:10", mirrorApp.macNightlyIsDue(now: at(4), lastRun: at(3, 10))),
                ("5:59am not run today", mirrorApp.macNightlyIsDue(now: at(5, 59), lastRun: at(23, daysAgo: 1))),
                ("6am", mirrorApp.macNightlyIsDue(now: at(6), lastRun: nil)),
                ("2pm", mirrorApp.macNightlyIsDue(now: at(14), lastRun: nil)),
            ]
            for (name, due) in cases { NSLog("MacSnapshot: nightly due [%@] = %@", name, due ? "yes" : "no") }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotOnboardingOnly") {
            let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
            profiles.first?.onboardingComplete = false
            try? context.save()
            try? await Task.sleep(for: .seconds(2))
            for step in 0...3 {
                NotificationCenter.default.post(name: .mirrorMacDebugOnboardingStep, object: nil, userInfo: ["step": step])
                try? await Task.sleep(for: .seconds(1.2))
                let sheet = mainWindow()?.attachedSheet
                NSLog("MacSnapshot: onboarding step %d sheet = %@", step, NSStringFromSize(sheet?.frame.size ?? .zero))
                capture(sheet ?? mainWindow(), name: "14-onboarding-\(step)")
            }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotParityOnly") {
            await parityPass(context: context, mainWindow: mainWindow, go: go)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotMenusOnly") {
            await menusPass(mainWindow: mainWindow, go: go)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotSettingsOnly") {
            await settingsPass(mainWindow: mainWindow)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--macSnapshotUIPolishOnly") {
            for page in ["report", "mood"] {
                go(page)
                try? await Task.sleep(for: .seconds(2))
                capture(mainWindow(), name: "6-\(page)")
                if page == "report", let window = mainWindow() {
                    window.makeKeyAndOrderFront(nil)
                    for (key, code) in [("\u{f702}", UInt16(123)), ("\u{f703}", UInt16(124))] {
                        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                       context: nil, characters: key, charactersIgnoringModifiers: key,
                                                       isARepeat: false, keyCode: code) {
                            // Use the application's normal dispatch path, like the Entries
                            // keyboard checks; calling NSWindow directly bypasses shortcuts.
                            NSApp.sendEvent(event)
                            try? await Task.sleep(for: .milliseconds(300))
                            capture(window, name: "6-report-key-\(code)")
                        }
                    }
                }
            }
            await settingsPass(mainWindow: mainWindow)
            NSApp.terminate(nil)
            return
        }
        capture(mainWindow(), name: "1-write")
        if CommandLine.arguments.contains("--macSnapshotPrefs") {
            await prefsPass(mainWindow: mainWindow, go: go)
            if CommandLine.arguments.contains("--macSnapshotPrefsOnly") { NSApp.terminate(nil); return }
        }
        if CommandLine.arguments.contains("--macSnapshotPanel") {
            NotificationCenter.default.post(name: .mirrorMacDebugOpenFormatPanel, object: nil)
            try? await Task.sleep(for: .seconds(1.5))
            for (index, window) in NSApp.windows.filter({ $0.isVisible && $0 !== mainWindow() }).enumerated() {
                capture(window, name: "1b-panel-\(index)")
            }
        }

        go("entries")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "2-entries-list")

        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "3-entries-reader")

        NotificationCenter.default.post(name: .mirrorMacDebugOpenEditor, object: nil)
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "3b-editor")

        // Edge states of the Entries screen.
        let all = (try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        if let first = all.first { first.isPinned = true; try? context.save() }
        NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["calendar": true])
        try? await Task.sleep(for: .seconds(1.5))
        capture(mainWindow(), name: "2b-pinned-calendar")
        NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["calendar": false, "search": "zzzzqq-no-match"])
        try? await Task.sleep(for: .seconds(1.5))
        capture(mainWindow(), name: "2c-no-results")
        NotificationCenter.default.post(name: .mirrorMacDebugEntriesState, object: nil, userInfo: ["search": ""])
        try? await Task.sleep(for: .seconds(1))

        // An entry removed behind the reader's back (another device's delete arriving by sync).
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(1.5))
        if let open = (try? context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])))?.first {
            context.delete(open)
            try? context.save()
        }
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "3d-external-delete")
        NSLog("MacSnapshot: external delete survived")

        // Deleting the entry open in the reader must not crash or leave a stale reader.
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(1.5))
        let beforeCount = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1
        NotificationCenter.default.post(name: .mirrorMacDebugConfirmDelete, object: nil)
        try? await Task.sleep(for: .seconds(2))
        let afterCount = (try? context.fetchCount(FetchDescriptor<Entry>())) ?? -1
        NSLog("MacSnapshot: delete check %d -> %d", beforeCount, afterCount)
        capture(mainWindow(), name: "3c-after-delete")

        // Today with whatever state the data so far produces (no reflection seeded yet).
        go("today")
        try? await Task.sleep(for: .seconds(3))
        capture(mainWindow(), name: "4a-insights-unseeded")

        // Today: a loaded reflection, past reflections, and the inspector.
        SampleData.seedTodayReflection(into: context)
        SampleData.seedPastNudges(into: context)
        // A grounded reflection (synthetic text) in the shape the Gemma path saves, with the entry it quotes.
        let todayID = DateHelpers.dayIdentifier(for: Date())
        for stale in ((try? context.fetch(FetchDescriptor<Insight>())) ?? []) where stale.type == .dailyNudge && stale.periodIdentifier == todayID {
            context.delete(stale)
        }
        let quoted = Entry(text: "Slow day. Nothing went wrong and I still feel flat. I'm tired more than I'm upset.", mood: "Drained", source: .typed)
        quoted.createdAt = Date().addingTimeInterval(-86_400)
        quoted.weekIdentifier = DateHelpers.weekIdentifier(for: quoted.createdAt)
        context.insert(quoted)
        context.insert(Insight(
            type: .dailyNudge,
            content: "You wrote, \"I'm tired more than I'm upset.\" That sounds like a day that asked a lot of you.",
            periodIdentifier: todayID,
            generatedByEngine: .gemma
        ))
        try? context.save()
        go("today")
        try? await Task.sleep(for: .seconds(3))
        capture(mainWindow(), name: "4-insights")
        NotificationCenter.default.post(name: .mirrorMacDebugToggleInspector, object: nil, userInfo: ["open": true])
        try? await Task.sleep(for: .seconds(1.5))
        capture(mainWindow(), name: "4b-inspector")
        mainWindow()?.setContentSize(NSSize(width: 980, height: 700))
        try? await Task.sleep(for: .seconds(1.5))
        capture(mainWindow(), name: "4c-inspector-narrow")
        mainWindow()?.setContentSize(NSSize(width: 1280, height: 800))
        // Inspector "Open" → Entries with that entry selected in the reader.
        NotificationCenter.default.post(name: .mirrorMacOpenEntry, object: nil, userInfo: ["id": quoted.id])
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "4d-open-from-inspector")
        // Follow-up chip → Write with the question already in the entry.
        NotificationCenter.default.post(name: .mirrorMacNewEntrySeeded, object: nil, userInfo: ["text": "Can you say more about \u{201C}Nothing went wrong and I still feel flat\u{201D}?\n"])
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "4e-chip-write")
        go("today")
        NotificationCenter.default.post(name: .mirrorMacDebugToggleInspector, object: nil, userInfo: ["open": false])
        try? await Task.sleep(for: .seconds(1))

        // Insights sub-pages (no boards: the shared title bar around the existing content).
        SampleData.seedWeeklyDigestSample(into: context)
        SampleData.seedPriorWeekDigestSample(into: context)
        SampleData.seedMonthlyReportSample(into: context)
        SampleData.seedAskSample(into: context)
        for page in ["digest", "report", "mood", "ask", "brain"] {
            go(page)
            try? await Task.sleep(for: .seconds(3))
            capture(mainWindow(), name: "6-\(page)")
            if page == "brain" {
                try? await Task.sleep(for: .seconds(2))
                capture(mainWindow(), name: "6-brain-3d-later")
                await brainInputChecks()
                NotificationCenter.default.post(name: .mirrorMacDebugBrainDimension, object: nil, userInfo: ["is3D": false])
                try? await Task.sleep(for: .seconds(1.5))
                capture(mainWindow(), name: "6-brain-2d")
            }
        }

        // The first capture of a run (1-write) is taken before macOS lets the app become the active app, so its
        // traffic lights are grey. Write again now that the app is active: this is the one for store screenshots.
        go("write")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "9-write-active")

        // Entries as a store screenshot: the seed also holds French voice-note samples (language tests) and
        // entries tagged with the sample marker, which would show as "#__sample__". Drop both, then show the
        // list with the newest entry open in the reader.
        let seeded = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        for entry in seeded {
            if entry.tags.contains("french") { context.delete(entry); continue }
            entry.tags.removeAll { $0 == SampleData.sampleTag }
        }
        try? context.save()
        go("entries")
        try? await Task.sleep(for: .seconds(2.5))
        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(2.5))
        capture(mainWindow(), name: "10-entries-store")

        // Go > Log Mood… presents the check-in sheet. Opt-in (--macSnapshotMood): it pops a modal
        // over the window, which is disruptive when the capture run is watched.
        if CommandLine.arguments.contains("--macSnapshotMood") {
            MoodCheckInPresenter.shared.pending = true
            try? await Task.sleep(for: .seconds(2))
            NSLog("MacSnapshot: mood sheet presented = %@", mainWindow()?.attachedSheet != nil ? "yes" : "no")
            capture(mainWindow()?.attachedSheet ?? mainWindow(), name: "4f-log-mood")
            if let sheet = mainWindow()?.attachedSheet { mainWindow()?.endSheet(sheet) }
            try? await Task.sleep(for: .seconds(1))
        }
        await settingsPass(mainWindow: mainWindow)

        if !CommandLine.arguments.contains("--macSnapshotHold") { NSApp.terminate(nil) }
    }
}

extension Notification.Name {
    /// userInfo["step"]: jumps the onboarding flow to that step.
    static let mirrorMacDebugOnboardingStep = Notification.Name("mirror.mac.debug.onboardingStep")
    /// userInfo["action"]: "openDate", "setDate" (+ "date"), "save". Drives Write from the harness.
    static let mirrorMacDebugWrite = Notification.Name("mirror.mac.debug.write")
    static let mirrorMacDebugBrainSheet = Notification.Name("mirror.mac.debug.brainSheet")
    static let mirrorMacDebugBrainDimension = Notification.Name("mirror.mac.debug.brainDimension")
    static let mirrorMacDebugToggleInspector = Notification.Name("mirror.mac.debug.toggleInspector")
    static let mirrorMacDebugConfirmDelete = Notification.Name("mirror.mac.debug.confirmDelete")
    static let mirrorMacDebugOpenFormatPanel = Notification.Name("mirror.mac.debug.openFormatPanel")
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

        // 2b. Notes-like inline styling. A caret with no selection sets the style for what is typed
        // next; a second press stops it; the buttons' state follows the caret; mixed selections
        // go all-on; Undo reverts.
        do {
            // Bold with the caret only, then type.
            let box = Box(text: "plain ")
            let (tv, c) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 6, length: 0))
            c.apply(.bold, to: tv)
            check("caret bold: button reports on", box.flags.bold, "\(box.flags)")
            tv.insertText("abc", replacementRange: tv.selectedRange())
            check("caret bold: typed text is bold", ranges(box.inline).map { [$0.location, $0.length] } == [[6, 3]] && ranges(box.inline).first?.bold == true, "\(ranges(box.inline))")
            // Still bold while typing on; press again to stop, type plain.
            check("caret bold: still on after typing", box.flags.bold, "\(box.flags)")
            c.apply(.bold, to: tv)
            check("caret bold: second press reports off", !box.flags.bold, "\(box.flags)")
            tv.insertText("xyz", replacementRange: tv.selectedRange())
            check("caret bold: text after the second press is plain", ranges(box.inline).map { [$0.location, $0.length] } == [[6, 3]], "\(ranges(box.inline))")
            // The caret moving into bold text reports bold, and back out reports plain.
            tv.setSelectedRange(NSRange(location: 8, length: 0))
            check("caret inside bold text reports bold", box.flags.bold, "\(box.flags)")
            tv.setSelectedRange(NSRange(location: 2, length: 0))
            check("caret in plain text reports plain", !box.flags.bold, "\(box.flags)")
        }
        do {
            // Underline and italic with the caret only.
            let box = Box(text: "")
            let (tv, c) = makeEditor(box)
            c.apply(.underline, to: tv)
            check("caret underline: button reports on", box.flags.underline, "\(box.flags)")
            tv.insertText("under", replacementRange: tv.selectedRange())
            check("caret underline: typed text is underlined", ranges(box.inline).first?.underline == true && ranges(box.inline).first?.length == 5, "\(ranges(box.inline))")
            c.apply(.italic, to: tv)
            tv.insertText("both", replacementRange: tv.selectedRange())
            let last = ranges(box.inline).last
            check("caret italic stacks on underline", last?.italic == true && last?.underline == true, "\(ranges(box.inline))")
        }
        do {
            // A selection that is partly bold goes all bold on the first press, plain on the second, and Undo restores.
            let box = Box(text: "one two three")
            let (tv, c) = makeEditor(box)
            // One click is one undo step; the run loop does not turn over inside this test.
            func click(_ command: NoteTextCommand) {
                tv.undoManager?.beginUndoGrouping(); c.apply(command, to: tv); tv.undoManager?.endUndoGrouping()
            }
            tv.undoManager?.groupsByEvent = false
            tv.setSelectedRange(NSRange(location: 0, length: 3))
            click(.bold)
            tv.setSelectedRange(NSRange(location: 0, length: 7))
            click(.bold)
            check("mixed selection goes all bold", ranges(box.inline).map { [$0.location, $0.length] } == [[0, 7]], "\(ranges(box.inline))")
            click(.bold)
            check("all-bold selection goes plain", box.inline == nil, "\(ranges(box.inline))")
            c.apply(.undo, to: tv)
            check("undo brings the bold back", ranges(box.inline).map { [$0.location, $0.length] } == [[0, 7]], "\(ranges(box.inline))")
        }
        do {
            // Typing at the end of bold text continues it, like Notes.
            let box = Box(text: "bold")
            let (tv, c) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 0, length: 4))
            c.apply(.bold, to: tv)
            tv.setSelectedRange(NSRange(location: 4, length: 0))
            tv.insertText("er", replacementRange: tv.selectedRange())
            check("typing after bold text continues the bold", ranges(box.inline).map { [$0.location, $0.length] } == [[0, 6]], "\(ranges(box.inline))")
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

        func doc(_ styles: [NoteParagraphTextStyle], indents: [Int]? = nil) -> Data? {
            try? JSONEncoder().encode(NoteTextStyleDocument(paragraphStyles: styles, indentLevels: indents, fontChoices: Array(repeating: "system", count: styles.count)))
        }

        // 9. Return on an empty list item leaves the list.
        do {
            let box = Box(text: "one\n", style: doc([.bulletedList, .bulletedList]))
            let (tv, _) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 4, length: 0))
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            check("return on empty item keeps text", box.text == "one\n", box.text.debugDescription)
            check("return on empty item exits the list", styles(box.style) == ["bulletedList"], "\(styles(box.style))")
        }

        // 10. Backspace at the start of a list item removes the list style first.
        do {
            let box = Box(text: "a\nb", style: doc([.bulletedList, .bulletedList]))
            let (tv, _) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 2, length: 0))
            tv.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            check("backspace keeps text", box.text == "a\nb", box.text)
            check("backspace turns the item into body", styles(box.style) == ["bulletedList", "body"], "\(styles(box.style))")
        }

        // 11. Tab and Shift-Tab change a list item's level.
        do {
            let box = Box(text: "a\nb", style: doc([.bulletedList, .bulletedList]))
            let (tv, _) = makeEditor(box)
            tv.setSelectedRange(NSRange(location: 3, length: 0))
            tv.doCommand(by: #selector(NSResponder.insertTab(_:)))
            check("tab indents", NoteEditorCodec.decodeTextStyleDocument(box.style)?.indentLevels == [0, 1], "\(String(describing: NoteEditorCodec.decodeTextStyleDocument(box.style)?.indentLevels))")
            tv.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
            check("shift-tab outdents", NoteEditorCodec.decodeTextStyleDocument(box.style)?.indentLevels == nil, "\(String(describing: NoteEditorCodec.decodeTextStyleDocument(box.style)?.indentLevels))")
        }

        // 12. Checklist commands.
        do {
            let box = Box(text: "a\nb\nc", style: doc([.checklistUnchecked, .checklistChecked, .checklistUnchecked]))
            let (tv, c) = makeEditor(box)
            c.apply(.checkAllItems, to: tv)
            check("check all", styles(box.style) == ["checklistChecked", "checklistChecked", "checklistChecked"], "\(styles(box.style))")
            c.apply(.uncheckAllItems, to: tv)
            check("uncheck all", styles(box.style) == ["checklistUnchecked", "checklistUnchecked", "checklistUnchecked"], "\(styles(box.style))")
        }
        do {
            let box = Box(text: "a\nb\nc", style: doc([.checklistUnchecked, .checklistChecked, .checklistUnchecked]))
            let (tv, c) = makeEditor(box)
            c.apply(.deleteCheckedItems, to: tv)
            check("delete checked removes the row", box.text == "a\nc" && styles(box.style) == ["checklistUnchecked", "checklistUnchecked"], "\(box.text.debugDescription) \(styles(box.style))")
        }
        do {
            let box = Box(text: "x\ny\nz", style: doc([.checklistChecked, .checklistUnchecked, .checklistUnchecked]))
            let (tv, c) = makeEditor(box)
            c.apply(.sortCheckedToBottom, to: tv)
            check("sort checked to bottom", box.text == "y\nz\nx" && styles(box.style) == ["checklistUnchecked", "checklistUnchecked", "checklistChecked"], "\(box.text.debugDescription) \(styles(box.style))")
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

// MARK: - Brain View input checks (DEBUG)

extension MacSnapshot {
    @MainActor
    private static func firstSCNView(in view: NSView?) -> SCNView? {
        guard let view else { return nil }
        if let scn = view as? SCNView { return scn }
        for sub in view.subviews { if let found = firstSCNView(in: sub) { return found } }
        return nil
    }

    @MainActor
    private static func send(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, clicks: Int = 1) {
        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { return }
        window.sendEvent(event)
    }

    /// Presses the first accessibility element whose label contains `text`, like assistive tech does.
    @MainActor
    private static func pressElement(labelContaining text: String, in root: Any?) -> Bool {
        guard let element = root as? NSAccessibilityProtocol else { return false }
        if let label = element.accessibilityLabel(), label.localizedCaseInsensitiveContains(text), element.accessibilityPerformPress() { return true }
        var children = element.accessibilityChildren() ?? []
        if children.isEmpty, let view = root as? NSView { children = view.subviews }
        for child in children where pressElement(labelContaining: text, in: child) { return true }
        return false
    }

    @MainActor
    private static func pngBytes(_ name: String) -> Data? {
        try? Data(contentsOf: outputDirectory.appendingPathComponent("\(name)-ws.png"))
    }

    @MainActor
    private static func sendEscape(to window: NSWindow) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                           isARepeat: false, keyCode: 53) else { return }
        window.sendEvent(event)
    }

    /// Real mouse events into the 3D view, and the Escape key into each sheet Brain View can open.
    @MainActor
    static func brainInputChecks() async {
        func mainWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) && abs($0.frame.width - 720) > 1 } ?? NSApp.windows.first { $0.isVisible }
        }
        guard let window = mainWindow() else { return }
        NotificationCenter.default.post(name: .mirrorMacDebugBrainDimension, object: nil, userInfo: ["is3D": true])
        try? await Task.sleep(for: .seconds(1.5))
        guard let scn = firstSCNView(in: window.contentView) else { NSLog("MacSnapshot: brain input: no SCNView"); return }
        let center = scn.convert(NSPoint(x: scn.bounds.midX, y: scn.bounds.midY), to: nil)

        // Auto-rotate is running: two frames apart differ.
        capture(window, name: "7-brain-a"); try? await Task.sleep(for: .seconds(2)); capture(window, name: "7-brain-b")
        NSLog("MacSnapshot: brain input: auto-rotate moves frames = %@", pngBytes("7-brain-a") != pngBytes("7-brain-b") ? "yes" : "no")

        // A click on the hub turns auto-rotate off: later frames identical.
        send(.leftMouseDown, at: center, in: window); send(.leftMouseUp, at: center, in: window)
        try? await Task.sleep(for: .seconds(2)); capture(window, name: "7-brain-c")
        try? await Task.sleep(for: .seconds(2)); capture(window, name: "7-brain-d")
        NSLog("MacSnapshot: brain input: click stops auto-rotate = %@", pngBytes("7-brain-c") == pngBytes("7-brain-d") ? "yes" : "no")

        // Drag orbits, and the window must not move.
        let frameBefore = window.frame
        send(.leftMouseDown, at: center, in: window)
        for step in 1...12 {
            send(.leftMouseDragged, at: NSPoint(x: center.x + CGFloat(step) * 12, y: center.y + CGFloat(step) * 3), in: window)
        }
        send(.leftMouseUp, at: NSPoint(x: center.x + 144, y: center.y + 36), in: window)
        try? await Task.sleep(for: .seconds(1)); capture(window, name: "7-brain-e")
        NSLog("MacSnapshot: brain input: drag changes view = %@, window moved = %@", pngBytes("7-brain-d") != pngBytes("7-brain-e") ? "yes" : "no", window.frame == frameBefore ? "no" : "yes")

        // Double-click resets the camera (and the view changes back).
        send(.leftMouseDown, at: center, in: window, clicks: 2); send(.leftMouseUp, at: center, in: window, clicks: 2)
        try? await Task.sleep(for: .seconds(1)); capture(window, name: "7-brain-f")
        NSLog("MacSnapshot: brain input: double-click changes view = %@", pngBytes("7-brain-e") != pngBytes("7-brain-f") ? "yes" : "no")

        // Sheets: open, then Escape through the real key path.
        for kind in ["node", "ask"] {
            NotificationCenter.default.post(name: .mirrorMacDebugBrainSheet, object: nil, userInfo: ["kind": kind])
            try? await Task.sleep(for: .seconds(2))
            let sheet = window.attachedSheet
            NSLog("MacSnapshot: brain sheet %@ presented = %@", kind, sheet != nil ? "yes" : "no")
            capture(sheet ?? window, name: "7-brain-sheet-\(kind)")
            if let sheet { sendEscape(to: sheet) }
            try? await Task.sleep(for: .seconds(1.5))
            NSLog("MacSnapshot: brain sheet %@ closed by Escape = %@", kind, window.attachedSheet == nil ? "yes" : "no")
        }
    }
}
#endif
