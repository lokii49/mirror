import SwiftUI

/// The What's New sheet as a paged walkthrough: one card per page, each with a small looping demo of
/// the feature drawn in SwiftUI (no video, no screenshots, so it follows the theme, Dynamic Type and the
/// language). Cards without a demo (the privacy notice) show their icon. Reduce Motion shows each demo's
/// last frame, still. The Feature Guide in Settings keeps the plain list.
struct WhatsNewWalkthrough: View {
    let cards: [FeatureCard]
    var onFinish: () -> Void
    @Environment(\.appDisplayMode) private var displayMode
    @State private var index: Int

    init(cards: [FeatureCard], startIndex: Int = 0, onFinish: @escaping () -> Void) {
        self.cards = cards
        self.onFinish = onFinish
        _index = State(initialValue: startIndex)
    }

    /// Tests only: render every demo at this phase, still (render harness).
    static var snapshotPhase: Int? = nil

    /// Card ids that have a demo. A What's New with none of them uses the plain list instead.
    static let demoIDs: Set<String> = ["smart-ask-search-310", "reflection-styles-310", "format-panel-310", "writing-310",
                                       // 3.1.8 (owner, 2026-11-06): the ten pages of the 3.1.8 What's New video.
                                       "theme-318", "write-318", "focus-mode-318", "scratch-318", "still-open-318",
                                       "links-318", "patterns-318", "watch-318", "health-318", "show-all-318"]

    static func supports(_ cards: [FeatureCard]) -> Bool {
        cards.contains { demoIDs.contains($0.id) }
    }

