import SwiftUI
import UIKit

/// The user's chosen font family for entry body text — applies everywhere an
/// entry's body/checklist/list text renders: the Write editor, the entry list
/// preview, and the entry detail/read view. A single global preference, not
/// per-entry, so switching it re-styles every entry consistently.
enum WritingFontChoice: String, CaseIterable, Identifiable {
    case system, serif, rounded, monospaced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Default"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        case .monospaced: return "Monospaced"
        }
    }

    var uiDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    var swiftUIDesign: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }

    static let storageKey = "mirrorWritingFontChoice"

    /// Reads the current choice from UserDefaults directly — for call sites that
    /// can't hold an @AppStorage binding (the UIKit editor's Coordinator, and
    /// plain SwiftUI View structs that read it once per render rather than
    /// observing it, since it changes rarely and every render path re-reads fresh).
    static var current: WritingFontChoice {
        WritingFontChoice(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .serif
    }
}
