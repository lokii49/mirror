import SwiftUI
import UIKit

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

@Observable final class FormattingPanelState {
    var activeParagraphStyle: NoteParagraphTextStyle = .body
    var activeInlineStyles = InlineStyleSet()
    var activeHighlightIndex: Int? = nil
    /// The font family the *current paragraph/selection* is using — drives the
    /// font row's highlight, same role activeParagraphStyle plays for block style.
    var activeFontChoice: WritingFontChoice = .system
    var onCommand: ((NoteTextCommand) -> Void)?
}

struct FormattingPanelView: View {
    var state: FormattingPanelState
    /// iPhone: shown as an overlay above the keyboard — keep the grabber and let
    /// the rows scroll on short screens. iPad: shown in a `.popover`, which
    /// supplies its own chrome and sizes to content.
    var presentation: Presentation = .sheet
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : Color.accentColor }
    private var idleFill: Color { displayMode == .sentinel ? MirrorTheme.inkMid : Color(.tertiarySystemFill) }
    private var cornerRadius: CGFloat { displayMode == .sentinel ? 6 : 10 }
    /// Shared Dynamic Type scale factor (audit 2.5) — every fixed point size and
    /// button dimension below is `base * typeScale` instead of a bare literal, so
    /// the panel respects accessibility text sizes the way the editor itself does
    /// (`NoteEditorTextView` sets `adjustsFontForContentSizeCategory = true`).
    /// One shared `@ScaledMetric` base of 1.0 keeps every row's relative
    /// proportions (Title 22pt vs. Mono 13pt, etc.) intact while scaling as a
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
        .background(displayMode == .sentinel ? MirrorTheme.inkRaised : Color(.secondarySystemBackground))
        .overlay(alignment: .top) {
            if displayMode == .sentinel {
                Rectangle().fill(MirrorTheme.ember.opacity(0.22)).frame(height: 1)
            }
        }
    }

    private var panelRows: some View {
        VStack(alignment: .leading, spacing: 0) {

            if presentation == .sheet {
                // Handle bar (Apple Notes style — tap Aa again to dismiss)
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            } else {
                Spacer(minLength: 8)
            }

            // Row 0: Font family — applies everywhere this entry's body text
            // appears (Write, entry list preview, entry detail view).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WritingFontChoice.allCases) { choice in
                        fontChoiceButton(choice)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.bottom, 10)

            // Row 1: Paragraph styles — horizontal scroll, each in its own font
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    paragraphStyleButton("Title",      style: .title,      labelFont: .system(size: 22 * typeScale, weight: .black))
                    paragraphStyleButton("Heading",    style: .heading,    labelFont: .system(size: 18 * typeScale, weight: .bold))
                    paragraphStyleButton("Subheading", style: .subheading, labelFont: .system(size: 15 * typeScale, weight: .semibold))
                    paragraphStyleButton("Body",       style: .body,       labelFont: .system(size: 14 * typeScale, weight: .regular))
                    paragraphStyleButton("Mono",       style: .monospaced, labelFont: .system(size: 13 * typeScale, design: .monospaced))
                    paragraphStyleButton("Quote",      style: .blockQuote, labelFont: .system(size: 14 * typeScale, weight: .regular).italic())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }

            // Row 2: Inline styles (fixed-size square buttons). Horizontally
            // scrolling like rows 0/1 — at large Dynamic Type sizes four square
            // buttons plus spacing no longer fit an iPhone SE's width (audit 2.5).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    inlineButton("B",  style: .bold,          font: .system(size: 17 * typeScale, weight: .bold),          accessibilityLabel: "Bold")
                    inlineButton("I",  style: .italic,        font: .system(size: 17 * typeScale).italic(),                accessibilityLabel: "Italic")
                    inlineButton("U",  style: .underline,     font: .system(size: 17 * typeScale), underline: true,        accessibilityLabel: "Underline")
                    inlineButton("S",  style: .strikethrough, font: .system(size: 17 * typeScale), strikethrough: true,    accessibilityLabel: "Strikethrough")
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)

            // Row 3: List types (scrolling, same reasoning as row 2) + indent
            // controls, which stay pinned outside the scroll region rather than
            // being pushed off with a trailing Spacer — a Spacer can't rescue an
            // overflow, it just makes the indent buttons unreachable (audit 2.5).
            // The indent pair keeps a fixed (unscaled) frame — if it scaled with
            // typeScale too, two 50pt-wide buttons growing at once would eat most
            // of a 375pt (iPhone SE) row's width and leave next to no scrollable
            // viewport for the four list-type buttons at large Dynamic Type sizes.
            // The glyph inside still scales, just within that fixed box.
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        listButton(icon: "list.bullet", command: .bulletedList, accessibilityLabel: "Bulleted list")
                        listButton(icon: "list.dash",   command: .dashedList,   accessibilityLabel: "Dashed list")
                        listButton(icon: "list.number", command: .numberedList, accessibilityLabel: "Numbered list")
                        listButton(icon: "checklist",   command: .checklist,    accessibilityLabel: "Checklist")
                    }
                }
                listButton(icon: "decrease.indent", command: .indentLess, accessibilityLabel: "Decrease indent", scaleFrame: false)
                listButton(icon: "increase.indent", command: .indentMore, accessibilityLabel: "Increase indent", scaleFrame: false)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Row 3b: Checklist bulk ops — only when cursor is on a checklist line
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
                .padding(.top, 10)
            }

            // Row 4: Highlight colors (scrolling, same reasoning as row 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        DispatchQueue.main.async { state.onCommand?(.highlight(index: nil)) }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(idleFill)
                                .frame(width: 44 * typeScale, height: 36 * typeScale)
                            Image(systemName: "xmark")
                                .font(.system(size: 12 * typeScale, weight: .semibold))
                                .foregroundStyle(state.activeHighlightIndex == nil ? accent : Color.secondary)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(state.activeHighlightIndex == nil ? accent : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    // Identifier keeps the old symbol-derived name ("xmark") so
                    // existing lookups still find it; the label carries the
                    // VoiceOver-facing name.
                    .accessibilityIdentifier("xmark")
                    .accessibilityLabel("No highlight")
                    .accessibilityAddTraits(state.activeHighlightIndex == nil ? .isSelected : [])

                    ForEach(0..<HighlightPalette.colors(for: displayMode).count, id: \.self) { idx in
                        highlightButton(index: idx)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 10)

            Spacer(minLength: 12)
        }
    }

    // MARK: - Font family button

    @ViewBuilder
    private func fontChoiceButton(_ choice: WritingFontChoice) -> some View {
        let isActive = state.activeFontChoice == choice
        Button {
            DispatchQueue.main.async { state.onCommand?(.fontFamily(choice)) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(choice.label)
                .font(.system(size: 14 * typeScale, weight: .regular, design: choice.swiftUIDesign))
                .lineLimit(1)
                .foregroundStyle(isActive ? accent : Color.primary)
                .padding(.horizontal, 16)
                .frame(height: 44 * typeScale)
                .background(
                    isActive ? accent.opacity(0.12) : idleFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isActive ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Paragraph style button

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
                .padding(.horizontal, 16)
                .frame(height: 50 * typeScale)
                .background(
                    isActive ? accent.opacity(0.12) : idleFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isActive ? accent.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Inline style button (fixed square)

    @ViewBuilder
    private func inlineButton(_ label: String, style: InlineTextStyle, font: Font, underline: Bool = false, strikethrough: Bool = false, accessibilityLabel: String) -> some View {
        let isActive = state.activeInlineStyles.contains(style)
        Button {
            let cmd = inlineCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
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
            .foregroundStyle(isActive ? accent : Color.primary)
            .frame(width: 50 * typeScale, height: 44 * typeScale)
            .background(
                isActive ? accent.opacity(0.12) : idleFill,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        }
        .buttonStyle(.plain)
        // Identifier keeps the plain glyph ("B") so existing lookups (and
        // test hooks) still find it; the label carries the VoiceOver name —
        // bare "B"/"I"/"U"/"S" read as just their letter otherwise (audit 3.1).
        .accessibilityIdentifier(label)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - List button (fixed square icon)

    @ViewBuilder
    private func listButton(icon: String, command: NoteTextCommand, accessibilityLabel: String, scaleFrame: Bool = true) -> some View {
        let isActive = listIsActive(command: command)
        let frameScale = scaleFrame ? typeScale : 1
        // When the frame is pinned (scaleFrame == false, the indent pair — see
        // the call site), the glyph still needs to scale "within" that fixed
        // 44pt-tall box, not past it: an unbounded 18 * typeScale glyph would
        // render larger than its own hit target at large accessibility sizes
        // (SwiftUI doesn't clip an oversized Image to its frame, so it'd look
        // big while tapping small). Capped at 24 — comfortably inside 44pt.
        let iconSize = scaleFrame ? 18 * typeScale : min(18 * typeScale, 24)
        Button {
            DispatchQueue.main.async { state.onCommand?(command) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(isActive ? accent : Color.primary)
                .frame(width: 50 * frameScale, height: 44 * frameScale)
                .background(
                    isActive ? accent.opacity(0.12) : idleFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
        }
        .buttonStyle(.plain)
        // Identifier keeps the SF Symbol name so existing lookups still find
        // it; the label carries the human name — icon-only buttons otherwise
        // read to VoiceOver as the raw symbol name, e.g. "list.bullet" (3.1).
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
                    Text(label).font(.system(size: 12 * typeScale, weight: .medium))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 36 * typeScale)
            .background(idleFill, in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 5 : 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Highlight button

    @ViewBuilder
    private func highlightButton(index: Int) -> some View {
        let isActive = state.activeHighlightIndex == index
        Button {
            let newIndex = isActive ? nil : index
            DispatchQueue.main.async { state.onCommand?(.highlight(index: newIndex)) }
        } label: {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(HighlightPalette.colors(for: displayMode)[index])
                .frame(width: 44 * typeScale, height: 36 * typeScale)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isActive ? accent : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        // Swatches carry no visible text — without a label VoiceOver just
        // reads "button" for all five (audit 3.1).
        .accessibilityLabel(HighlightPalette.name(for: index, displayMode: displayMode))
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