    /// More pages than this show a "3 of 9" counter instead of dots.
    static let maxDots = 7

    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }
    private var isLast: Bool { index >= cards.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { offset, card in
                    if offset == index {
                        AnyView(WhatsNewPage(card: card))
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.width < -40 { go(to: index + 1) }
                    if value.translation.width > 40 { go(to: index - 1) }
                }
            )

            controls
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 8)
        }
        .background(MirrorTheme.bgBase)
        #if os(macOS)
        // A Mac sheet sizes to its content, and this view fills whatever it is given.
        .frame(width: 560, height: 680)
        #endif
    }

    private func go(to newIndex: Int) {
        guard cards.indices.contains(newIndex) else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { index = newIndex }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Group {
                if cards.count <= Self.maxDots {
                    HStack(spacing: 7) {
                        ForEach(cards.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? accent : Color.primary.opacity(0.18))
                                .frame(width: i == index ? 20 : 7, height: 7)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
                } else {
                    // A row of dots wider than the screen widened the whole sheet (3.1.0, 28 pages).
                    Text("\(index + 1) of \(cards.count)")
                        .scaledFont(displayMode == .sentinel ? 12 : 13, weight: .semibold, design: displayMode == .sentinel ? .monospaced : .default)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(index + 1) of \(cards.count)"))

            HStack(spacing: 12) {
                if index > 0 {
                    Button { go(to: index - 1) } label: {
                        Text("Back")
                            .scaledFont(16, weight: .semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(Color.primary)
                            .background(MirrorTheme.inkRaised, in: buttonShape)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if isLast { onFinish() } else { go(to: index + 1) }
                } label: {
                    Text(isLast ? "Get started" : "Next")
                        .scaledFont(16, weight: .semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        // White text needs the deep plum fill: the dark-mode accent (#C98BC6) carries white at 2.6:1.
                        .background(displayMode == .sentinel ? accent : MirrorTheme.buttonFill, in: buttonShape)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var buttonShape: AnyShape {
        displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 8)) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One page: the demo (or the card's icon), then the title and text.
private struct WhatsNewPage: View {
    let card: FeatureCard
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                demo
                    .frame(maxWidth: 420)
                    .frame(height: 250)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Group {
                        if displayMode == .sentinel {
                            Text(card.title).scaledFont(19, weight: .bold, design: .monospaced)
                        } else {
                            Text(card.title).scaledFont(24, weight: .bold, design: .rounded)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                    if card.tier != .free {
                        Text(card.tier.label)
                            .scaledFont(11, weight: .bold)
                            .foregroundStyle(card.tier.color)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(card.tier.color.opacity(0.12), in: Capsule())
                    }

                    Text(card.body)
                        .scaledFont(15)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 440)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Each demo is type-erased: the nested generic view types were deep enough to overflow the main
    /// thread's stack while SwiftUI built them (seen in a Debug render on an iPhone 14 Pro, 2026-10-09).
    private var demo: AnyView {
        switch card.id {
        case "smart-ask-search-310": return AnyView(DemoStage { AnyView(AskSearchDemo(phase: $0)) })
        case "reflection-styles-310": return AnyView(DemoStage { AnyView(ReflectionStylesDemo(phase: $0)) })
        case "format-panel-310": return AnyView(DemoStage { AnyView(FormatPanelDemo(phase: $0)) })
        case "writing-310": return AnyView(DemoStage { AnyView(WritingDemo(phase: $0)) })
        case "theme-318": return AnyView(DemoStage { AnyView(ThemeDemo(phase: $0)) })
        case "write-318": return AnyView(DemoStage { AnyView(WriteHeaderDemo(phase: $0)) })
        case "focus-mode-318": return AnyView(DemoStage { AnyView(FocusModeDemo(phase: $0)) })
        case "scratch-318": return AnyView(DemoStage { AnyView(ScratchDemo(phase: $0)) })
        case "still-open-318": return AnyView(DemoStage { AnyView(StillOpenDemo(phase: $0)) })
        case "links-318": return AnyView(DemoStage { AnyView(EntryLinksDemo(phase: $0)) })
        case "patterns-318": return AnyView(DemoStage { AnyView(PatternsDemo(phase: $0)) })
        case "watch-318": return AnyView(DemoStage { AnyView(WatchDemo(phase: $0)) })
        case "health-318": return AnyView(DemoStage { AnyView(HealthDemo(phase: $0)) })
        case "show-all-318": return AnyView(DemoStage { AnyView(ShowAllDemo(phase: $0)) })
        default: return AnyView(IconStage(card: card))
        }
    }
}

// MARK: - Stage

/// Loops a demo through phases 0...3, holding each; with Reduce Motion, shows phase 3 still.
private struct DemoStage<Content: View>: View {
    @ViewBuilder var content: (Int) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        ZStack {
            stageShape.fill(MirrorTheme.inkRaised)
            stageShape.stroke(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.25) : MirrorTheme.inkBorder, lineWidth: 1)
            Group {
                if let phase = WhatsNewWalkthrough.snapshotPhase {
                    content(phase)
                } else if reduceMotion {
                    content(3)
                } else {
                    PhaseAnimator([0, 1, 2, 3]) { phase in
                        content(phase)
                    } animation: { phase in
                        // Time to read each step; the jump back to the start is quick.
                        .spring(response: phase == 0 ? 0.35 : 0.55, dampingFraction: 0.85).delay(phase == 0 ? 0.6 : 1.1)
                    }
                }
            }
            .padding(18)
        }
        .clipShape(stageShape)
    }

    private var stageShape: AnyShape {
        displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct IconStage: View {
    let card: FeatureCard
    var body: some View {
        ZStack {
            Circle().fill(card.accentColor.opacity(0.14)).frame(width: 150, height: 150)
            Circle().fill(card.accentColor.opacity(0.10)).frame(width: 104, height: 104)
            Image(systemName: card.symbolName)
                .scaledFont(46, weight: .semibold)
                .foregroundStyle(card.accentColor)
        }
    }
}

private extension View {
    func demoCard(_ displayMode: DisplayMode, highlighted: Bool = false, accent: Color) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? accent.opacity(0.14) : MirrorTheme.bgBase,
                        in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 12, style: .continuous)
                .stroke(highlighted ? accent.opacity(0.6) : MirrorTheme.inkBorder, lineWidth: highlighted ? 1.5 : 1))
    }
}

// MARK: - Demos (synthetic sample text only)

/// A question finds the entry that means the same thing, without sharing its words.
private struct AskSearchDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(accent)
                Text("a calm evening")
                    .scaledFont(15, weight: .medium)
                    .opacity(phase >= 1 ? 1 : 0)
                Spacer(minLength: 0)
            }
            .demoCard(displayMode, accent: accent)

            VStack(alignment: .leading, spacing: 7) {
                row("Deadline moved up again.", match: false)
                row("Sat on the balcony after dinner. Finally quiet.", match: true)
                row("Long call with Mum about the trip.", match: false)
            }
            .opacity(phase >= 1 ? 1 : 0.35)
        }
    }

    private func row(_ text: LocalizedStringKey, match: Bool) -> some View {
        let lit = match && phase >= 2
        return VStack(alignment: .leading, spacing: 4) {
            Text(text).scaledFont(13).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if lit && phase >= 3 {
                Label("Found by meaning", systemImage: "sparkles")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(accent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .demoCard(displayMode, highlighted: lit, accent: accent)
        .scaleEffect(lit ? 1.02 : 1)
        .opacity(phase >= 2 && !match ? 0.45 : 1)
    }
}

/// The same reflection in each style: Gentle, Quiet (the quote only), Curious (a question).
private struct ReflectionStylesDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }
    /// 0-1 Gentle, 2 Quiet, 3 Curious.
    private var style: Int { phase <= 1 ? 0 : phase - 1 }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                chip("Gentle", on: style == 0)
                chip("Quiet", on: style == 1)
                chip("Curious", on: style == 2)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 3)
                    Text("Sat on the balcony after dinner. Finally quiet.")
                        .scaledFont(15, weight: .medium, design: .serif).italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    Text("You seem calmer tonight.").opacity(style == 0 ? 1 : 0)
                    Text("What's underneath “Finally quiet”?").opacity(style == 2 ? 1 : 0)
                }
                .scaledFont(14)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: style == 1 ? 0 : nil, alignment: .top)
                .clipped()
            }
            .demoCard(displayMode, accent: accent)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: LocalizedStringKey, on: Bool) -> some View {
        Text(title)
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(on ? .white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(on ? accent : MirrorTheme.bgBase, in: Capsule())
            .overlay(Capsule().stroke(on ? Color.clear : MirrorTheme.inkBorder, lineWidth: 1))
    }
}

