#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

// The Settings window (Cmd-,), built to the approved board: 720 x 560, a title row, five icon
// tabs, and a form. Appearance is the board's own design; the other tabs hold the existing
// settings screens.

enum MacSettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, subscription, privacy, diagnostics

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .subscription: return "Subscription"
        case .privacy: return "iCloud & Privacy"
        case .diagnostics: return "Diagnostics"
        }
    }

    var icon: String {
        switch self {
        case .general: return "general"
        case .appearance: return "palette"
        case .subscription: return "card"
        case .privacy: return "cloud"
        case .diagnostics: return "pulse"
        }
    }

    var width: CGFloat { self == .privacy ? 104 : 92 }

    /// Diagnostics holds debug-only tools, so release builds do not show the tab.
    static var visible: [MacSettingsTab] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter { $0 != .diagnostics }
        #endif
    }
}

/// One icon tab. The selected state is an input, so the pill redraws when the tab changes.
private struct MacSettingsTabButton: View {
    let item: MacSettingsTab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                MacIcon(name: item.icon, size: 20)
                Text(item.title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    // Long translations ("Erscheinungsbild", サブスクリプション) shrink to fit the tab
                    // instead of breaking mid-word or wrapping; English is unchanged.
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
            }
            .frame(width: item.width, height: 52)
            .foregroundStyle(selected ? MacTokens.accentInk : MacTokens.controlInk)
            .background(selected ? MacTokens.tabSelectedFill : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(MacHoverButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(item.title)
    }
}

struct MacSettingsRoot: View {
    @AppStorage("macSettingsTab") private var tabRaw = MacSettingsTab.general.rawValue

    private var tab: MacSettingsTab { MacSettingsTab(rawValue: tabRaw).flatMap { MacSettingsTab.visible.contains($0) ? $0 : nil } ?? .general }

