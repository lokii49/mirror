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
    static let demoIDs: Set<String> = ["smart-ask-search-310", "reflection-styles-310", "format-panel-310", "writing-310"]

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
                        .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .semibold) : .system(size: 13, weight: .semibold))
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
                            .font(.system(size: 16, weight: .semibold))
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
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(accent, in: buttonShape)
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
                            Text(card.title).font(MirrorTheme.mono(19, weight: .bold))
                        } else {
                            Text(card.title).font(.system(size: 24, weight: .bold, design: .rounded))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                    if card.tier != .free {
                        Text(card.tier.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(card.tier.color)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(card.tier.color.opacity(0.12), in: Capsule())
                    }

                    Text(card.body)
                        .font(.system(size: 15))
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
                .font(.system(size: 46, weight: .semibold))
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
                    .font(.system(size: 15, weight: .medium))
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
            Text(text).font(.system(size: 13)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if lit && phase >= 3 {
                Label("Found by meaning", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
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
                        .font(.system(size: 15, weight: .medium, design: .serif)).italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    Text("You seem calmer tonight.").opacity(style == 0 ? 1 : 0)
                    Text("What's underneath “Finally quiet”?").opacity(style == 2 ? 1 : 0)
                }
                .font(.system(size: 14))
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
            .font(.system(size: 13, weight: .semibold))
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
                if phase >= 3 { Text("•").font(.system(size: 18, weight: .bold)) }
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? accent : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(on ? accent.opacity(0.16) : MirrorTheme.bgBase,
                        in: RoundedRectangle(cornerRadius: displayMode == .sentinel ? 6 : 10, style: .continuous))
    }

    private func cell(_ glyph: String, on: Bool) -> some View {
        Text(verbatim: glyph)
            .font(.system(size: 15, weight: .bold))
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
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(accent.opacity(0.12), in: Capsule())
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("Draft saved")
            }
            .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(MirrorTheme.bgBase, in: Capsule()))
    }

    private var editorRow: AnyView {
        AnyView(HStack(alignment: .center, spacing: 1) {
            Text("Walked to the market early.")
                .font(.system(size: 16))
            Caret(color: accent)
            Spacer(minLength: 0)
        }
        .demoCard(displayMode, accent: accent))
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(MirrorTheme.bgBase, in: Capsule())
            .overlay(Capsule().stroke(MirrorTheme.inkBorder, lineWidth: 1))
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