/// The new Aa panel: the control being used lights up and the sample line follows it.
private struct FormatPanelDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if phase >= 3 { Text("•").scaledFont(18, weight: .bold) }
                Text("Morning pages")
                    .font(.system(size: phase >= 1 ? 22 : 16, weight: phase >= 1 ? .bold : .regular))
                    .padding(.horizontal, phase >= 2 ? 4 : 0)
                    .background(phase >= 2 ? HighlightPalette.colors(for: displayMode)[1] : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4))
                Spacer(minLength: 0)
            }
            .frame(height: 34)

            HStack(spacing: 6) {
                tile("Title", on: phase == 1)
                tile("Body", on: phase == 0)
                tile("Quote", on: false)
            }
            HStack(spacing: 0) {
                cell("B", on: phase >= 1)
                cell("I", on: false)
                cell("U", on: false)
                cell("•", on: phase >= 3)
                cell("1.", on: false)
            }
            .background(MirrorTheme.bgBase, in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 12, style: .continuous))
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(HighlightPalette.colors(for: displayMode)[i])
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(i == 1 && phase >= 2 ? accent : Color.clear, lineWidth: 2).padding(-3))
                        .padding(3)
                }
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, on: Bool) -> some View {
        Text(title)
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(on ? accent : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(on ? accent.opacity(0.16) : MirrorTheme.bgBase,
                        in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 10, style: .continuous))
    }

    private func cell(_ glyph: String, on: Bool) -> some View {
        Text(verbatim: glyph)
            .scaledFont(15, weight: .bold)
            .foregroundStyle(on ? accent : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(on ? accent.opacity(0.16) : Color.clear)
    }
}

