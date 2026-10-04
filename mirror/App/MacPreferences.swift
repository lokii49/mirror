#if os(macOS)
import SwiftUI

/// Mac-only reading and writing preferences (Settings > Appearance). The editor, the reader and
/// new entries read them; they are not synced.
enum MacPrefs {
    static let fontKey = "macWritingFont"
    static let sizeKey = "macTextSize"
    static let widthKey = "macLineWidth"

    static let defaultSize = 18.0
    static let sizeRange: ClosedRange<Double> = 14...24

    /// Body text size in points.
    static var textSize: CGFloat {
        let stored = UserDefaults.standard.object(forKey: sizeKey) as? Double ?? defaultSize
        return CGFloat(min(max(stored, sizeRange.lowerBound), sizeRange.upperBound))
    }

    /// The font new entries start in. An entry keeps its own font once it is saved.
    static var writingFont: WritingFontChoice {
        WritingFontChoice(rawValue: UserDefaults.standard.string(forKey: fontKey) ?? "") ?? .serif
    }

    enum LineWidth: String, CaseIterable {
        case narrow, comfortable, wide

        /// The editor's text column, in points (the board's 680 is Comfortable).
        var column: CGFloat {
            switch self {
            case .narrow: return 560
            case .comfortable: return 680
            case .wide: return 840
            }
        }
        /// The reader sits in a narrower pane; it keeps the same 40 pt difference as before.
        var readerColumn: CGFloat { column - 40 }
    }

    static func lineWidth(_ raw: String) -> LineWidth { LineWidth(rawValue: raw) ?? .comfortable }
}
#endif
