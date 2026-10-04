#if os(macOS)
import SwiftUI

/// The Mac Write screen's Aa popover, laid out like Notes on the Mac: a row of B / I / U / S and
/// indent controls, then the paragraph styles as a list with a checkmark on the current one, then
/// colours, font, link and clear formatting. Every control sends the same `NoteTextCommand` the
/// iPhone panel and the Format menu send, through `FormattingPanelState.onCommand`. The Format menu
/// has the styles, B/I/U/S and indent but not fonts, colours, links or the checklist actions, so
/// those live here too.
struct MacNotesFormatPopover: View {
    @Bindable var state: FormattingPanelState
    @Environment(\.appDisplayMode) private var displayMode

    private func send(_ command: NoteTextCommand) { state.onCommand?(command) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inlineRow
            Divider()
            VStack(alignment: .leading, spacing: 1) {
                styleRow("Title", style: .title, command: .title, font: .system(size: 17, weight: .bold))
                styleRow("Heading", style: .heading, command: .heading, font: .system(size: 14.5, weight: .bold))
                styleRow("Subheading", style: .subheading, command: .subheading, font: .system(size: 13, weight: .semibold))
                styleRow("Body", style: .body, command: .body, font: .system(size: 13))
                styleRow("Monospaced", style: .monospaced, command: .monospaced, font: .system(size: 12.5, design: .monospaced))
            }
            Divider()
            VStack(alignment: .leading, spacing: 1) {
                listRow("Bulleted List", symbol: "•", command: .bulletedList, isOn: state.activeParagraphStyle == .bulletedList)
                listRow("Dashed List", symbol: "–", command: .dashedList, isOn: state.activeParagraphStyle == .dashedList)
                listRow("Numbered List", symbol: "1.", command: .numberedList, isOn: state.activeParagraphStyle == .numberedList)
                listRow("Checklist", symbol: "◯", command: .checklist, isOn: isChecklist)
                styleRow("Block Quote", style: .blockQuote, command: .blockQuote, font: .system(size: 13).italic(), bar: true)
            }
            if isChecklist {
                checklistActions
            }
            Divider()
            swatchRow(title: "Highlight", colors: HighlightPalette.colors(for: displayMode), active: state.activeHighlightIndex,
                      name: { HighlightPalette.name(for: $0, displayMode: displayMode) }) { send(.highlight(index: $0)) }
            swatchRow(title: "Text color", colors: TextColorPalette.colors(for: displayMode), active: state.activeTextColorIndex,
                      name: { TextColorPalette.name(for: $0, displayMode: displayMode) }) { send(.textColor(index: $0)) }
            Divider()
            bottomRow
        }
        .padding(14)
        .frame(width: 272)
    }

    private var isChecklist: Bool {
        state.activeParagraphStyle == .checklistUnchecked || state.activeParagraphStyle == .checklistChecked
    }

    // MARK: - B / I / U / S + indent

    private var inlineRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                inlineCell("B", style: .bold, font: .system(size: 13, weight: .bold), label: "Bold")
                cellDivider
                inlineCell("I", style: .italic, font: .custom("Georgia", size: 13.5).italic(), label: "Italic")
                cellDivider
                inlineCell("U", style: .underline, font: .system(size: 13), underline: true, label: "Underline")
                cellDivider
                inlineCell("S", style: .strikethrough, font: .system(size: 13), strikethrough: true, label: "Strikethrough")
            }
            .modifier(CapsuleGroup())
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                iconCell("decrease.indent", label: "Decrease Indent") { send(.indentLess) }
                cellDivider
                iconCell("increase.indent", label: "Increase Indent") { send(.indentMore) }
            }
            .modifier(CapsuleGroup())
        }
    }

    private func inlineCell(_ text: String, style: InlineTextStyle, font: Font, underline: Bool = false,
                            strikethrough: Bool = false, label: LocalizedStringKey) -> some View {
        let on = state.activeInlineStyles.contains(style)
        return Button {
            switch style {
            case .bold: send(.bold)
            case .italic: send(.italic)
            case .underline: send(.underline)
            case .strikethrough: send(.strikethrough)
            }
        } label: {
            Text(text)
                .font(font)
                .underline(underline)
                .strikethrough(strikethrough)
                .frame(width: 34, height: 26)
                .foregroundStyle(on ? Color.white : MacTokens.ink)
                .background(on ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(label)
    }

    private func iconCell(_ systemName: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 32, height: 26)
                .foregroundStyle(MacTokens.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var cellDivider: some View {
        Rectangle().fill(MacTokens.controlBorder).frame(width: 1, height: 16)
    }

    // MARK: - Style list

    private func styleRow(_ title: LocalizedStringKey, style: NoteParagraphTextStyle, command: NoteTextCommand,
                          font: Font, bar: Bool = false) -> some View {
        listButton(isOn: state.activeParagraphStyle == style, label: title, action: { send(command) }) {
            HStack(spacing: 6) {
                if bar { Rectangle().fill(MacTokens.secondaryInk).frame(width: 2, height: 14) }
                Text(title).font(font).foregroundStyle(MacTokens.ink)
            }
        }
    }

    private func listRow(_ title: LocalizedStringKey, symbol: String, command: NoteTextCommand, isOn: Bool) -> some View {
        listButton(isOn: isOn, label: title, action: { send(command) }) {
            HStack(spacing: 6) {
                Text(verbatim: symbol).font(.system(size: 13)).foregroundStyle(MacTokens.secondaryInk).frame(minWidth: 14, alignment: .leading)
                Text(title).font(.system(size: 13)).foregroundStyle(MacTokens.ink)
            }
        }
    }

    private func listButton<Label: View>(isOn: Bool, label: LocalizedStringKey, action: @escaping () -> Void,
                                         @ViewBuilder content: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 14)
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(MacPopoverRowStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var checklistActions: some View {
        Menu {
            Button("Check All") { send(.checkAllItems) }
            Button("Uncheck All") { send(.uncheckAllItems) }
            Button("Sort Done") { send(.sortCheckedToBottom) }
            Divider()
            Button("Delete Done", role: .destructive) { send(.deleteCheckedItems) }
        } label: {
            Label("Checklist", systemImage: "checklist").font(.system(size: 12))
        }
        .menuStyle(.button)
        .fixedSize()
        .padding(.leading, 26)
    }

    // MARK: - Colours

    private func swatchRow(title: LocalizedStringKey, colors: [Color], active: Int?, name: @escaping (Int) -> String,
                           apply: @escaping (Int?) -> Void) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(MacTokens.secondaryInk)
                .frame(width: 66, alignment: .leading)
            Button { apply(nil) } label: {
                Image(systemName: "circle.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(MacTokens.secondaryInk)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("None"))
            .help("None")
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                Button { apply(index) } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .overlay { Circle().stroke(active == index ? Color.accentColor : MacTokens.controlBorder, lineWidth: active == index ? 2 : 1) }
                        .padding(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(name(index)))
                .accessibilityAddTraits(active == index ? .isSelected : [])
                .help(name(index))
            }
        }
    }

    // MARK: - Font, link, clear

    private var bottomRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(WritingFontChoice.allCases) { choice in
                    Button {
                        send(.fontFamily(choice))
                    } label: {
                        if choice == state.activeFontChoice {
                            Label(choice.label, systemImage: "checkmark")
                        } else {
                            Text(choice.label)
                        }
                    }
                }
            } label: {
                Text(state.activeFontChoice.label).font(.system(size: 12))
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Font")
            Spacer(minLength: 0)
            Button { state.onRequestLinkEditor?() } label: {
                Image(systemName: "link").font(.system(size: 12))
            }
            .help(state.activeLinkURL == nil ? "Add Link" : "Edit Link")
            .accessibilityLabel(state.activeLinkURL == nil ? Text("Add Link") : Text("Edit Link"))
            Button { send(.clearFormatting) } label: {
                Image(systemName: "eraser").font(.system(size: 12))
            }
            .help("Clear Formatting")
            .accessibilityLabel(Text("Clear Formatting"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Rounded group that holds segmented controls, as in Notes' toolbar and format popover.
private struct CapsuleGroup: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MacTokens.surface, in: Capsule())
            .overlay { Capsule().stroke(MacTokens.controlBorder, lineWidth: 1) }
            .clipShape(Capsule())
    }
}

/// A popover list row: tinted on hover and press, like a menu item.
private struct MacPopoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}
#endif

#if os(macOS) && DEBUG
import AppKit

/// DEBUG: `--renderFormatPopover=<dir>` writes the Aa popover in light and dark to PNG and quits,
/// for design review (popovers don't appear in the Mac snapshot harness).
enum MacFormatPopoverRender {
    static var requestedDirectory: String? {
        CommandLine.arguments.first { $0.hasPrefix("--renderFormatPopover=") }.map { String($0.dropFirst("--renderFormatPopover=".count)) }
    }

    @MainActor
    static func renderAndQuit(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let state = FormattingPanelState()
            state.activeParagraphStyle = .heading
            state.activeInlineStyles.bold = true
            state.activeHighlightIndex = 1
            let host = NSHostingView(rootView: MacNotesFormatPopover(state: state).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/format-popover-\(name).png"))
            }
            window.close()
        }
        exit(0)
    }
}
#endif