/// A draft that keeps its date, turns "#work, sleep" into two tags and is saved.
/// Kept flat (strings built in code, blocks type-erased): a richer version overflowed the main thread's
/// stack in a Debug render.
private struct WritingDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    private var accent: Color { displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }
    private var dateText: String {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
    private var work: String { String(localized: "work") }
    private var sleep: String { String(localized: "sleep") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            tagRow
            editorRow
            Spacer(minLength: 0)
        }
    }

    private var headerRow: AnyView {
        AnyView(HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(verbatim: dateText)
            }
            .scaledFont(13, weight: .medium)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(accent.opacity(0.12), in: Capsule())
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("Draft saved")
            }
            .scaledFont(12, weight: .medium)
            .foregroundStyle(.secondary)
            .opacity(phase >= 3 ? 1 : 0)
        })
    }

    private var tagRow: AnyView {
        if phase >= 2 {
            return AnyView(HStack(spacing: 6) {
                chip("#" + work)
                chip("#" + sleep)
                Spacer(minLength: 0)
            }
            .frame(height: 28))
        }
        return AnyView(HStack {
            Text(verbatim: phase >= 1 ? "#\(work), \(sleep)" : " ")
                .scaledFont(13, weight: .medium)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(MirrorTheme.bgBase, in: Capsule()))
    }

    private var editorRow: AnyView {
        AnyView(HStack(alignment: .center, spacing: 1) {
            Text("Walked to the market early.")
                .scaledFont(16)
            Caret(color: accent)
            Spacer(minLength: 0)
        }
        .demoCard(displayMode, accent: accent))
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text)
            .scaledFont(13, weight: .medium)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MirrorTheme.bgBase, in: Capsule())
            .overlay(Capsule().stroke(MirrorTheme.inkBorder, lineWidth: 1))
    }
}

// MARK: - 3.1.8 demos (the 3.1.8 What's New video's pages, drawn here so they follow theme, text size and language)
// Sample text reuses strings the app already translates (the 3.1.0 demo lines, template names, mood names,
// "Still Open", "Linked from", …). Each demo's body is one type-erased block (main-thread stack limit).

private struct DemoAccent {
    let mode: DisplayMode
    var color: Color { mode == .sentinel ? MirrorTheme.ember : MirrorTheme.primary }
    var corner: CGFloat { mode == .sentinel ? 6 : 12 }
}

/// Weekday and date in the view's language (the render harness sets `\.locale`).
private func demoDate(_ daysAgo: Int, _ locale: Locale, weekday: Bool = true) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return weekday
        ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        : date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
}

private func moodPill(_ mood: String, mode: DisplayMode) -> some View {
    HStack(spacing: 5) {
        Circle().fill(MirrorTheme.moodColor(for: mood)).frame(width: 8, height: 8)
        Text(LocalizedStringKey(mood))
    }
    .scaledFont(12, weight: .semibold)
    .padding(.horizontal, 9)
    .frame(height: 24)
    .background(MirrorTheme.moodColor(for: mood).opacity(0.16), in: Capsule())
}

