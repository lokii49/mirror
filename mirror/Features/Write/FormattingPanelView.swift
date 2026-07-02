import SwiftUI
import UIKit

let highlightColors: [Color] = [
    Color(red: 1.0, green: 0.75, blue: 0.80),   // pink
    Color(red: 0.82, green: 0.75, blue: 1.0),   // purple
    Color(red: 1.0, green: 0.84, blue: 0.60),   // orange/yellow
    Color(red: 0.70, green: 0.95, blue: 0.85),  // mint
    Color(red: 0.68, green: 0.85, blue: 1.0),   // blue
]

@Observable final class FormattingPanelState {
    var activeParagraphStyle: NoteParagraphTextStyle = .body
    var activeInlineStyles = InlineStyleSet()
    var activeHighlightIndex: Int? = nil
    /// The font family the *current paragraph/selection* is using — drives the
    /// font row's highlight, same role activeParagraphStyle plays for block style.
    var activeFontChoice: WritingFontChoice = .system
    /// Entry-wide fallback only (empty document, or a paragraph with no explicit
    /// override) — no longer mutated by tapping a font button; that now goes
    /// through onCommand(.fontFamily) like every other paragraph-level command.
    var fontChoiceRaw: String = WritingFontChoice.system.rawValue
    var onCommand: ((NoteTextCommand) -> Void)?
    var onDismiss: (() -> Void)?
}

struct FormattingPanelView: View {
    var state: FormattingPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Handle bar (Apple Notes style — tap Aa again to dismiss)
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 10)

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
                    paragraphStyleButton("Title",      style: .title,      labelFont: .system(size: 22, weight: .black))
                    paragraphStyleButton("Heading",    style: .heading,    labelFont: .system(size: 18, weight: .bold))
                    paragraphStyleButton("Subheading", style: .subheading, labelFont: .system(size: 15, weight: .semibold))
                    paragraphStyleButton("Body",       style: .body,       labelFont: .system(size: 14, weight: .regular))
                    paragraphStyleButton("Mono",       style: .monospaced, labelFont: .system(size: 13, design: .monospaced))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }

            // Row 2: Inline styles (fixed-size square buttons, left-aligned)
            HStack(spacing: 8) {
                inlineButton("B",  style: .bold,          font: .system(size: 17, weight: .bold))
                inlineButton("I",  style: .italic,        font: .system(size: 17).italic())
                inlineButton("U",  style: .underline,     font: .system(size: 17), underline: true)
                inlineButton("S",  style: .strikethrough, font: .system(size: 17), strikethrough: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Row 3: List types + indent controls
            HStack(spacing: 8) {
                listButton(icon: "list.bullet", command: .bulletedList)
                listButton(icon: "list.dash",   command: .dashedList)
                listButton(icon: "list.number", command: .numberedList)
                listButton(icon: "checklist",   command: .checklist)
                Spacer(minLength: 0)
                listButton(icon: "decrease.indent", command: .indentLess)
                listButton(icon: "increase.indent", command: .indentMore)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Row 3b: Checklist bulk ops — only when cursor is on a checklist line
            if state.activeParagraphStyle == .checklistUnchecked || state.activeParagraphStyle == .checklistChecked {
                HStack(spacing: 8) {
                    bulkChecklistButton("Check All",   command: .checkAllItems)
                    bulkChecklistButton("Uncheck All", command: .uncheckAllItems)
                    bulkChecklistButton("Delete Done", command: .deleteCheckedItems)
                    bulkChecklistButton("Sort Done",   command: .sortCheckedToBottom)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            // Row 4: Highlight colors
            HStack(spacing: 8) {
                Button {
                    DispatchQueue.main.async { state.onCommand?(.highlight(index: nil)) }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 44, height: 36)
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(state.activeHighlightIndex == nil ? Color.accentColor : Color.secondary)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(state.activeHighlightIndex == nil ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                ForEach(0..<highlightColors.count, id: \.self) { idx in
                    highlightButton(index: idx)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
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
                .font(.system(size: 14, weight: .regular, design: choice.swiftUIDesign))
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Paragraph style button

    @ViewBuilder
    private func paragraphStyleButton(_ label: String, style: NoteParagraphTextStyle, labelFont: Font) -> some View {
        let isActive = state.activeParagraphStyle == style
        Button {
            let cmd = paragraphCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
            Text(label)
                .font(labelFont)
                .lineLimit(1)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(
                    isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline style button (fixed square)

    @ViewBuilder
    private func inlineButton(_ label: String, style: InlineTextStyle, font: Font, underline: Bool = false, strikethrough: Bool = false) -> some View {
        let isActive = state.activeInlineStyles.contains(style)
        Button {
            let cmd = inlineCommand(for: style)
            DispatchQueue.main.async { state.onCommand?(cmd) }
        } label: {
            Group {
                if strikethrough {
                    Text(label).strikethrough(true, color: isActive ? Color.accentColor : Color.primary)
                } else if underline {
                    Text(label).underline(true, color: isActive ? Color.accentColor : Color.primary)
                } else {
                    Text(label)
                }
            }
            .font(font)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: 50, height: 44)
            .background(
                isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List button (fixed square icon)

    @ViewBuilder
    private func listButton(icon: String, command: NoteTextCommand) -> some View {
        let isActive = listIsActive(command: command)
        Button {
            DispatchQueue.main.async { state.onCommand?(command) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 50, height: 44)
                .background(
                    isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk checklist button

    @ViewBuilder
    private func bulkChecklistButton(_ label: String, command: NoteTextCommand) -> some View {
        Button {
            DispatchQueue.main.async { state.onCommand?(command) }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
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
            RoundedRectangle(cornerRadius: 10)
                .fill(highlightColors[index])
                .frame(width: 44, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
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
