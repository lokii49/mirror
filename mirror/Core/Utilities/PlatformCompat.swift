import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Cross-platform shims so the shared SwiftUI code builds on native macOS.
// iOS builds use UIKit directly; on macOS the UIKit names map to their AppKit
// equivalents where the API shape matches, and the rest is stubbed below.

#if os(macOS)
import AppKit

typealias UIColor = NSColor
typealias UIFont = NSFont
typealias UIFontDescriptor = NSFontDescriptor
typealias UIImage = NSImage

extension NSImage {
    convenience init?(systemName name: String) {
        self.init(systemSymbolName: name, accessibilityDescription: nil)
    }

    private var bitmapRep: NSBitmapImageRep? {
        guard let tiff = tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        bitmapRep?.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
        bitmapRep?.representation(using: .png, properties: [:])
    }
}

/// UIApplication stand-in: only what the shared code calls on Mac.
struct UIBackgroundTaskIdentifier: Equatable {
    let rawValue: Int
    static let invalid = UIBackgroundTaskIdentifier(rawValue: 0)
}

final class UIApplication {
    static let shared = UIApplication()
    enum State { case active, inactive, background }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    /// Mac apps are not suspended while they run, so there is no background time to request.
    var applicationState: State { NSApp.isActive ? .active : .inactive }
    func beginBackgroundTask(withName name: String?, expirationHandler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier { .invalid }
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}

final class UIPasteboard {
    static let general = UIPasteboard()
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }
}

extension NSColor {
    static var tintColor: NSColor { .controlAccentColor }
    // UIKit semantic colors, mapped to their AppKit counterparts.
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemFill: NSColor { .quaternaryLabelColor }
    static var secondarySystemFill: NSColor { .tertiaryLabelColor }
    static var systemFill: NSColor { .quaternaryLabelColor }
}

extension NSFontDescriptor.SymbolicTraits {
    static let traitBold = NSFontDescriptor.SymbolicTraits.bold
    static let traitItalic = NSFontDescriptor.SymbolicTraits.italic
}

extension NSFont {
    func withTrait(_ trait: NSFontDescriptor.SymbolicTraits, add: Bool) -> NSFont {
        var traits = fontDescriptor.symbolicTraits
        if add { traits.insert(trait) } else { traits.remove(trait) }
        return NSFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
    }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

/// Keyboard notifications are iOS-only; on Mac they are never posted, so keyboard-avoidance code stays idle.
enum UIResponder {
    static let keyboardWillShowNotification = Notification.Name("mirror.mac.keyboardWillShow")
    static let keyboardWillHideNotification = Notification.Name("mirror.mac.keyboardWillHide")
    static let keyboardWillChangeFrameNotification = Notification.Name("mirror.mac.keyboardWillChangeFrame")
    static let keyboardFrameEndUserInfoKey = "mirror.mac.keyboardFrameEnd"
    static let keyboardAnimationDurationUserInfoKey = "mirror.mac.keyboardAnimationDuration"
}

// SwiftUI APIs that exist only on iOS. On Mac they degrade to the closest native behavior.
extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .automatic }
}

enum PlatformKeyboardType { case `default`, URL, emailAddress }
enum PlatformAutocapitalization { case never, words, sentences }

enum PlatformTitleDisplayMode { case automatic, inline, large }

extension View {
    func keyboardType(_ type: PlatformKeyboardType) -> some View { self }
    func textInputAutocapitalization(_ style: PlatformAutocapitalization?) -> some View { self }
    func navigationBarTitleDisplayMode(_ mode: PlatformTitleDisplayMode) -> some View { self }

    /// macOS has no full-screen cover; a sheet is the nearest presentation.
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }

    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
    }
}

// Haptics: Macs have no Taptic engine for apps, so the feedback generators are no-ops there.
// Call sites keep using the UIKit names unchanged.
final class UIImpactFeedbackGenerator {
    enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    init(style: FeedbackStyle) {}
    func prepare() {}
    func impactOccurred() {}
    func impactOccurred(intensity: CGFloat) {}
}

final class UINotificationFeedbackGenerator {
    enum FeedbackType { case success, warning, error }
    init() {}
    func prepare() {}
    func notificationOccurred(_ type: FeedbackType) {}
}

final class UISelectionFeedbackGenerator {
    init() {}
    func prepare() {}
    func selectionChanged() {}
}
#endif

/// Resigns the text-input focus (hides the keyboard on iOS).
@MainActor func dismissKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #else
    NSApp.keyWindow?.makeFirstResponder(nil)
    #endif
}

/// Presents the system share sheet for `items`.
@MainActor func presentShareSheet(items: [Any]) {
    #if os(iOS)
    let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.windows.first?.rootViewController?
        .present(av, animated: true)
    #else
    guard let view = NSApp.keyWindow?.contentView else { return }
    NSSharingServicePicker(items: items)
        .show(relativeTo: .zero, of: view, preferredEdge: .minY)
    #endif
}

extension Color {
    /// The system hairline/separator color on both platforms.
    static var platformSeparator: Color {
        #if os(iOS)
        Color(.separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}

extension View {
    /// A wheel date picker on iPhone/iPad; the standard field style on Mac.
    @ViewBuilder func platformWheelDatePicker() -> some View {
        #if os(iOS)
        datePickerStyle(.wheel)
        #else
        datePickerStyle(.field)
        #endif
    }
}