/// The same small Write screen in light, then dark: paper and plum, then warm off-black.
private struct ThemeDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let dark = phase >= 2
        return AnyView(VStack(spacing: 12) {
            HStack(spacing: 8) {
                modeIcon("sun.max.fill", on: !dark)
                modeIcon("moon.fill", on: dark)
                Spacer(minLength: 0)
            }
            sample
                .environment(\.colorScheme, dark ? .dark : .light)
                .animation(.easeInOut(duration: 0.5), value: dark)
            Spacer(minLength: 0)
        })
    }

    private var sample: AnyView {
        let a = DemoAccent(mode: displayMode)
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: demoDate(0, locale)).scaledFont(15, weight: .bold).foregroundStyle(MirrorTheme.textPrimary)
                Spacer(minLength: 0)
                Text("Save").scaledFont(12, weight: .semibold).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.buttonFill, in: Capsule())
            }
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5).fill(a.color).frame(width: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sat on the balcony after dinner. Finally quiet.")
                        .scaledFont(14, weight: .medium, design: .serif).italic()
                        .foregroundStyle(MirrorTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You seem calmer tonight.").scaledFont(13).foregroundStyle(MirrorTheme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: a.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: a.corner, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1))
        }
        .padding(12)
        .background(MirrorTheme.bgBase, in: RoundedRectangle(cornerRadius: a.corner + 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: a.corner + 4, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1)))
    }

    private func modeIcon(_ symbol: String, on: Bool) -> some View {
        let a = DemoAccent(mode: displayMode)
        return Image(systemName: symbol)
            .scaledFont(14, weight: .semibold)
            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.5))
            .frame(width: 36, height: 30)
            .background(on ? a.color : MirrorTheme.bgBase, in: Capsule())
    }
}

/// The date as the title, Mood beside it, then a template fills the page.
private struct WriteHeaderDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        let templates: [WritingTemplate] = [.eveningReview, .gratitude, .morningPages]
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Date().formatted(.dateTime.weekday(.wide).locale(locale)))
                        .scaledFont(22, weight: .bold)
                    Text(verbatim: demoDate(0, locale, weekday: false))
                        .scaledFont(12).foregroundStyle(MirrorTheme.textSecondary)
                }
                Spacer(minLength: 8)
                if phase >= 1 {
                    moodPill("Peaceful", mode: displayMode).transition(.scale.combined(with: .opacity))
                } else {
                    Text("Mood").scaledFont(12, weight: .semibold).foregroundStyle(MirrorTheme.textSecondary)
                        .padding(.horizontal, 10).frame(height: 24)
                        .overlay(Capsule().strokeBorder(MirrorTheme.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }
            }
            HStack(spacing: 6) {
                ForEach(templates) { template in
                    Text(verbatim: template.title)
                        .scaledFont(12, weight: .semibold)
                        .lineLimit(1)
                        .foregroundStyle(phase >= 3 && template == .eveningReview ? Color.white : Color.primary)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(phase >= 3 && template == .eveningReview ? a.color : MirrorTheme.bgBase, in: Capsule())
                        .overlay(Capsule().stroke(MirrorTheme.inkBorder, lineWidth: phase >= 3 && template == .eveningReview ? 0 : 1))
                }
            }
            .opacity(phase >= 2 ? 1 : 0)
            Text(verbatim: phase >= 3 ? WritingTemplate.eveningReview.seedText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        .components(separatedBy: .newlines).filter { !$0.isEmpty }.prefix(2).joined(separator: "\n") : " ")
                .scaledFont(14, weight: .semibold)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .demoCard(displayMode, accent: a.color)
                .opacity(phase >= 3 ? 1 : 0.4)
            Spacer(minLength: 0)
        })
    }
}

/// Focus mode: the date, mood and toolbar step aside and only the words stay.
private struct FocusModeDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        let focused = phase == 2 || phase == 3
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis.circle").opacity(focused ? 0 : 1)
                Image(systemName: focused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(phase == 1 || focused ? a.color : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(phase == 1 ? a.color.opacity(0.18) : Color.clear, in: Circle())
                Spacer(minLength: 0)
                Text("Save").scaledFont(12, weight: .semibold).foregroundStyle(.white)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.buttonFill, in: Capsule())
            }
            .scaledFont(16, weight: .semibold)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: demoDate(0, locale)).scaledFont(18, weight: .bold)
                moodPill("Content", mode: displayMode)
            }
            .opacity(focused ? 0 : 1)
            .frame(height: focused ? 0 : nil, alignment: .top)
            .clipped()
            HStack(alignment: .center, spacing: 1) {
                Text("Walked to the market early.").readingFont(size: focused ? 19 : 16)
                Caret(color: a.color)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack {
                ForEach(["textformat", "checklist", "camera", "mic"], id: \.self) { symbol in
                    Image(systemName: symbol).frame(maxWidth: .infinity)
                }
            }
            .scaledFont(15)
            .foregroundStyle(MirrorTheme.textSecondary)
            .opacity(focused ? 0 : 1)
        })
    }
}

