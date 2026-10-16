import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Highlight swatches for the formatting panel and the editor's rendered
/// highlight attribute. Each entry is a light/dark-adaptive `Color`
/// (`MirrorTheme.hex`) — the original set was fixed light-mode RGB literals
/// with no dark counterpart, so highlighted text read washed-out / low
/// contrast in dark mode, and there was no Sentinel variant at all (audit 3.2).
enum HighlightPalette {
    static func colors(for displayMode: DisplayMode) -> [Color] {
        displayMode == .sentinel ? sentinel : classic
    }

    /// VoiceOver label for swatch `index` — the swatches carry no visible
    /// text, so without this every one reads as just "button" (audit 3.1).
    static func name(for index: Int, displayMode: DisplayMode) -> String {
        let names = displayMode == .sentinel
            ? [String(localized: "Ember"), String(localized: "Amber"), String(localized: "Ash"), String(localized: "Rust"), String(localized: "Dusk violet")]
            : [String(localized: "Pink"), String(localized: "Purple"), String(localized: "Orange"), String(localized: "Mint"), String(localized: "Blue")]
        guard names.indices.contains(index) else { return String(localized: "Highlight") }
        return names[index]
    }

    /// Same 5 hues as the original light pastels, each paired with a
    /// deepened dark-mode counterpart.
    private static let classic: [Color] = [
        MirrorTheme.hex(0x5C2430, 0xFFBFCC),   // pink / rose
        MirrorTheme.hex(0x3B2A66, 0xD1BFFF),   // purple
        MirrorTheme.hex(0x5C441A, 0xFFD699),   // orange / yellow
        MirrorTheme.hex(0x1F4D3B, 0xB3F2D9),   // mint
        MirrorTheme.hex(0x1F3D5C, 0xADD9FF),   // blue
    ]

    /// Previously fell back to the Classic pastels, clashing with the
    /// mono/ember language everything else in the panel branches for.
    /// Stays in-family (ember + warm neutrals).
    private static let sentinel: [Color] = [
        MirrorTheme.ember,
        MirrorTheme.hex(0xE0A050, 0xC47A20),   // amber
        MirrorTheme.hex(0x8A8398, 0x6B6478),   // ash
        MirrorTheme.hex(0xC06248, 0x9E4530),   // rust
        MirrorTheme.hex(0x8A6FD1, 0x6B4FB0),   // dusk violet
    ]
}

/// Foreground text colors for the Aa panel's Text Color row and the editor's
/// rendered `.foregroundColor` attribute. Same light/dark-adaptive shape as
/// `HighlightPalette` but tuned as legible foreground ink rather than a
/// background wash — a highlight's pastel would fail contrast as text color.
enum TextColorPalette {
    static func colors(for displayMode: DisplayMode) -> [Color] {
        displayMode == .sentinel ? sentinel : classic
    }

    static func name(for index: Int, displayMode: DisplayMode) -> String {
        let names = displayMode == .sentinel
            ? [String(localized: "Ember"), String(localized: "Amber"), String(localized: "Ash"), String(localized: "Rust"), String(localized: "Dusk violet")]
            : [String(localized: "Red"), String(localized: "Orange"), String(localized: "Green"), String(localized: "Blue"), String(localized: "Purple")]
        guard names.indices.contains(index) else { return String(localized: "Text color") }
        return names[index]
    }

    private static let classic: [Color] = [
        MirrorTheme.hex(0xC0392B, 0xFF6B5B),   // red
        MirrorTheme.hex(0xB8631A, 0xFFA94D),   // orange
        MirrorTheme.hex(0x1F7A4D, 0x5FE0A0),   // green
        MirrorTheme.hex(0x1F5FA8, 0x6FB8FF),   // blue
        MirrorTheme.hex(0x6A3FA0, 0xC79BFF),   // purple
    ]

