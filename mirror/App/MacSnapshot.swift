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
        capture(mainWindow(), name: "1-write")

        go("entries")
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "2-entries-list")

        NotificationCenter.default.post(name: .mirrorMacDebugSelectFirstEntry, object: nil)
        try? await Task.sleep(for: .seconds(2))
        capture(mainWindow(), name: "3-entries-reader")

        go("insights")
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
    static let mirrorMacDebugSelectFirstEntry = Notification.Name("mirror.mac.debug.selectFirstEntry")
}
#endif