/// A quick note goes into Scratch, kept out; the reflection reads only the journal entry.
private struct ScratchDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Entries", systemImage: "book.closed").scaledFont(12, weight: .bold).foregroundStyle(MirrorTheme.textSecondary)
                    Text("Sat on the balcony after dinner. Finally quiet.")
                        .scaledFont(13).fixedSize(horizontal: false, vertical: true)
                        .demoCard(displayMode, highlighted: phase >= 3, accent: a.color)
                    if phase == 0 { note.transition(.opacity) }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Scratch", systemImage: "note.text").scaledFont(12, weight: .bold).foregroundStyle(MirrorTheme.textSecondary)
                    if phase >= 1 { note.transition(.move(edge: .leading).combined(with: .opacity)) }
                    if phase >= 2 {
                        Label("Keep out of reflections", systemImage: "eye.slash")
                            .scaledFont(11, weight: .semibold)
                            .foregroundStyle(a.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if phase >= 3 {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(a.color)
                    Text("You seem calmer tonight.").scaledFont(13, weight: .medium)
                    Spacer(minLength: 0)
                }
                .demoCard(displayMode, accent: a.color)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer(minLength: 0)
        })
    }

    private var note: some View {
        Text("Oats, lemons, tape")
            .scaledFont(13)
            .fixedSize(horizontal: false, vertical: true)
            .demoCard(displayMode, accent: DemoAccent(mode: displayMode).color)
    }
}

/// Unticked checklist items from three entries gather into one list; one gets ticked.
private struct StillOpenDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        let items: [(LocalizedStringKey, Int)] = [("Call the dentist", 4), ("Return the library books", 2), ("Send the photos", 1)]
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist.unchecked").foregroundStyle(a.color)
                Text("Still Open").scaledFont(15, weight: .bold)
                Text(verbatim: "\(phase >= 3 ? 2 : 3)").scaledFont(13, weight: .semibold).foregroundStyle(MirrorTheme.textSecondary).monospacedDigit()
                Spacer(minLength: 0)
            }
            .opacity(phase >= 1 ? 1 : 0.35)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let ticked = phase >= 3 && i == 0
                HStack(spacing: 9) {
                    Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(ticked ? a.color : MirrorTheme.textSecondary)
                    Text(item.0).scaledFont(13).strikethrough(ticked).opacity(ticked ? 0.55 : 1).lineLimit(2)
                    Spacer(minLength: 6)
                    Text(verbatim: demoDate(item.1, locale, weekday: false))
                        .scaledFont(11).foregroundStyle(MirrorTheme.textSecondary).opacity(phase >= 2 ? 1 : 0)
                }
                .demoCard(displayMode, highlighted: phase >= 1 && phase < 3 && i == 0, accent: a.color)
                .opacity(phase >= 1 ? 1 : 0.35)
                .offset(x: phase >= 1 ? 0 : CGFloat(i * 14 - 14))
            }
            Spacer(minLength: 0)
        })
    }
}

