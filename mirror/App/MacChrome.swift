#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

// The Mac window chrome and sidebar, built to the approved design (the "MirrorNotes Mac UI"
// boards): a flat 232 pt sidebar with Write, Entries and an INSIGHTS group, a footer line, and
// a window whose title bar is transparent so the traffic lights sit on the sidebar.

// MARK: - Design tokens (from the boards; light / dark)

enum MacTokens {
    static let windowBackground = MirrorTheme.hex(0x08060F, 0xF2EEF8)
    static let sidebarBackground = MirrorTheme.hex(0x0D0A17, 0xE9E3F5)
    static let sidebarBorder = MirrorTheme.hex(0x221E3A, 0xD9D0EE)
    static let ink = MirrorTheme.hex(0xF2EEF8, 0x1A1530)
    static let secondaryInk = MirrorTheme.hex(0x9A93B5, 0x6B6485)
    static let accent = MirrorTheme.hex(0x7C5CE4, 0x6341CC)
    /// Cards and controls sitting on the window background.
    static let surface = MirrorTheme.hex(0x1C1830, 0xFFFFFF)
    static let controlBorder = MirrorTheme.hex(0x2A2545, 0xD9D0EE)
    static let divider = MirrorTheme.hex(0x221E3A, 0xE0D9F5)
    static let segmentDivider = MirrorTheme.hex(0x2A2545, 0xE8E2F6)
    /// Icon-button and chip ink (the boards' #4A4366 / light violet).
    static let controlInk = MirrorTheme.hex(0xC9BEF2, 0x4A4366)
    static let accentInk = MirrorTheme.hex(0xC9BEF2, 0x4B2FA8)

    /// Selected list row. The board is dark-only; the light values are derived from it.
    static let selectedRowFill = MirrorTheme.hex(0x2A2150, 0xE6DEFA)
    static let selectedRowBorder = MirrorTheme.hex(0x5B45B8, 0xB9A8F0)
    static let selectedRowInk = MirrorTheme.hex(0xC9BEF2, 0x5B45B8)

    /// The quoted sentence of a reflection, and the active state of a toolbar toggle.
    static let quoteHighlight = MirrorTheme.hex(0x2F2560, 0xEAE2FF)
    static let toggleActiveFill = MirrorTheme.hex(0x2F2560, 0xE3DBF7)

    /// Settings window: control outline and the selected tab's pill.
    static let settingsControlBorder = MirrorTheme.hex(0x2A2545, 0xD0C6EC)
    static let tabSelectedFill = MirrorTheme.hex(0x2F2560, 0xDAD0F3)

    /// Quick capture popover: its outline, the text field and the footer strip.
    static let popoverBorder = MirrorTheme.hex(0x3A3360, 0xD9D0EE)
    static let quickField = MirrorTheme.hex(0x110E1C, 0xF8F5FF)
    static let quickFooter = MirrorTheme.hex(0x17132B, 0xF0EBFA)

    static let sidebarWidth: CGFloat = 232
    static let chromeHeight: CGFloat = 52
}

