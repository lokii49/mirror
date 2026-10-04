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
            ? ["Ember", "Amber", "Ash", "Rust", "Dusk violet"]
            : ["Pink", "Purple", "Orange", "Mint", "Blue"]
        guard names.indices.contains(index) else { return "Highlight" }
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
            ? ["Ember", "Amber", "Ash", "Rust", "Dusk violet"]
            : ["Red", "Orange", "Green", "Blue", "Purple"]
        guard names.indices.contains(index) else { return "Text color" }
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
}

struct FormattingPanelView: View {
    var state: FormattingPanelState
    /// iPhone: shown as an overlay above the keyboard — keep the grabber and let
    /// the rows scroll on short screens. iPad: shown in a `.popover`, which
    /// supplies its own chrome and sizes to content.
    var presentation: Presentation = .sheet
    /// The header's close button (iPhone, where the panel replaces the keyboard). None in a popover.
    var onClose: (() -> Void)? = nil
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor }
    private var idleFill: Color { displayMode == .sentinel ? MirrorTheme.inkMid : MirrorTheme.inkRaised }
    private var cornerRadius: CGFloat { displayMode == .sentinel ? 6 : 10 }
    /// Shared Dynamic Type scale factor (audit 2.5) — every fixed point size and
    /// button dimension below is `base * typeScale` instead of a bare literal, so
    /// the panel respects accessibility text sizes the way the editor itself does
    /// (`NoteEditorTextView` sets `adjustsFontForContentSizeCategory = true`).
    /// One shared `@ScaledMetric` base of 1.0 keeps every row's relative
    /// proportions (Title 22pt vs. Code 13pt, etc.) intact while scaling as a
    /// group — the officially recommended pattern for a cluster of custom point
    /// sizes that should move together rather than each having its own metric.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1.0

    enum Presentation { case sheet, popover }

    var body: some View {
        Group {
            if presentation == .sheet {
                ScrollView { panelRows }
            } else {
                panelRows
            }
        }
        .frame(maxWidth: .infinity)
        .background(displayMode == .sentinel ? MirrorTheme.inkRaised : MirrorTheme.inkBase)
        .overlay(alignment: .top) {
            if displayMode == .sentinel {
                Rectangle().fill(MirrorTheme.ember.opacity(0.22)).frame(height: 1)
            }
        }
    }

    /// Laid out like the Format sheet in Notes on iPhone: a "Format" header (font menu, close), the
    /// paragraph styles as chips, then segmented capsules for B / I / U / S + link / clear and for the
    /// list types + indent, then colour dots. Every control still sends the same command.
    private var panelRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Paragraph styles, each label in its own style.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    paragraphStyleButton("Title",      style: .title,      labelFont: .system(size: 20 * typeScale, weight: .bold))
                    paragraphStyleButton("Heading",    style: .heading,    labelFont: .system(size: 17 * typeScale, weight: .bold))
                    paragraphStyleButton("Subheading", style: .subheading, labelFont: .system(size: 15 * typeScale, weight: .semibold))
                    paragraphStyleButton("Body",       style: .body,       labelFont: .system(size: 15 * typeScale, weight: .regular))
                    paragraphStyleButton("Code",       style: .monospaced, labelFont: .system(size: 14 * typeScale, design: .monospaced))
                    paragraphStyleButton("Quote",      style: .blockQuote, labelFont: .system(size: 15 * typeScale, weight: .regular).italic())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }

            // B / I / U / S, then link / clear. Scrolls at large Dynamic Type sizes (audit 2.5).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    segmented {
                        inlineButton("B", style: .bold,          font: .system(size: 17 * typeScale, weight: .bold),       accessibilityLabel: "Bold")
                        segmentDivider
                        inlineButton("I", style: .italic,        font: .system(size: 17 * typeScale).italic(),             accessibilityLabel: "Italic")
                        segmentDivider
                        inlineButton("U", style: .underline,     font: .system(size: 17 * typeScale), underline: true,     accessibilityLabel: "Underline")
                        segmentDivider
                        inlineButton("S", style: .strikethrough, font: .system(size: 17 * typeScale), strikethrough: true, accessibilityLabel: "Strikethrough")
                    }
                    segmented {
                        linkButton
                        segmentDivider
                        clearFormattingButton
                    }
                }
                .padding(.horizontal, 16)
            }

            // List types (scrolling) + indent, pinned so it can't be pushed off-screen (audit 2.5).
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    segmented {
                        listButton(icon: "list.bullet", command: .bulletedList, accessibilityLabel: "Bulleted list")
                        segmentDivider
                        listButton(icon: "list.dash",   command: .dashedList,   accessibilityLabel: "Dashed list")
                        segmentDivider
                        listButton(icon: "list.number", command: .numberedList, accessibilityLabel: "Numbered list")
                        segmentDivider
                        listButton(icon: "checklist",   command: .checklist,    accessibilityLabel: "Checklist")
                    }
                }
                segmented {
                    listButton(icon: "decrease.indent", command: .indentLess, accessibilityLabel: "Decrease indent", scaleFrame: false)
                    segmentDivider
                    listButton(icon: "increase.indent", command: .indentMore, accessibilityLabel: "Increase indent", scaleFrame: false)
                }
            }
            .padding(.horizontal, 16)

            // Checklist bulk ops — only when the cursor is on a checklist line.
            if state.activeParagraphStyle == .checklistUnchecked || state.activeParagraphStyle == .checklistChecked {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        bulkChecklistButton("Check All",   command: .checkAllItems)
                        bulkChecklistButton("Uncheck All", command: .uncheckAllItems)
                        bulkChecklistButton("Delete Done", command: .deleteCheckedItems)
                        bulkChecklistButton("Sort Done",   command: .sortCheckedToBottom)
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Highlight and text colours share one scrolling row (a second row would push the panel past
            // its fixed 360pt input-view budget: FormattingPanelSizingTests).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        DispatchQueue.main.async { state.onCommand?(.highlight(index: nil)) }
                    } label: {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 20 * typeScale))
                            .foregroundStyle(state.activeHighlightIndex == nil ? accent : Color.secondary)
                            .frame(width: 34 * typeScale, height: 34 * typeScale)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("xmark")
                    .accessibilityLabel("No highlight")
                    .accessibilityAddTraits(state.activeHighlightIndex == nil ? .isSelected : [])

                    ForEach(0..<HighlightPalette.colors(for: displayMode).count, id: \.self) { idx in
                        highlightButton(index: idx)
                    }

                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 26 * typeScale)
                        .padding(.horizontal, 2)

                    Button {
                        DispatchQueue.main.async { state.onCommand?(.textColor(index: nil)) }
                    } label: {
                        Text("A")
                            .font(.system(size: 17 * typeScale, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 34 * typeScale, height: 34 * typeScale)
                            .background(Circle().fill(idleFill))
                            .overlay(Circle().stroke(state.activeTextColorIndex == nil ? accent : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Default text color")
                    .accessibilityAddTraits(state.activeTextColorIndex == nil ? .isSelected : [])

                    ForEach(0..<TextColorPalette.colors(for: displayMode).count, id: \.self) { idx in
                        textColorButton(index: idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }

            Spacer(minLength: 4)
        }
        .padding(.top, presentation == .sheet ? 12 : 10)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if displayMode == .sentinel {
                    Text("FORMAT").font(MirrorTheme.mono(13 * typeScale, weight: .bold)).tracking(1.2)
                } else {
                    Text("Format").font(.system(size: 17 * typeScale, weight: .bold))
                }
            }
            .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            fontMenu
            if presentation == .sheet, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13 * typeScale, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 30 * typeScale, height: 30 * typeScale)
                        .background(Circle().fill(idleFill))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("closeFormatPanel")
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 16)
    }

    /// Font family for this entry's body text (Write, entry list preview, entry detail).
    private var fontMenu: some View {
        Menu {
            ForEach(WritingFontChoice.allCases) { choice in
                Button {
                    DispatchQueue.main.async { state.onCommand?(.fontFamily(choice)) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if choice == state.activeFontChoice {
                        Label(choice.label, systemImage: "checkmark")
                    } else {
                        Text(choice.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(state.activeFontChoice.label)
                    .font(.system(size: 14 * typeScale, weight: .medium, design: state.activeFontChoice.swiftUIDesign))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10 * typeScale, weight: .semibold))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30 * typeScale)
            .background(Capsule().fill(idleFill))
        }
        .accessibilityIdentifier("fontMenu")
        .accessibilityLabel("Font")
    }

    // MARK: - Segmented capsule

    /// A rounded group of buttons with hairline dividers, like the segments in Notes' Format sheet.
    private func segmented<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .background(groupShape.fill(idleFill))
            .clipShape(groupShape)
    }

    private var groupShape: AnyShape {
        displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var segmentDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 22 * typeScale)
    }

    // MARK: - Paragraph style chip

    @ViewBuilder
    private func paragraphStyleButton(_ label: LocalizedStringKey, style: NoteParagraphTextStyle, labelFont: Font) -> some View {
        let isActive = state.activeParagraphStyle == style
        Button {
            let cmd = paragraphCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
            Text(label)
                .font(labelFont)
                .lineLimit(1)
                .foregroundStyle(isActive ? accent : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 42 * typeScale)
                .background(isActive ? accent.opacity(0.16) : Color.clear, in: chipShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var chipShape: AnyShape {
        displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 6)) : AnyShape(Capsule())
    }

    // MARK: - Segment cells

    /// One cell inside a `segmented` group: tinted when active.
    private func cell<Label: View>(isActive: Bool, width: CGFloat, height: CGFloat, @ViewBuilder _ label: () -> Label) -> some View {
        label()
            .foregroundStyle(isActive ? accent : Color.primary)
            .frame(width: width, height: height)
            .background(isActive ? accent.opacity(0.16) : Color.clear)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func inlineButton(_ label: String, style: InlineTextStyle, font: Font, underline: Bool = false, strikethrough: Bool = false, accessibilityLabel: String) -> some View {
        let isActive = state.activeInlineStyles.contains(style)
        Button {
            let cmd = inlineCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
            cell(isActive: isActive, width: 48 * typeScale, height: 42 * typeScale) {
                Group {
                    if strikethrough {
                        Text(label).strikethrough(true, color: isActive ? accent : Color.primary)
                    } else if underline {
                        Text(label).underline(true, color: isActive ? accent : Color.primary)
                    } else {
                        Text(label)
                    }
                }
                .font(font)
            }
        }
        .buttonStyle(.plain)
        // Identifier keeps the plain glyph ("B") so existing lookups still find it; the label carries
        // the VoiceOver name (audit 3.1).
        .accessibilityIdentifier(label)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var linkButton: some View {
        let isActive = state.activeLinkURL != nil
        return Button {
            DispatchQueue.main.async { state.onRequestLinkEditor?() }
        } label: {
            cell(isActive: isActive, width: 48 * typeScale, height: 42 * typeScale) {
                Image(systemName: "link").font(.system(size: 16 * typeScale))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("link")
        .accessibilityLabel(isActive ? "Edit link" : "Add link")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var clearFormattingButton: some View {
        Button {
            DispatchQueue.main.async { state.onCommand?(.clearFormatting) }
        } label: {
            cell(isActive: false, width: 48 * typeScale, height: 42 * typeScale) {
                Image(systemName: "eraser").font(.system(size: 16 * typeScale))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clearFormatting")
        .accessibilityLabel("Clear formatting")
    }

    @ViewBuilder
    private func listButton(icon: String, command: NoteTextCommand, accessibilityLabel: String, scaleFrame: Bool = true) -> some View {
        let isActive = listIsActive(command: command)
        // The indent pair keeps a fixed frame so two growing buttons can't eat an iPhone SE row at large
        // Dynamic Type sizes; its glyph still scales, capped inside the box (audit 2.5).
        let frameScale = scaleFrame ? typeScale : 1
        let iconSize = scaleFrame ? 17 * typeScale : min(17 * typeScale, 22)
        Button {
            DispatchQueue.main.async { state.onCommand?(command) }
        } label: {
            cell(isActive: isActive, width: 48 * frameScale, height: 42 * frameScale) {
                Image(systemName: icon).font(.system(size: iconSize))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(icon)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Bulk checklist button

    @ViewBuilder
    private func bulkChecklistButton(_ label: LocalizedStringKey, command: NoteTextCommand) -> some View {
        Button {
            DispatchQueue.main.async { state.onCommand?(command) }
        } label: {
            Group {
                if displayMode == .sentinel {
                    Text(label).font(MirrorTheme.mono(11 * typeScale, weight: .medium)).textCase(.uppercase)
                } else {
                    Text(label).font(.system(size: 13 * typeScale, weight: .medium))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 32 * typeScale)
            .background(idleFill, in: chipShape)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colour dots

    @ViewBuilder
    private func highlightButton(index: Int) -> some View {
        let isActive = state.activeHighlightIndex == index
        Button {
            let newIndex = isActive ? nil : index
            DispatchQueue.main.async { state.onCommand?(.highlight(index: newIndex)) }
        } label: {
            Circle()
                .fill(HighlightPalette.colors(for: displayMode)[index])
                .frame(width: 30 * typeScale, height: 30 * typeScale)
                .padding(2)
                .overlay(Circle().stroke(isActive ? accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HighlightPalette.name(for: index, displayMode: displayMode))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func textColorButton(index: Int) -> some View {
        let isActive = state.activeTextColorIndex == index
        let color = TextColorPalette.colors(for: displayMode)[index]
        return Button {
            let newIndex = isActive ? nil : index
            DispatchQueue.main.async { state.onCommand?(.textColor(index: newIndex)) }
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30 * typeScale, height: 30 * typeScale)
                .padding(2)
                .overlay(Circle().stroke(isActive ? accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TextColorPalette.name(for: index, displayMode: displayMode))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Helpers

    private func listIsActive(command: NoteTextCommand) -> Bool {
        switch command {
        case .bulletedList: return state.activeParagraphStyle == .bulletedList
        case .dashedList:   return state.activeParagraphStyle == .dashedList
        case .numberedList: return state.activeParagraphStyle == .numberedList
        case .checklist:
            return state.activeParagraphStyle == .checklistUnchecked
                || state.activeParagraphStyle == .checklistChecked
        default: return false
        }
    }

    private func paragraphCommand(for style: NoteParagraphTextStyle) -> NoteTextCommand {
        switch style {
        case .title:      return .title
        case .heading:    return .heading
        case .subheading: return .subheading
        case .body:       return .body
        case .monospaced: return .monospaced
        case .blockQuote: return .blockQuote
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