/// Select words, Add Link › Link to an Entry; the older entry shows Linked from.
private struct EntryLinksDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: demoDate(0, locale)).scaledFont(11).foregroundStyle(MirrorTheme.textSecondary)
                Text("Walked to the market early.")
                    .scaledFont(14)
                    .foregroundStyle(phase >= 3 ? a.color : Color.primary)
                    .underline(phase >= 3)
                    .padding(.horizontal, 2)
                    .background(phase == 1 ? a.color.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            }
            .demoCard(displayMode, accent: a.color)
            .overlay(alignment: .bottomTrailing) {
                if phase == 2 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Add Link").padding(.horizontal, 10).padding(.vertical, 6)
                        Text("Link to an Entry…").foregroundStyle(a.color).padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading).background(a.color.opacity(0.12))
                    }
                    .scaledFont(12, weight: .medium)
                    .fixedSize()
                    .background(MirrorTheme.inkMid, in: RoundedRectangle(cornerRadius: a.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: a.corner, style: .continuous).stroke(MirrorTheme.inkBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .offset(x: -8, y: 46)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
            .zIndex(1)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: demoDate(5, locale)).scaledFont(11).foregroundStyle(MirrorTheme.textSecondary)
                Text("Sat on the balcony after dinner. Finally quiet.").scaledFont(14).fixedSize(horizontal: false, vertical: true)
                if phase >= 3 {
                    Divider().padding(.vertical, 3)
                    Text("Linked from").scaledFont(11, weight: .bold).foregroundStyle(a.color)
                    Label { Text(verbatim: demoDate(0, locale)) } icon: { Image(systemName: "link") }
                        .scaledFont(12, weight: .medium).foregroundStyle(a.color)
                }
            }
            .demoCard(displayMode, highlighted: phase >= 3, accent: a.color)
            Spacer(minLength: 0)
        })
    }
}

/// Patterns' rows, counted from the moods shown: the weekday, its most common mood, "n of m".
private struct PatternsDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        var calendar = Calendar.current
        calendar.locale = locale
        let days = calendar.standaloneWeekdaySymbols
        let rows: [(String, String, Int, Int)] = [(days[0], "Grateful", 5, 7), (days[3], "Anxious", 3, 5), (days[5], "Joyful", 4, 6)]
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.topleft.filled").foregroundStyle(a.color)
                Text("Patterns").scaledFont(15, weight: .bold)
                Spacer(minLength: 0)
                Text("Year in Review").scaledFont(11, weight: .semibold).foregroundStyle(a.color)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(a.color.opacity(0.14), in: Capsule())
                    .opacity(phase >= 3 ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    let tint = MirrorTheme.moodColor(for: row.1)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(verbatim: row.0).scaledFont(13, weight: .medium).lineLimit(1)
                            Spacer(minLength: 6)
                            Circle().fill(tint).frame(width: 8, height: 8)
                            Text(LocalizedStringKey(row.1)).scaledFont(13, weight: .semibold)
                            Text("\(row.2) of \(row.3)").scaledFont(12).monospacedDigit().foregroundStyle(MirrorTheme.textSecondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MirrorTheme.inkBorder.opacity(0.6))
                                Capsule().fill(tint).frame(width: max(4, proxy.size.width * (phase >= 2 ? Double(row.2) / Double(row.3) : 0)))
                            }
                        }
                        .frame(height: 4)
                    }
                    .opacity(phase >= 1 ? (phase >= 3 && i != 0 ? 0.45 : 1) : 0.25)
                }
            }
            .demoCard(displayMode, accent: a.color)
            Spacer(minLength: 0)
        })
    }
}

/// A mood logged on the watch arrives on the iPhone.
private struct WatchDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        let moods = ["Peaceful", "Grateful", "Drained"]
        return AnyView(HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 5) {
                ForEach(moods, id: \.self) { mood in
                    let picked = phase >= 1 && mood == "Peaceful"
                    HStack(spacing: 5) {
                        Circle().fill(MirrorTheme.moodColor(for: mood)).frame(width: 8, height: 8)
                        Text(LocalizedStringKey(mood)).scaledFont(11, weight: .semibold).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if picked { Image(systemName: "checkmark").scaledFont(9, weight: .bold) }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).frame(height: 26)
                    .background(picked ? MirrorTheme.moodColor(for: mood).opacity(0.45) : Color.white.opacity(0.14), in: Capsule())
                }
            }
            .padding(10)
            .frame(width: 118, height: 128)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.gray.opacity(0.5), lineWidth: 3))
            .overlay(alignment: .bottom) { Image(systemName: "applewatch").scaledFont(12).foregroundStyle(MirrorTheme.textSecondary).offset(y: 22) }
            Image(systemName: "arrow.right")
                .scaledFont(16, weight: .bold)
                .foregroundStyle(a.color)
                .opacity(phase >= 2 ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "iphone").scaledFont(14).foregroundStyle(MirrorTheme.textSecondary)
                VStack(alignment: .leading, spacing: 5) {
                    moodPill("Peaceful", mode: displayMode)
                    Text(verbatim: Date().formatted(.dateTime.hour().minute().locale(locale)))
                        .scaledFont(11).foregroundStyle(MirrorTheme.textSecondary)
                }
                .demoCard(displayMode, highlighted: phase >= 3, accent: a.color)
                .opacity(phase >= 3 ? 1 : 0)
                Text("Walked to the market early.").scaledFont(12).lineLimit(2)
                    .demoCard(displayMode, accent: a.color)
            }
            .frame(maxWidth: .infinity)
        })
    }
}