/// One of the board's line icons (vector assets in `MacIcons`), tinted with the current color.
struct MacIcon: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        Image("mac-\(name)")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// Pointer feedback without changing the size or selected state of a control.
struct MacHoverButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(label: configuration.label, pressed: configuration.isPressed, enabled: isEnabled)
    }

    private struct HoverLabel: View {
        let label: ButtonStyleConfiguration.Label
        let pressed: Bool
        let enabled: Bool
        @State private var hovered = false

        var body: some View {
            label
                .background(MacTokens.controlInk.opacity(enabled ? (pressed ? 0.16 : hovered ? 0.08 : 0) : 0),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Destinations

/// Every place the sidebar can go. The sidebar lists them in this order.
enum MacDestination: String, CaseIterable, Hashable {
    case write, entries
    case today, digest, report, mood, ask, brain

    var title: LocalizedStringKey {
        switch self {
        case .write: return "Write"
        case .entries: return "Entries"
        case .today: return "Today"
        case .digest: return "Weekly digest"
        case .report: return "Monthly report"
        case .mood: return "Mood timeline"
        case .ask: return "Ask"
        case .brain: return "Brain View"
        }
    }

    /// The window's title, by page.
    var windowTitle: String {
        switch self {
        case .write: return String(localized: "Write")
        case .entries: return String(localized: "Entries")
        case .today: return String(localized: "Today")
        case .digest: return String(localized: "Weekly digest")
        case .report: return String(localized: "Monthly report")
        case .mood: return String(localized: "Mood timeline")
        case .ask: return String(localized: "Ask")
        case .brain: return String(localized: "Brain View")
        }
    }

    var icon: String {
        switch self {
        case .write: return "pen"
        case .entries: return "book"
        case .today: return "sun"
        case .digest: return "doc"
        case .report: return "bars"
        case .mood: return "chart"
        case .ask: return "chat"
        case .brain: return "constellation"
        }
    }

    /// The plan that unlocks it, matching the subscription table.
    func isLocked(for tier: SubscriptionTier) -> Bool {
        switch self {
        case .write, .entries: return false
        case .today, .digest, .ask: return tier == .free
        case .report, .mood, .brain: return tier != .deep
        }
    }
}

// MARK: - Sidebar

struct MacSidebar: View {
    @Binding var selection: MacDestination
    @State private var subscription = SubscriptionService.shared
    /// This month's Ask answers, to show how many questions Core has left.
    @Query private var thisMonth: [Insight]

    init(selection: Binding<MacDestination>) {
        _selection = selection
        let month = DateHelpers.monthIdentifier(for: Date())
        _thisMonth = Query(filter: #Predicate<Insight> { $0.periodIdentifier == month })
    }

    private var asksLeft: Int? {
        guard subscription.tier == .core else { return nil }
        let used = thisMonth.filter { $0.type == .askResponse }.count
        return max(0, 15 - used)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: MacTokens.chromeHeight)   // room for the traffic lights

            VStack(spacing: 2) {
                row(.write)
                row(.entries)
            }

            Text("INSIGHTS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(MacTokens.secondaryInk)
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 6)

            VStack(spacing: 2) {
                row(.today)
                row(.digest)
                row(.report)
                row(.mood)
                row(.ask, trailing: asksLeft.map { String(localized: "\($0) left") })
                row(.brain)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                MacIcon(name: "lock", size: 14)
                Text("On-device. Nothing leaves this Mac.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(MacTokens.secondaryInk)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(MacTokens.sidebarBorder).frame(height: 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: MacTokens.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(MacTokens.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(MacTokens.sidebarBorder).frame(width: 1)
        }
    }

    private func row(_ destination: MacDestination, trailing: String? = nil) -> some View {
        let isSelected = selection == destination
        let locked = destination.isLocked(for: subscription.tier)
        return Button {
            selection = destination
        } label: {
            HStack(spacing: 9) {
                MacIcon(name: destination.icon)
                Text(destination.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTokens.secondaryInk)
                }
                if locked {
                    MacIcon(name: "lock", size: 13)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(isSelected ? Color.white : (locked ? MacTokens.secondaryInk : MacTokens.ink))
            .background(isSelected ? MacTokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(MacHoverButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(destination.title)
    }
}

// MARK: - Window

/// Makes the title bar transparent and full-size so the traffic lights sit on the sidebar,
/// and gives the window the board's background.
struct MacWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        // The scene uses the hidden title bar style, so the content runs under the traffic lights.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        positionTrafficLights(in: window)
        observeResizes(of: window)
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 8 / 255, green: 6 / 255, blue: 15 / 255, alpha: 1)
                : NSColor(srgbRed: 242 / 255, green: 238 / 255, blue: 248 / 255, alpha: 1)
        }
    }
}

extension MacWindowConfigurator {
    private static var observedWindows = Set<ObjectIdentifier>()

    /// AppKit moves the buttons back on resize and full screen; put them where the design has them.
    fileprivate static func observeResizes(of window: NSWindow) {
        guard observedWindows.insert(ObjectIdentifier(window)).inserted else { return }
        let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                          NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                                          NSWindow.didBecomeKeyNotification]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                if let window { positionTrafficLights(in: window) }
            }
        }
    }

    /// The board centers the traffic lights on the sidebar's 52 pt top row, 16 pt from the left.
    static func positionTrafficLights(in window: NSWindow, rowHeight: CGFloat = MacTokens.chromeHeight) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview else { return }
        let spacing = mini.frame.minX - close.frame.minX
        // The container is 28 pt tall and anchored to the window top; AppKit measures y from its
        // bottom, so a lower button needs a taller container.
        if container.frame.height < rowHeight {
            var frame = container.frame
            let grow = rowHeight - frame.height
            frame.size.height += grow
            frame.origin.y -= grow
            container.frame = frame
        }
        let y = (container.frame.height - close.frame.height) / 2
        for (index, button) in [close, mini, zoom].enumerated() {
            button.setFrameOrigin(NSPoint(x: 16 + CGFloat(index) * spacing, y: y))
        }
    }
}

// MARK: - Page title bar

/// The 52 pt bar every Mac screen carries: a title on the left, that screen's controls on the
/// right, and a hairline under it. The traffic lights sit on the sidebar, not here.
struct MacPageBar<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTokens.ink)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(height: MacTokens.chromeHeight)
        .background(MacTokens.windowBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(MacTokens.divider).frame(height: 1) }
    }
}

/// An icon button in the bar that shows an "on" state (the Today inspector toggle).
struct MacBarToggle: View {
    let icon: String
    let isOn: Bool
    let label: LocalizedStringKey
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MacIcon(name: icon, size: 17)
                .frame(width: 34, height: 28)
                .background(isOn ? MacTokens.toggleActiveFill : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(MacHoverButtonStyle())
        .foregroundStyle(isOn ? MacTokens.accentInk : MacTokens.controlInk)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(label)
        .help(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct MacPageModifier<Trailing: View>: ViewModifier {
    let title: LocalizedStringKey
    let dark: Bool
    let selectable: Bool
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            MacPageBar(title: title, trailing: trailing)
                .environment(\.colorScheme, dark ? .dark : scheme)
            Group {
                if selectable {
                    content.textSelection(.enabled)
                } else {
                    content
                }
            }
            .modifier(MacNoScrollEdgeEffect())
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }
    }
}

extension View {
    /// Puts the screen under the shared title bar. `dark` is for screens drawn on an always-dark
    /// canvas (Brain View), where the bar must match it.
    func macPage<Trailing: View>(_ title: LocalizedStringKey, dark: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) -> some View {
        modifier(MacPageModifier(title: title, dark: dark, selectable: !dark, trailing: trailing))
    }
}

/// Sidebar plus the screen it selects.
struct MacRootView<Detail: View>: View {
    @Binding var selection: MacDestination
    @Binding var sidebarVisible: Bool
    @ViewBuilder var detail: () -> Detail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                MacSidebar(selection: $selection)
                    .transition(.move(edge: .leading))
            }
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacTokens.windowBackground)
        }
        .background(MacTokens.windowBackground)
        .background(MacWindowConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: sidebarVisible)
    }
}
#endif