    private static let sentinel: [Color] = [
        MirrorTheme.ember,
        MirrorTheme.hex(0xE0A050, 0xC47A20),   // amber
        MirrorTheme.hex(0x8A8398, 0x6B6478),   // ash
        MirrorTheme.hex(0xC06248, 0x9E4530),   // rust
        MirrorTheme.hex(0x8A6FD1, 0x6B4FB0),   // dusk violet
    ]
}

@Observable final class FormattingPanelState {
    var activeParagraphStyle: NoteParagraphTextStyle = .body
    var activeInlineStyles = InlineStyleSet()
    var activeHighlightIndex: Int? = nil
    var activeTextColorIndex: Int? = nil
    /// The font family the *current paragraph/selection* is using — drives the
    /// font row's highlight, same role activeParagraphStyle plays for block style.
    var activeFontChoice: WritingFontChoice = .system
    /// Non-nil when the cursor sits inside an existing link — drives the Link
    /// button's active state and prefills the URL editor for editing it.
    var activeLinkURL: String? = nil
    var onCommand: ((NoteTextCommand) -> Void)?
    /// Tapping Link needs a URL from the user before a command can be dispatched
    /// — the panel can't own that alert (it doesn't know the current selection),
    /// so it hands off to whoever presents it (WriteView) instead of calling
    /// onCommand directly.
    var onRequestLinkEditor: (() -> Void)?
    /// The swatch the highlighter pen applies; the color dot picks it, as in Notes.
    var lastHighlightIndex = 0
    /// A checklist item was just checked by a tap on its circle (or VoiceOver's action), so
    /// WriteView can ask about, or apply, automatic sorting.
    var onChecklistItemChecked: (() -> Void)?
}


#if os(iOS)
/// The Aa panel, laid out like Apple Notes' Format panel: a "Format" header with a round close
/// button, one sideways row of paragraph styles (each label in its own style, the active one on a
/// filled pill), then two rows of capsule groups: B / I / U / S with the highlighter and the color
/// dot, and the list types, indent and quote. The color dot swaps those two rows for the
/// highlight and text color swatches. Checklist, link, clear formatting and font live in the
/// keyboard bar. On iPhone the panel is a floating card that replaces the keyboard; on iPad it
/// fills a popover, which supplies its own chrome.
struct FormattingPanelView: View {
    var state: FormattingPanelState
    var presentation: Presentation = .sheet
    /// The header's close button (iPhone, where the panel replaces the keyboard). None in a popover.
    var onClose: (() -> Void)? = nil
    @Environment(\.appDisplayMode) private var displayMode
    @State private var showingColors = false
    /// Every point size and row height below is `base * typeScale`, so the panel follows Dynamic
    /// Type as one group (audit 2.5).
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1.0

    enum Presentation { case sheet, popover }

    /// The tallest the iPhone card gets before its content scrolls (large Dynamic Type sizes).
    static let maximumInputHeight: CGFloat = 420

    private var isSentinel: Bool { displayMode == .sentinel }
    private var accent: Color { isSentinel ? MirrorTheme.ember : Color.accentColor }
    private var groupFill: Color { isSentinel ? MirrorTheme.inkMid : Color(.tertiarySystemFill) }
    private var rowHeight: CGFloat { min(44 * typeScale, 72) }
    private var groupGap: CGFloat { 12 }

