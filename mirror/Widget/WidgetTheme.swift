import SwiftUI

// Shared by every widget in this folder. The widget extension is a separate
// target with no access to the app's `MirrorTheme`, so before this file each
// widget hand-copied the same handful of `Color(red:…)` literals and the same
// `widgetIsSentinel()` / `widget.tier` reads. Those are consolidated here.
//
// The values are the DARK variant of the matching `MirrorTheme` tokens, frozen
// as hex integers — widgets render dark chrome regardless of system appearance,
// so this deliberately does NOT use `MirrorTheme.hex(dark:light:)`'s adaptive
// `UIColor { trait in … }` form. `WidgetThemeTokenTests` asserts each value
// still matches its `MirrorTheme` counterpart so the two can't silently drift.
enum WidgetTheme {
    /// Non-adaptive hex → Color. No trait lookup: the widget palette is fixed-dark.
    static func hex(_ v: UInt32) -> Color {
        Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue:  Double(v & 0xFF) / 255
        )
    }

    static let bgTop        = hex(0x1C1830)  // MirrorTheme.inkRaised (dark)
    static let bgBottom      = hex(0x110E1C)  // MirrorTheme.inkMid (dark)
    static let violet        = hex(0x7C5CE4)  // MirrorTheme.violet (dark)
    static let violetLight    = hex(0xA78BFA)  // MirrorTheme.violetLight (dark)
    static let ember          = hex(0xF97B8B)  // MirrorTheme.ember (dark)

    /// Widget-only. No `MirrorTheme` counterpart — `inkBase` (dark) is #08060F,
    /// a near-black with a violet cast; Sentinel widgets want a flatter neutral.
    static let sentinelBg     = hex(0x0B0B0E)
}

// App-group access shared across widgets. Kept as free functions with the exact
// bodies the widgets used before, so this is a move, not a rewrite — callers
// still evaluate them at struct-init time (`private let sentinel = …`).
enum WidgetShared {
    static let appGroupID = "group.com.lokesh.mirror"

    static func isSentinel() -> Bool {
        UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.displayMode") == "sentinel"
    }

    /// "free" | "core" | "deep"
    static func tier() -> String {
        UserDefaults(suiteName: appGroupID)?.string(forKey: "widget.tier") ?? "free"
    }
}
