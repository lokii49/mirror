import SwiftUI
import UIKit

/// The font family for an entry's body text — stored per-entry (Entry.fontChoice),
/// not globally, so changing the font for one entry doesn't affect any other.
/// Applies everywhere that entry's body/checklist/list text renders: the Write
/// editor, the entry list preview, and the entry detail/read view.
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

}