    var body: some View {
        if presentation == .sheet {
            // Fills the input view edge to edge: the keyboard's backdrop sits behind it, and an
            // inset card left that backdrop showing as a grey frame.
            ScrollView { panelContent }
                .scrollBounceBehavior(.basedOnSize)
                .panelCard(isSentinel: isSentinel)
        } else {
            panelContent
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, presentation == .sheet ? 16 : 18)
            paragraphStyleRow
                .padding(.top, 10)
            Group {
                if showingColors {
                    colorRows
                } else {
                    formatRows
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, presentation == .sheet ? 34 : 18)
        }
        .animation(.easeInOut(duration: 0.2), value: showingColors)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if showingColors {
                Button {
                    showingColors = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 17 * typeScale, weight: .semibold))
                        titleText("Colors")
                    }
                    .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("colorsBack")
            } else {
                titleText("Format")
            }
            Spacer(minLength: 8)
            if presentation == .sheet, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17 * typeScale, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44 * typeScale, height: 44 * typeScale)
                        .closeButtonSurface(isSentinel: isSentinel)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("closeFormatPanel")
                .accessibilityLabel("Close")
            }
        }
    }

    @ViewBuilder
    private func titleText(_ key: LocalizedStringKey) -> some View {
        Group {
            if isSentinel {
                Text(key).font(MirrorTheme.mono(17 * typeScale, weight: .bold)).textCase(.uppercase).tracking(1.2)
            } else {
                Text(key).font(.system(size: 22 * typeScale, weight: .bold))
            }
        }
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    // MARK: - Paragraph styles

    private var paragraphStyleRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                paragraphStyleButton("Title",      style: .title,      font: .system(size: 26 * typeScale, weight: .bold))
                paragraphStyleButton("Heading",    style: .heading,    font: .system(size: 21 * typeScale, weight: .bold))
                paragraphStyleButton("Subheading", style: .subheading, font: .system(size: 17 * typeScale, weight: .semibold))
                paragraphStyleButton("Body",       style: .body,       font: .system(size: 17 * typeScale))
                paragraphStyleButton("Code",       style: .monospaced, font: .system(size: 15 * typeScale, design: .monospaced))
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
    }

    private func paragraphStyleButton(_ label: LocalizedStringKey, style: NoteParagraphTextStyle, font: Font) -> some View {
        let isActive = state.activeParagraphStyle == style
        return Button {
            let cmd = paragraphCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
            Text(label)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isActive ? (isSentinel ? MirrorTheme.inkBase : Color.white) : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: rowHeight)
                .background {
                    if isActive { Capsule().fill(accent) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Format rows

    /// Every cell in both rows has the same width, as in Notes: six cells per row, with one gap
    /// between groups in the first row and two in the second.
    private var formatRows: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - 2 * groupGap) / 6
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: groupGap) {
                    group {
                        inlineButton("B", style: .bold, font: .system(size: 19 * typeScale, weight: .bold), accessibilityLabel: "Bold")
                        divider
                        inlineButton("I", style: .italic, font: .system(size: 19 * typeScale).italic(), accessibilityLabel: "Italic")
                        divider
                        inlineButton("U", style: .underline, font: .system(size: 19 * typeScale), underline: true, accessibilityLabel: "Underline")
                        divider
                        inlineButton("S", style: .strikethrough, font: .system(size: 19 * typeScale), strikethrough: true, accessibilityLabel: "Strikethrough")
                    }
                    .frame(width: cell * 4 + groupGap / 2)
                    group {
                        highlighterButton
                        divider
                        colorDotButton
                    }
                    .frame(width: cell * 2 + groupGap / 2)
                }
                HStack(spacing: groupGap) {
                    group {
                        iconButton("list.bullet", command: .bulletedList, identifier: "list.bullet", label: "Bulleted list")
                        divider
                        iconButton("list.dash", command: .dashedList, identifier: "list.dash", label: "Dashed list")
                        divider
                        iconButton("list.number", command: .numberedList, identifier: "list.number", label: "Numbered list")
                    }
                    .frame(width: cell * 3)
                    group {
                        iconButton("decrease.indent", command: .indentLess, identifier: "decrease.indent", label: "Decrease indent")
                        divider
                        iconButton("increase.indent", command: .indentMore, identifier: "increase.indent", label: "Increase indent")
                    }
                    .frame(width: cell * 2)
                    group {
                        iconButton("text.quote", command: .blockQuote, identifier: "blockQuote", label: "Quote")
                    }
                    .frame(width: cell)
                }
            }
        }
        .frame(height: rowHeight * 2 + 10)
    }

    /// Equal cells in one capsule with hairline dividers.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .frame(height: rowHeight)
            .background(groupShape.fill(groupFill))
            .clipShape(groupShape)
    }

    private var groupShape: AnyShape {
        isSentinel ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(Capsule())
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: rowHeight)
    }

    private func cell<Label: View>(isActive: Bool, @ViewBuilder _ label: () -> Label) -> some View {
        label()
            .foregroundStyle(isActive ? accent : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .background(isActive ? accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
    }

    private func inlineButton(_ label: String, style: InlineTextStyle, font: Font, underline: Bool = false, strikethrough: Bool = false, accessibilityLabel: String) -> some View {
        let isActive = state.activeInlineStyles.contains(style)
        return Button {
            let cmd = inlineCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
            cell(isActive: isActive) {
                Text(label)
                    .underline(underline)
                    .strikethrough(strikethrough)
                    .font(font)
            }
        }
        .buttonStyle(.plain)
        // The identifier keeps the plain glyph ("B") so existing lookups still find it; the label carries
        // the VoiceOver name (audit 3.1).
        .accessibilityIdentifier(label)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func iconButton(_ systemImage: String, command: NoteTextCommand, identifier: String, label: LocalizedStringKey) -> some View {
        let isActive = isActive(command)
        return Button {
            DispatchQueue.main.async { state.onCommand?(command) }
        } label: {
            cell(isActive: isActive) {
                Image(systemName: systemImage).font(.system(size: min(19 * typeScale, 30)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Highlights in the last-picked swatch; a second tap removes it.
    private var highlighterButton: some View {
        let isActive = state.activeHighlightIndex != nil
        return Button {
            let index = isActive ? nil : state.lastHighlightIndex
            DispatchQueue.main.async { state.onCommand?(.highlight(index: index)) }
        } label: {
            cell(isActive: isActive) {
                Image(systemName: "highlighter").font(.system(size: min(19 * typeScale, 30)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("highlighter")
        .accessibilityLabel("Highlight")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Shows the highlight color the pen applies; opens the swatches.
    private var colorDotButton: some View {
        let palette = HighlightPalette.colors(for: displayMode)
        let dot = palette.indices.contains(state.lastHighlightIndex) ? palette[state.lastHighlightIndex] : accent
        return Button {
            showingColors = true
        } label: {
            cell(isActive: false) {
                Circle()
                    .fill(dot)
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .frame(width: min(24 * typeScale, 36), height: min(24 * typeScale, 36))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("colorPicker")
        .accessibilityLabel("Colors")
    }

    // MARK: - Colors

    private var colorRows: some View {
        VStack(spacing: 10) {
            swatchRow {
                noneSwatch(isActive: state.activeHighlightIndex == nil, accessibilityLabel: "No highlight") {
                    state.onCommand?(.highlight(index: nil))
                } label: {
                    Image(systemName: "nosign").font(.system(size: 15 * typeScale, weight: .medium))
                }
                .accessibilityIdentifier("xmark")
                ForEach(0..<HighlightPalette.colors(for: displayMode).count, id: \.self) { idx in
                    highlightSwatch(index: idx)
                }
            }
            swatchRow {
                noneSwatch(isActive: state.activeTextColorIndex == nil, accessibilityLabel: "Default text color") {
                    state.onCommand?(.textColor(index: nil))
                } label: {
                    Text("A").font(.system(size: 15 * typeScale, weight: .bold))
                }
                ForEach(0..<TextColorPalette.colors(for: displayMode).count, id: \.self) { idx in
                    textColorSwatch(index: idx)
                }
            }
        }
    }

    private func swatchRow<Content: View>(@ViewBuilder _ swatches: () -> Content) -> some View {
        HStack(spacing: 0) { swatches() }
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
    }

    private var swatchSize: CGFloat { min(30 * typeScale, 40) }

    private func noneSwatch<Label: View>(isActive: Bool, accessibilityLabel: String, action: @escaping () -> Void,
                                         @ViewBuilder label: () -> Label) -> some View {
        Button {
            DispatchQueue.main.async { action() }
        } label: {
            label()
                .foregroundStyle(isActive ? accent : Color.primary)
                .frame(width: swatchSize, height: swatchSize)
                .background(Circle().fill(groupFill))
                .overlay(Circle().stroke(isActive ? accent : Color.clear, lineWidth: 2).padding(-3))
                .padding(3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// An "A" on the highlight color, so it previews the result and reads apart from the text color
    /// row (color behind the letter vs. in it).
    private func highlightSwatch(index: Int) -> some View {
        let isActive = state.activeHighlightIndex == index
        return Button {
            let newIndex = isActive ? nil : index
            if let newIndex { state.lastHighlightIndex = newIndex }
            DispatchQueue.main.async { state.onCommand?(.highlight(index: newIndex)) }
        } label: {
            Text("A")
                .font(.system(size: 15 * typeScale, weight: .heavy))
                .foregroundStyle(Color.primary)
                .frame(width: swatchSize, height: swatchSize)
                .background(Circle().fill(HighlightPalette.colors(for: displayMode)[index]))
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .overlay(Circle().stroke(isActive ? accent : Color.clear, lineWidth: 2).padding(-3))
                .padding(3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        // Both rows share color names, so the label says which row ("Purple, Highlight").
        .accessibilityLabel(Text(verbatim: HighlightPalette.name(for: index, displayMode: displayMode) + ", ") + Text("Highlight"))
        .accessibilityIdentifier("highlight-\(index)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// An "A" in the text color, so it previews the result.
    private func textColorSwatch(index: Int) -> some View {
        let isActive = state.activeTextColorIndex == index
        let color = TextColorPalette.colors(for: displayMode)[index]
        return Button {
            let newIndex = isActive ? nil : index
            DispatchQueue.main.async { state.onCommand?(.textColor(index: newIndex)) }
        } label: {
            Text("A")
                .font(.system(size: 15 * typeScale, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: swatchSize, height: swatchSize)
                .background(Circle().fill(groupFill))
                .overlay(Circle().stroke(isActive ? accent : Color.clear, lineWidth: 2).padding(-3))
                .padding(3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: TextColorPalette.name(for: index, displayMode: displayMode) + ", ") + Text("Text color"))
        .accessibilityIdentifier("textColor-\(index)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Helpers

    private func isActive(_ command: NoteTextCommand) -> Bool {
        switch command {
        case .bulletedList: return state.activeParagraphStyle == .bulletedList
        case .dashedList:   return state.activeParagraphStyle == .dashedList
        case .numberedList: return state.activeParagraphStyle == .numberedList
        case .blockQuote:   return state.activeParagraphStyle == .blockQuote
        default: return false
        }
    }

    private func paragraphCommand(for style: NoteParagraphTextStyle) -> NoteTextCommand {
        switch style {
        case .title:      return .title
        case .heading:    return .heading
        case .subheading: return .subheading
        case .monospaced: return .monospaced
        default:          return .body
        }
    }

    private func inlineCommand(for style: InlineTextStyle) -> NoteTextCommand {
        switch style {
        case .bold:          return .bold
        case .italic:        return .italic
        case .underline:     return .underline
        case .strikethrough: return .strikethrough
        }
    }
}

/// Notes' card is an opaque sheet: white in light mode, raised grey in dark.
private let panelCardFill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemBackground })

private extension View {
    /// The card that replaces the keyboard: an opaque sheet with a hairline top edge. Sentinel
    /// keeps its ink card with an ember hairline.
    @ViewBuilder
    func panelCard(isSentinel: Bool) -> some View {
        if isSentinel {
            self
                .background(MirrorTheme.inkRaised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MirrorTheme.ember.opacity(0.3), lineWidth: 1))
        } else {
            // Square-topped and full width. iOS draws a rectangular, translucent keyboard backdrop
            // behind any custom inputView, so rounded top corners left grey wedges of it showing
            // (owner screenshot, 2026-10-16). The bottom corners sit on the display's own.
            self
                .background(panelCardFill)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                }
        }
    }

    @ViewBuilder
    func closeButtonSurface(isSentinel: Bool) -> some View {
        if isSentinel {
            self.background(Circle().fill(MirrorTheme.inkMid))
        } else {
            self
                .background(Circle().fill(panelCardFill))
                .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 1)
        }
    }
}
#endif