/// A mood check-in, written one way into Apple Health as a State of Mind.
private struct HealthDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        let pink = Color(red: 0.98, green: 0.24, blue: 0.40)
        return AnyView(VStack(spacing: 18) {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "face.smiling").foregroundStyle(a.color).scaledFont(16)
                    moodPill("Grateful", mode: displayMode)
                    Text(verbatim: Date().formatted(.dateTime.hour().minute().locale(locale)))
                        .scaledFont(11).foregroundStyle(MirrorTheme.textSecondary)
                }
                .demoCard(displayMode, highlighted: phase == 1, accent: a.color)
                .frame(maxWidth: .infinity)
                Image(systemName: "arrow.right")
                    .scaledFont(18, weight: .bold)
                    .foregroundStyle(a.color)
                    .opacity(phase >= 2 ? 1 : 0.2)
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(pink).scaledFont(20)
                    Text("Apple Health").scaledFont(13, weight: .bold)
                    HStack(spacing: 5) {
                        Circle().fill(MirrorTheme.moodColor(for: "Grateful")).frame(width: 8, height: 8)
                        Text(LocalizedStringKey("Grateful")).scaledFont(12)
                    }
                }
                .demoCard(displayMode, highlighted: phase >= 3, accent: pink)
                .frame(maxWidth: .infinity)
                .opacity(phase >= 3 ? 1 : 0.3)
            }
            Spacer(minLength: 0)
        })
    }
}

/// Past reflections end with Show all, and the list keeps going.
private struct ShowAllDemo: View {
    let phase: Int
    @Environment(\.appDisplayMode) private var displayMode
    @Environment(\.locale) private var locale

    var body: some View {
        let a = DemoAccent(mode: displayMode)
        let lines: [LocalizedStringKey] = ["Sat on the balcony after dinner. Finally quiet.", "Deadline moved up again.",
                                           "Long call with Mum about the trip.", "Walked to the market early."]
        return AnyView(VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<6, id: \.self) { i in
                    let day = i + (phase >= 3 ? 14 : 1)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: demoDate(day, locale, weekday: false))
                            .scaledFont(11).foregroundStyle(MirrorTheme.textSecondary).monospacedDigit()
                            .frame(width: 52, alignment: .leading)
                        Text(lines[i % lines.count]).scaledFont(13, design: .serif).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .demoCard(displayMode, accent: a.color)
            .animation(.easeInOut(duration: 0.45), value: phase >= 3)
            Text("Show all (\(63))")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(phase == 2 ? Color.white : a.color)
                .padding(.horizontal, 14).frame(height: 30)
                .background(phase == 2 ? a.color : a.color.opacity(0.12), in: Capsule())
                .scaleEffect(phase == 2 ? 0.95 : 1)
                .opacity(phase >= 3 ? 0 : 1)
            Spacer(minLength: 0)
        })
    }
}

/// A blinking caret at the end of the text; steady with Reduce Motion.
private struct Caret: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if reduceMotion {
            bar(1)
        } else {
            TimelineView(.periodic(from: .now, by: 0.55)) { context in
                bar(Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0 ? 1 : 0)
            }
        }
    }
    private func bar(_ opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 18).opacity(opacity)
    }
}
