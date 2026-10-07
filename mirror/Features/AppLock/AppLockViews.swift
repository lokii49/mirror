import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// What App Lock draws (see AppLock.swift for when). The cover is opaque, not a blur: a blur still
// shows the shape of the page. iOS covers each window scene with a window of its own above alert
// level, which also covers sheets and alerts; the Mac covers every app window, sheets included.

/// The theme the app is in, for views that live outside ContentView's environment (the cover
/// windows). ContentView keeps this in the app group for the widgets.
private var currentDisplayMode: DisplayMode {
    UserDefaults(suiteName: "group.com.lokesh.mirror")?.string(forKey: "widget.displayMode")
        .flatMap(DisplayMode.init(rawValue:)) ?? .classic
}

struct AppLockScreen: View {
    /// False for the app-switcher cover: content hidden, nothing to unlock.
    var interactive = true
    @State private var lock = AppLock.shared
    @Environment(\.appDisplayMode) private var displayMode

    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }

    var body: some View {
        ZStack {
            MirrorTheme.bgBase.ignoresSafeArea()
            if interactive && lock.isLocked {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 72, height: 72)
                        .background(accent.opacity(0.12), in: Circle())
                    Text("MirrorNotes is locked")
                        .font(displayMode == .sentinel ? MirrorTheme.mono(17) : .system(size: 20, weight: .semibold))
                        .foregroundStyle(MirrorTheme.textPrimary)
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text(unlockTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 22)
                            .frame(height: 42)
                            .background(accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(lock.isAuthenticating)
                    .keyboardShortcut(.defaultAction)
                    if let reason = lock.unavailableReason {
                        Text(reason)
                            .font(.system(size: 13))
                            .foregroundStyle(MirrorTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                }
                .padding(24)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(MirrorTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var unlockTitle: String {
        switch AppLock.method {
        case .faceID: return String(localized: "Unlock with Face ID")
        case .touchID: return String(localized: "Unlock with Touch ID")
        case .opticID: return String(localized: "Unlock with Optic ID")
        case .passcode, .unavailable:
            #if os(macOS)
            return String(localized: "Unlock with Password")
            #else
            return String(localized: "Unlock with Passcode")
            #endif
        }
    }
}

/// Settings > Your Data (Archive in Sentinel; iCloud & Privacy on the Mac).
struct AppLockSettingsGroup: View {
    @State private var lock = AppLock.shared
    @State private var working = false

    var body: some View {
        SettingsGroup(title: "Privacy") {
            HStack {
                SettingsRowLabel(title: "App Lock", systemImage: "lock.fill", iconColor: .indigo)
                Spacer()
                Toggle("App Lock", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { on in
                        working = true
                        Task {
                            await lock.setEnabled(on)
                            working = false
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(MirrorTheme.primary)
                .disabled(working || AppLock.method == .unavailable)
            }

            Text(caption)
                .font(.system(size: 12.5))
                .foregroundStyle(MirrorTheme.textSecondary)
                .padding(.leading, 44)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var caption: String {
        let when: String
        switch AppLock.method {
        case .unavailable: return AppLock.unavailableText
        case .faceID: when = String(localized: "Asks for Face ID when you open MirrorNotes and after 5 minutes away.")
        case .touchID: when = String(localized: "Asks for Touch ID when you open MirrorNotes and after 5 minutes away.")
        case .opticID: when = String(localized: "Asks for Optic ID when you open MirrorNotes and after 5 minutes away.")
        case .passcode:
            #if os(macOS)
            when = String(localized: "Asks for your Mac password when you open MirrorNotes and after 5 minutes away.")
            #else
            when = String(localized: "Asks for your passcode when you open MirrorNotes and after 5 minutes away.")
            #endif
        }
        return when + " " + String(localized: "Widgets and notifications can still show lines from your reflections.")
    }
}

#if os(iOS)
/// Put in ContentView's background: covers the window scene ContentView is in with a window above
/// everything else (sheets and alerts included) while `AppLock.hidesContent`.
struct AppLockWindowInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { AppLockCoverWindows.install(in: scene) }
        }
    }
}

@MainActor
enum AppLockCoverWindows {
    private static var windows: [ObjectIdentifier: UIWindow] = [:]
    private static var observing = false

    static func install(in scene: UIWindowScene) {
        let key = ObjectIdentifier(scene)
        guard windows[key] == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isHidden = true
        windows[key] = window
        observe()
        apply()
    }

    /// Show/hide is driven from here, not from a view inside the cover window: SwiftUI doesn't
    /// update a hidden window's views, so a view-driven cover never came back after an unlock.
    private static func observe() {
        guard !observing else { return }
        observing = true
        withObservationTracking {
            _ = AppLock.shared.hidesContent
            _ = AppLock.shared.isLocked
        } onChange: {
            Task { @MainActor in
                observing = false
                observe()
                apply()
            }
        }
    }

    private static func apply() {
        let lock = AppLock.shared
        for (key, window) in windows {
            guard window.windowScene != nil else { windows[key] = nil; continue }
            if lock.hidesContent {
                if lock.isLocked {
                    // Drop the keyboard: typing must not reach the hidden editor. The draft stays.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                matchStyle(window)
                // A fresh root each time, so what's shown matches the state now.
                let root = UIHostingController(rootView: AppLockScreen(interactive: lock.isLocked)
                    .environment(\.appDisplayMode, currentDisplayMode))
                root.view.backgroundColor = .clear
                window.rootViewController = root
                window.isHidden = false
                window.makeKey()
            } else if !window.isHidden {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene?.windows.first { $0 !== window && !$0.isHidden && $0.windowLevel == .normal }?.makeKey()
            }
        }
    }

    /// Light/dark as the app's own windows have it (Sentinel forces dark; ContentView sets it on the
    /// windows that exist at the time, which may be before this one).
    private static func matchStyle(_ cover: UIWindow) {
        if let app = cover.windowScene?.windows.first(where: { $0 !== cover && $0.windowLevel == .normal }) {
            cover.overrideUserInterfaceStyle = app.overrideUserInterfaceStyle
        }
    }
}
#endif

#if os(macOS)
/// Covers every app window (main, entry, new entry, Settings, sheets and alerts) while locked, and
/// any window that opens while locked. Quick capture stays usable: it only writes.
@MainActor
enum AppLockMacCovers {
    private static var covers: [ObjectIdentifier: (window: NSWindow, cover: NSView, responder: NSResponder?)] = [:]
    private static var observers: [NSObjectProtocol] = []

    /// Starts the away tracking and the covers. Called once at launch (not in harness runs).
    static func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.didLeave() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.didReturn() }
        })
        // A frontmost app never resigns active when the user walks away: the screen locking or the
        // Mac sleeping counts as away too.
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.didLeave() }
        })
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if NSApp.isActive { AppLock.shared.didReturn() } }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLock.shared.didLeave() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if NSApp.isActive { AppLock.shared.didReturn() } }
        })
        // New windows (and sheets) while locked get a cover as soon as AppKit shows them.
        observers.append(center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { sync() }
        })
        sync()
    }

    static func sync() {
        let locked = AppLock.shared.isLocked
        if locked {
            for window in NSApp.windows where needsCover(window) && covers[ObjectIdentifier(window)] == nil {
                cover(window)
            }
        }
        for (key, entry) in covers where !locked || !entry.window.isVisible {
            entry.cover.removeFromSuperview()
            if !locked, let responder = entry.responder { entry.window.makeFirstResponder(responder) }
            covers[key] = nil
        }
    }

    private static func needsCover(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.contentView != nil else { return false }
        // Menus, the menu bar item and its popover sit at status-bar level and above.
        if window.level.rawValue >= NSWindow.Level.statusBar.rawValue { return false }
        let name = String(describing: type(of: window))
        return name != "QuickCapturePanel" && !name.contains("ToolTip")
    }

    private static func cover(_ window: NSWindow) {
        // The frame view, not the content view, so the title bar and toolbar are covered too.
        guard let frameView = window.contentView?.superview else { return }
        let isMain = window.identifier?.rawValue.hasPrefix("main") == true
        let host = NSHostingView(rootView: AppLockScreen(interactive: isMain || !hasMainWindow)
            .environment(\.appDisplayMode, currentDisplayMode))
        host.frame = frameView.bounds
        host.autoresizingMask = [.width, .height]
        frameView.addSubview(host, positioned: .above, relativeTo: nil)
        let responder = window.firstResponder
        // Keystrokes must not reach a hidden editor; the text stays where it was.
        window.makeFirstResponder(host)
        covers[ObjectIdentifier(window)] = (window, host, responder)
    }

    /// Only one window shows the Unlock button when the main window is open.
    private static var hasMainWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }
    }
}
#endif