    /// Height of the title bar zone the content runs under.
    private static let titlebarInset: CGFloat = {
        NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 720, height: 560), styleMask: [.titled, .closable, .miniaturizable]).height - 560
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Tab changes replace the pane in place; inherited animations must not fade
                // or resize the window while AppKit is updating its hosting view.
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
        // Drawn 560 pt tall from the top edge, but laid out `inset` shorter: the window adds the
        // title bar zone back, so it comes out at the board's 560.
        .frame(width: 720, height: 560, alignment: .top)
        .frame(width: 720, height: 560 - Self.titlebarInset, alignment: .top)
        .background(MacTokens.windowBackground)
        .background(MacSettingsWindowConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.appDisplayMode, .classic)
    }

    // MARK: Title row and tabs

    private var header: some View {
        // Capture the value, rather than making ForEach's stored row builder read a
        // computed property through self. The row builder must depend on this selection
        // so its existing buttons update without recreating the whole tab strip.
        let selectedTab = tab
        return VStack(spacing: 0) {
            Text(tab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacTokens.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            HStack(spacing: 4) {
                ForEach(MacSettingsTab.visible) { item in
                    MacSettingsTabButton(item: item, selected: item == selectedTab) {
                        tabRaw = item.rawValue
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .background(MacTokens.sidebarBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(MacTokens.sidebarBorder).frame(height: 1) }
    }

    // MARK: Panes

    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .appearance:
            MacAppearanceSettings()
        case .general:
            scrolling { ProtocolSettingsView() }
        case .subscription:
            scrolling { SubscriptionView(embedded: true) }
        case .privacy:
            scrolling {
                VStack(spacing: 0) {
                    // Keep each pane's padding: overlapping their backgrounds clips the
                    // preceding card's rounded corners and shadow.
                    ArchiveSettingsView()
                    if SubscriptionService.shared.isSubscribed || SubscriptionService.allFeaturesFree {
                        SmartSearchSettingsView()
                    }
                    ManualSettingsView()
                }
            }
        case .diagnostics:
            #if DEBUG
            scrolling { DiagnosticsSettingsView() }
            #else
            EmptyView()
            #endif
        }
    }

    /// The existing screens inside the window's own scroll view, in a centered column.
    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .environment(\.settingsEmbedded, true)
                .toggleStyle(.switch)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
        .modifier(MacNoScrollEdgeEffect())
    }
}

// MARK: - Appearance tab (the board)

struct MacAppearanceSettings: View {
    @AppStorage("mirrorAppearanceMode") private var appearance = "system"
    @AppStorage(MacPrefs.fontKey) private var font = WritingFontChoice.serif.rawValue
    @AppStorage(MacPrefs.sizeKey) private var size = MacPrefs.defaultSize
    @AppStorage(MacPrefs.widthKey) private var width = MacPrefs.LineWidth.comfortable.rawValue

    private var previewDesign: Font.Design {
        WritingFontChoice(rawValue: font)?.swiftUIDesign ?? .serif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            row("Appearance:") {
                MacSegmented(selection: $appearance, options: [("system", "System", 84), ("light", "Light", 84), ("dark", "Dark", 84)])
            }

            row("Writing font:") {
                fontMenu
            }

            row("Text size:") {
                HStack(spacing: 16) {
                    Slider(value: Binding(get: { size }, set: { size = $0.rounded() }), in: MacPrefs.sizeRange)
                        .tint(MacTokens.accent)
                        .frame(width: 220)
                        .accessibilityLabel("Text size")
                    Text("\(Int(size)) pt")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTokens.secondaryInk)
                        .frame(width: 40, alignment: .leading)
                }
            }

            row("Line width:") {
                MacSegmented(selection: $width, options: [("narrow", "Narrow", 84), ("comfortable", "Comfortable", 104), ("wide", "Wide", 84)])
            }

            HStack(alignment: .top, spacing: 16) {
                Text("Preview:")
                    .foregroundStyle(MacTokens.controlInk)
                    .frame(width: 150, alignment: .trailing)
                    .padding(.top, 14)
                Text("The street was quiet except for a delivery van and someone watering plants two floors down.")
                    .font(.system(size: CGFloat(size), design: previewDesign))
                    .lineSpacing(CGFloat(size) * 0.5)
                    .foregroundStyle(MacTokens.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(width: MacPrefs.lineWidth(width) == .narrow ? 300 : MacPrefs.lineWidth(width) == .wide ? 400 : 350, alignment: .leading)
                    .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MacTokens.divider, lineWidth: 1) }
                    .frame(width: 400, alignment: .leading)
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .onChange(of: appearance) { _, new in applyAppearance(new) }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let fontOptions: [(value: String, title: String)] = [
        (WritingFontChoice.serif.rawValue, "Serif (New York)"),
        (WritingFontChoice.system.rawValue, "Sans (SF Pro)"),
        (WritingFontChoice.monospaced.rawValue, "Mono (SF Mono)"),
    ]

    /// The board's popup: a white, bordered field with the up/down chevrons.
    private var fontMenu: some View {
        Menu {
            ForEach(Self.fontOptions, id: \.value) { option in
                Button {
                    font = option.value
                } label: {
                    if option.value == font { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 0) {
                Text(LocalizedStringKey(Self.fontOptions.first { $0.value == font }?.title ?? "Serif (New York)"))
                    .foregroundStyle(MacTokens.ink)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MacTokens.controlInk)
            }
            .padding(.horizontal, 8)
            .frame(width: 220, height: 26)
            .background(MacTokens.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.settingsControlBorder, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Writing font")
    }

    /// The main window applies the stored choice too, but it may be closed while Settings is open.
    private func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private func row<Control: View>(_ label: LocalizedStringKey, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(MacTokens.controlInk)
                .frame(width: 150, alignment: .trailing)
            control()
        }
    }
}

/// The board's segmented control: a bordered white strip, the chosen segment filled with the accent.
struct MacSegmented: View {
    @Binding var selection: String
    let options: [(value: String, title: LocalizedStringKey, width: CGFloat)]

    var body: some View {
        let currentSelection = selection
        return HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                let selected = option.value == currentSelection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : MacTokens.ink)
                        .frame(width: option.width, height: 26)
                        .background(selected ? MacTokens.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    if index > 0, !selected {
                        Rectangle().fill(MacTokens.segmentDivider).frame(width: 1)
                    }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(MacTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(MacTokens.settingsControlBorder, lineWidth: 1) }
    }
}

// MARK: - Window

/// Makes the Settings window's title bar transparent so the board's title row and tabs run to the
/// top edge, with the traffic lights centered in the 38 pt title row.
struct MacSettingsWindowConfigurator: NSViewRepresentable {
    private static var configuredKey = 0
    private static var observationsKey = 0
    /// Held for the life of the window they observe (released with the window's own observers).

    /// Configures as soon as the view joins a window; SwiftUI does not call back once it has.
    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            MacSettingsWindowConfigurator.configure(window)
        }
    }

    func makeNSView(context: Context) -> NSView { Probe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    fileprivate static func configure(_ window: NSWindow?) {
        guard let window else { return }
        // SwiftUI updates this representable when the selected tab changes. Reapplying
        // fullSizeContentView and the title-bar geometry then invalidates window layout.
        guard objc_getAssociatedObject(window, &Self.configuredKey) == nil else { return }
        objc_setAssociatedObject(window, &Self.configuredKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Settings")
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 8 / 255, green: 6 / 255, blue: 15 / 255, alpha: 1)
                : NSColor(srgbRed: 242 / 255, green: 238 / 255, blue: 248 / 255, alpha: 1)
        }
        MacWindowConfigurator.positionTrafficLights(in: window, rowHeight: 38)
        // AppKit moves the buttons back on some events; observe once per window.
        // Marked on the window itself: an address-keyed set could skip a recreated window.
        // The Settings scene re-applies its own title bar style; keep the board's.
        let observations = [
            window.observe(\.titlebarAppearsTransparent, options: [.new]) { window, _ in
                if !window.titlebarAppearsTransparent { DispatchQueue.main.async { window.titlebarAppearsTransparent = true } }
            },
            window.observe(\.titleVisibility, options: [.new]) { window, _ in
                if window.titleVisibility != .hidden { DispatchQueue.main.async { window.titleVisibility = .hidden } }
            },
            // Embedded screens set a navigation title ("Journal"); the window is "Settings".
            window.observe(\.title, options: [.new]) { window, _ in
                let name = String(localized: "Settings")
                if window.title != name { DispatchQueue.main.async { window.title = name } }
            },
        ]
        objc_setAssociatedObject(window, &Self.observationsKey, observations, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                if let window { MacWindowConfigurator.positionTrafficLights(in: window, rowHeight: 38) }
            }
        }
    }
}
#endif
