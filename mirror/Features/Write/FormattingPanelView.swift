import SwiftUI

let highlightColors: [Color] = [
    Color(red: 1.0, green: 0.75, blue: 0.80),   // pink
    Color(red: 0.82, green: 0.75, blue: 1.0),   // purple
    Color(red: 1.0, green: 0.84, blue: 0.60),   // orange/yellow
    Color(red: 0.70, green: 0.95, blue: 0.85),  // mint
    Color(red: 0.68, green: 0.85, blue: 1.0),   // blue
]

// Observable state shared between WriteView and the formatting panel.
@Observable final class FormattingPanelState {
    var activeParagraphStyle: NoteParagraphTextStyle = .body
    var activeInlineStyles = InlineStyleSet()
    var activeHighlightIndex: Int? = nil
    var onCommand: ((NoteTextCommand) -> Void)?
    var onDismiss: (() -> Void)?
}

struct FormattingPanelView: View {
    var state: FormattingPanelState

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Row 1: Paragraph styles
            HStack(spacing: 6) {
                paragraphButton("Title",      style: .title,      font: .title3.bold())
                paragraphButton("Heading",    style: .heading,    font: .headline)
                paragraphButton("Subheading", style: .subheading, font: .subheadline)
                paragraphButton("Body",       style: .body,       font: .body)
                paragraphButton("Mono",       style: .monospaced, font: .system(.footnote, design: .monospaced))
            }
            .padding(.horizontal, 12)

            Divider().padding(.vertical, 10)

            // Row 2: Inline styles
            HStack(spacing: 6) {
                inlineButton("B",  style: .bold,          font: .system(size: 17, weight: .bold))
                inlineButton("I",  style: .italic,        font: .system(size: 17).italic())
                inlineButton("U",  style: .underline,     font: .system(size: 17),         underline: true)
                inlineButton("S",  style: .strikethrough, font: .system(size: 17),         strikethrough: true)
            }
            .padding(.horizontal, 12)

            Divider().padding(.vertical, 10)

            // Row 3: List types + indent controls
            HStack(spacing: 6) {
                listButton(icon: "list.bullet",           command: .bulletedList)
                listButton(icon: "list.dash",             command: .dashedList)
                listButton(icon: "list.number",           command: .numberedList)
                listButton(icon: "checklist",             command: .checklist)
                listButton(icon: "decrease.indent",       command: .indentLess)
                listButton(icon: "increase.indent",       command: .indentMore)
            }
            .padding(.horizontal, 12)

            // Row 3b: Checklist bulk ops (contextual — only when cursor is on a checklist line)
            if state.activeParagraphStyle == .checklistUnchecked || state.activeParagraphStyle == .checklistChecked {
                Divider().padding(.vertical, 6)
                HStack(spacing: 6) {
                    bulkChecklistButton("Check All",   command: .checkAllItems)
                    bulkChecklistButton("Uncheck All", command: .uncheckAllItems)
                    bulkChecklistButton("Delete Done", command: .deleteCheckedItems)
                    bulkChecklistButton("Sort Done",   command: .sortCheckedToBottom)
                }
                .padding(.horizontal, 12)
            }

            Divider().padding(.vertical, 10)

            // Row 4: Highlight colors
            HStack(spacing: 6) {
                // Clear button
                Button {
                    state.onCommand?(.highlight(index: nil))
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 32)
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(state.activeHighlightIndex == nil ? Color.accentColor : Color.secondary)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(state.activeHighlightIndex == nil ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                ForEach(0..<highlightColors.count, id: \.self) { idx in
                    highlightButton(index: idx)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .topTrailing) {
            Button {
                state.onDismiss?()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.trailing, 4)
        }
    }

    // MARK: - Paragraph button

    @ViewBuilder
    private func paragraphButton(_ label: String, style: NoteParagraphTextStyle, font: Font) -> some View {
        let isActive = state.activeParagraphStyle == style
        Button {
            state.onCommand?(paragraphCommand(for: style))
        } label: {
            Text(label)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inline button

    @ViewBuilder
    private func inlineButton(_ label: String, style: InlineTextStyle, font: Font, underline: Bool = false, strikethrough: Bool = false) -> some View {
        let isActive = state.activeInlineStyles.contains(style)
        Button {
            state.onCommand?(inlineCommand(for: style))
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
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .background(isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk checklist button

    @ViewBuilder
    private func bulkChecklistButton(_ label: String, command: NoteTextCommand) -> some View {
        Button {
            state.onCommand?(command)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(Color.primary)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Highlight button

    @ViewBuilder
    private func highlightButton(index: Int) -> some View {
        let isActive = state.activeHighlightIndex == index
        Button {
            state.onCommand?(.highlight(index: isActive ? nil : index))
        } label: {
            highlightColors[index]
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - List button

    @ViewBuilder
    private func listButton(icon: String, command: NoteTextCommand) -> some View {
        let isActive = listIsActive(command: command)
        Button {
            state.onCommand?(command)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .background(isActive ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

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
