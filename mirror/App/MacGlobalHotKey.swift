#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI
import SwiftData

/// The global quick-capture shortcut (default ⌥⌘J): opens quick capture from any app. Carbon's RegisterEventHotKey works inside the App Sandbox and needs no Accessibility
/// permission, unlike an NSEvent global monitor. Registration fails when another app already holds
/// the combination; `registrationFailed` lets Settings say so.
@Observable
@MainActor
final class MacGlobalHotKey {
    static let shared = MacGlobalHotKey()

    struct Shortcut: Equatable {
        /// A virtual key code (kVK_*).
        var keyCode: UInt32
        /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
        var modifiers: UInt32

        static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey | cmdKey))

        /// "⌥⌘J", in the order macOS menus use.
        var display: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            return s + Self.keyName(keyCode)
        }

        /// Needs ⌘, ⌥ or ⌃: a bare key or ⇧+key would take over normal typing everywhere.
        var isAcceptable: Bool {
            modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
        }

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// From a key-down event in the recorder.
        init(event: NSEvent) {
            keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var m: UInt32 = 0
            if flags.contains(.command) { m |= UInt32(cmdKey) }
            if flags.contains(.option) { m |= UInt32(optionKey) }
            if flags.contains(.control) { m |= UInt32(controlKey) }
            if flags.contains(.shift) { m |= UInt32(shiftKey) }
            modifiers = m
        }

        private static func keyName(_ code: UInt32) -> String {
            if let name = fKeys[Int(code)] { return name }
            switch Int(code) {
            case kVK_Space: return String(localized: "Space")
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Delete: return "⌫"
            case kVK_LeftArrow: return "←"
            case kVK_RightArrow: return "→"
            case kVK_UpArrow: return "↑"
            case kVK_DownArrow: return "↓"
            default: break
            }
            // The character this key types on the current keyboard layout, unshifted.
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = data.withUnsafeBytes { buffer -> OSStatus in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
                return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                      OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            }
            guard status == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }

        private static let fKeys: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
    }

    private static let enabledKey = "quickCaptureHotKeyEnabled"
    private static let keyCodeKey = "quickCaptureHotKeyCode"
    private static let modifiersKey = "quickCaptureHotKeyModifiers"

    private(set) var shortcut: Shortcut
    private(set) var isEnabled: Bool
    /// True when the last registration was refused (another app holds the combination).
    private(set) var registrationFailed = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        let d = UserDefaults.standard
        isEnabled = d.object(forKey: Self.enabledKey) as? Bool ?? true
        if let code = d.object(forKey: Self.keyCodeKey) as? Int, let mods = d.object(forKey: Self.modifiersKey) as? Int {
            shortcut = Shortcut(keyCode: UInt32(code), modifiers: UInt32(mods))
        } else {
            shortcut = .default
        }
    }

    /// Called once at launch.
    func start(container: ModelContainer) {
        MacQuickCaptureOpener.container = container
        installHandlerIfNeeded()
        register()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        register()
    }

    func setShortcut(_ new: Shortcut) {
        guard new.isAcceptable else { return }
        shortcut = new
        UserDefaults.standard.set(Int(new.keyCode), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(new.modifiers), forKey: Self.modifiersKey)
        register()
    }

    /// Suspends the shortcut while Settings is recording a new one, so pressing the current
    /// combination records it instead of opening quick capture.
    func suspend() { unregister() }
    func resume() { register() }

    private func register() {
        unregister()
        registrationFailed = false
        guard isEnabled else { return }
        let id = EventHotKeyID(signature: OSType(0x4D4E5143), id: 1) // "MNQC"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            hotKeyRef = nil
            registrationFailed = true
        }
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in MacQuickCaptureOpener.open() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}

/// The quick-capture panel the shortcut opens: the menu bar popover's view (same draft, same save
/// path) in a floating panel near the top of the active screen, like Spotlight. SwiftUI's
/// MenuBarExtra can't be opened from code (its status button has no target or action), so the
/// shortcut doesn't reuse that popover. Esc or clicking elsewhere closes it; the draft stays.
@MainActor
enum MacQuickCaptureOpener {
    static var container: ModelContainer?
    private static var panel: NSPanel?

    static func open() {
        guard let container else { return }
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        let panel = panel ?? makePanel(container: container)
        self.panel = panel
        position(panel)
        // A non-activating panel takes the keyboard without bringing the app (and its main window)
        // forward, so Esc returns you to the app you were in.
        panel.makeKeyAndOrderFront(nil)
    }

    private static func makePanel(container: ModelContainer) -> NSPanel {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: MacQuickCaptureView().modelContainer(container))
        host.sizingOptions = [.preferredContentSize]
        panel.contentView = host
        return panel
    }

    /// Centered horizontally, a fifth of the way down the screen the pointer is on.
    private static func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height / 5 - size.height,
            width: size.width,
            height: size.height
        ), display: true)
    }
}

/// Borderless panels refuse key status by default; quick capture needs typing. Closes when the
/// user clicks elsewhere, like the menu bar popover.
private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        close()
    }
}

/// Settings row: on/off plus a recorder. Click the shortcut, press the new combination; Esc cancels.
struct MacQuickCaptureHotKeyRow: View {
    @State private var hotKey = MacGlobalHotKey.shared
    @State private var recording = false
    @State private var rejected = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SettingsRowLabel(title: "Quick capture shortcut", systemImage: "keyboard", iconColor: MirrorTheme.violet)
                Spacer()
                Button(recording ? String(localized: "Type a shortcut…") : hotKey.shortcut.display) {
                    recording ? stopRecording() : startRecording()
                }
                .disabled(!hotKey.isEnabled)
                .help("Click, then press the new shortcut. Esc cancels.")
                Toggle("", isOn: Binding(get: { hotKey.isEnabled }, set: { hotKey.setEnabled($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(MirrorTheme.primary)
            }
            Group {
                if rejected {
                    Text("Use ⌘, ⌥ or ⌃ with a key.")
                } else if hotKey.registrationFailed && hotKey.isEnabled {
                    Text("Another app is using \(hotKey.shortcut.display). Choose a different shortcut.")
                        .foregroundStyle(Color.red)
                } else {
                    Text("Opens quick capture from any app.")
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(MirrorTheme.textSecondary)
            .padding(.leading, 44)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        rejected = false
        recording = true
        hotKey.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let candidate = MacGlobalHotKey.Shortcut(event: event)
            if candidate.isAcceptable {
                hotKey.setShortcut(candidate)
                stopRecording()
            } else {
                rejected = true
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            hotKey.resume()
        }
    }
}
#endif
