import SwiftUI
import SwiftData

struct BrainView: View {
    let viewModel: InsightViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDisplayMode) private var displayMode
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]

    @State private var subscriptionService = SubscriptionService.shared
    @State private var brainModel = BrainViewModel()
    @State private var showPaywall = false
    @State private var selectedNode: BrainNode?
    @State private var askPrefill: AskPrefill?
    @State private var is3D = true

    var body: some View {
        Group {
            if subscriptionService.isDeep {
                mainContent
            } else {
                blurredDeepPreview
            }
        }
        .background(MirrorTheme.bgBase)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        // Default nav bar hairline/background assumes a light backdrop —
        // against this view's always-dark canvas it just reads as a stray
        // line. Not load-bearing, safe to drop.
        .toolbarBackground(.hidden, for: .navigationBar)
        // Panning the graph starts drags from anywhere, including near the
        // left edge — the system's edge-swipe-to-pop gesture would hijack
        // those as "go back." Disabling it here (X button replaces back)
        // so a left-swipe inside the graph is just a pan, not a pop.
        .background(InteractivePopGestureDisabler())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.thinMaterial, in: Circle())
                }
            }
            if subscriptionService.isDeep, case .ready = brainModel.state {
                ToolbarItem(placement: .topBarTrailing) {
                    dimensionToggle
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView().environment(\.appDisplayMode, displayMode) }
        .sheet(item: $selectedNode) { node in
            BrainNodeDetailSheet(
                node: node,
                entries: brainModel.entries(for: node, in: entries),
                onAsk: { question in
                    selectedNode = nil
                    askPrefill = AskPrefill(question: question)
                }
            )
            .environment(\.appDisplayMode, displayMode)
        }
        .sheet(item: $askPrefill) { prefill in
            NavigationStack {
                AskView(viewModel: viewModel, initialQuestion: prefill.question)
            }
            .environment(\.appDisplayMode, displayMode)
        }
    }

    /// Custom instead of `Picker(.segmented)` — the system segmented style
    /// follows the device's light/dark appearance, not this view's canvas
    /// (always dark regardless of system setting), so it rendered with the
    /// wrong contrast. This is real frosted glass (`.thinMaterial`) tuned
    /// for the dark canvas specifically, matching the X button.
    private var dimensionToggle: some View {
        HStack(spacing: 2) {
            dimensionSegment(title: "3D", isSelected: is3D) { is3D = true }
            dimensionSegment(title: "2D", isSelected: !is3D) { is3D = false }
        }
        .padding(3)
        .background(.thinMaterial, in: Capsule())
    }

    private func dimensionSegment(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if displayMode == .sentinel {
                    Text(title).font(MirrorTheme.mono(12, weight: .semibold))
                } else {
                    Text(title).font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? (displayMode == .sentinel ? MirrorTheme.ember : .white) : .white.opacity(0.55))
            .frame(width: 44, height: 26)
            .background(
                isSelected ? (displayMode == .sentinel ? MirrorTheme.ember.opacity(0.16) : Color.white.opacity(0.22)) : Color.clear,
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) : AnyShape(Capsule())
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main content

    /// The very first build used to fire before this ever measured the real
    /// screen, baking a fallback-size layout in permanently (2D positions
    /// are computed once, not re-laid-out on resize) — squeezed into a box
    /// that didn't match the actual view. Measuring here first, before any
    /// state-dependent branch runs a rebuild, removes that race entirely.
    private var mainContent: some View {
        GeometryReader { geo in
            stateContent(size: geo.size)
        }
    }

    @ViewBuilder
    private func stateContent(size: CGSize) -> some View {
        switch brainModel.state {
        case .idle, .loading:
            VStack(spacing: 14) {
                ProgressView()
                Group {
                    if displayMode == .sentinel {
                        Text("MAPPING SIGNAL NETWORK…").font(MirrorTheme.mono(12, weight: .medium))
                    } else {
                        Text("Mapping your mind…").font(.system(size: 14))
                    }
                }
                .foregroundStyle(MirrorTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: taskKey(size)) {
                await brainModel.rebuild(entries: entries, canvasSize: size)
            }
        case .notEnoughEntries(let remaining):
            ScrollView {
                NeedsMoreEntriesCard(
                    remaining: remaining,
                    total: BrainViewModel.minimumEntries,
                    icon: "brain.head.profile",
                    iconColor: MirrorTheme.violet,
                    unlockLabel: "Brain View unlocks after 10 entries."
                )
                .padding(16)
            }
            .task(id: taskKey(size)) {
                await brainModel.rebuild(entries: entries, canvasSize: size)
            }
        case .empty:
            emptyCard
                .task(id: taskKey(size)) {
                    await brainModel.rebuild(entries: entries, canvasSize: size)
                }
        case .decryptionPending:
            decryptionPendingCard
                .task(id: taskKey(size)) {
                    await brainModel.rebuild(entries: entries, canvasSize: size)
                }
        case .ready(let graph):
            Group {
                if is3D {
                    Brain3DView(graph: graph) { node in
                        selectedNode = node
                    }
                } else {
                    BrainConstellationView(graph: graph) { node in
                        selectedNode = node
                    }
                    .id(graph.nodes.map(\.id).joined(separator: "|"))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .task(id: taskKey(size)) {
                await brainModel.rebuild(entries: entries, canvasSize: size)
            }
        }
    }

    /// Combines the entry-content fingerprint with the measured size so a
    /// rebuild re-fires both when entries change and when the real size
    /// first becomes known (or actually changes, e.g. rotation).
    private func taskKey(_ size: CGSize) -> String {
        "\(BrainViewModel.fingerprint(of: entries))-\(Int(size.width))x\(Int(size.height))"
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.12) : MirrorTheme.violetDim)
                    .frame(width: 72, height: 72)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
            }
            Group {
                if displayMode == .sentinel {
                    Text("NO RECURRING SIGNALS YET").font(MirrorTheme.mono(16, weight: .bold)).tracking(0.5)
                } else {
                    Text("No recurring themes yet").font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            Text("Mirror builds this map from names and topics\nthat repeat across your entries.")
                .font(.system(size: 14))
                .foregroundStyle(MirrorTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Distinct from `emptyCard` — entries exist and may well have recurring
    /// themes, they just couldn't be decrypted yet (e.g. right after unlock,
    /// before Keychain access or an iCloud Keychain sync is ready). Reopening
    /// once decryption succeeds resolves this on its own.
    private var decryptionPendingCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(displayMode == .sentinel ? MirrorTheme.ember.opacity(0.12) : MirrorTheme.violetDim)
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violetLight)
            }
            Group {
                if displayMode == .sentinel {
                    Text("SIGNALS NOT READABLE YET").font(MirrorTheme.mono(16, weight: .bold)).tracking(0.5)
                } else {
                    Text("Entries not readable yet").font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            Text(displayMode == .sentinel
                 ? "Couldn't decrypt some signals just now.\nReopen Constellation in a moment."
                 : "Mirror couldn't decrypt some entries just now.\nReopen Brain View in a moment.")
                .font(.system(size: 14))
                .foregroundStyle(MirrorTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Locked preview

    private var blurredDeepPreview: some View {
        ZStack {
            previewGraph
                .blur(radius: 8)
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color(red: 0.68, green: 0.56, blue: 1.0))
                }
                VStack(spacing: 8) {
                    Group {
                        if displayMode == .sentinel {
                            Text("CONSTELLATION").font(MirrorTheme.mono(20, weight: .bold)).tracking(1)
                        } else {
                            Text("Brain View").font(.system(size: 22, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(.white)
                    Text("A living map of your people, places,\nand themes is part of Deep.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Button { showPaywall = true } label: {
                    Group {
                        if displayMode == .sentinel {
                            Text("UNLOCK WITH DEEP").font(MirrorTheme.mono(14, weight: .bold))
                        } else {
                            Text("Unlock with Deep").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: displayMode == .sentinel ? [MirrorTheme.ember, .orange] : [MirrorTheme.violet, Color.indigo], startPoint: .leading, endPoint: .trailing),
                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) : AnyShape(Capsule())
                    )
                }
                .buttonStyle(.plain)
                .shadow(color: (displayMode == .sentinel ? MirrorTheme.ember : MirrorTheme.violet).opacity(0.4), radius: 16, x: 0, y: 6)
            }
            .padding(28)
            .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 28)
            .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10))
    }

    /// Static mock graph rendered behind the lock card — no real data.
    /// Matches BrainConstellationView's flat, plain-node styling.
    private var previewGraph: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let mock: [(x: CGFloat, y: CGFloat, r: CGFloat, score: Double?)] = [
                (0.30, 0.30, 18, 2.0), (0.70, 0.28, 15, 4.8),
                (0.22, 0.55, 12, 1.5), (0.66, 0.55, 20, 3.4), (0.45, 0.66, 11, nil),
                (0.80, 0.44, 10, 2.6), (0.36, 0.78, 13, 4.5), (0.60, 0.80, 9, 3.0),
                (0.15, 0.40, 9, nil), (0.85, 0.66, 11, 1.8), (0.52, 0.20, 10, 4.0)
            ]
            Canvas { context, _ in
                for node in mock {
                    let p = CGPoint(x: node.x * w, y: node.y * h)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: p)
                    context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.7)
                }
                let hubColor = displayMode == .sentinel ? MirrorTheme.ember : Color(red: 0.62, green: 0.5, blue: 1.0)
                let hubRect = CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)
                context.fill(Circle().path(in: hubRect), with: .color(hubColor))
                for node in mock {
                    let p = CGPoint(x: node.x * w, y: node.y * h)
                    let color = node.score.map { MirrorTheme.moodScoreColor($0) } ?? hubColor.opacity(0.75)
                    let rect = CGRect(x: p.x - node.r / 2, y: p.y - node.r / 2, width: node.r, height: node.r)
                    context.fill(Circle().path(in: rect), with: .color(color))
                }
            }
            .background(Color(red: 0.09, green: 0.09, blue: 0.10))
        }
    }
}

// MARK: - Ask prefill wrapper

private struct AskPrefill: Identifiable {
    let id = UUID()
    let question: String
}

// MARK: - Node detail sheet

private struct BrainNodeDetailSheet: View {
    let node: BrainNode
    let entries: [Entry]
    let onAsk: (String) -> Void
    @Environment(\.appDisplayMode) private var displayMode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    askButton
                    entryList
                }
                .padding(16)
            }
            .background(MirrorTheme.bgBase)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var typeIcon: String {
        switch node.type {
        case .person: return "person.fill"
        case .place: return "mappin.circle.fill"
        case .keyword, .theme: return "number"
        }
    }

    private var nodeColor: Color {
        node.avgMoodScore.map { MirrorTheme.moodScoreColor($0) } ?? MirrorTheme.violet.opacity(0.55)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(nodeColor.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: typeIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(nodeColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if displayMode == .sentinel {
                        Text(node.label.uppercased()).font(MirrorTheme.mono(19, weight: .bold)).tracking(0.5)
                    } else {
                        Text(node.label).font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                }
                Group {
                    if displayMode == .sentinel {
                        Text(node.mentionCount == 1 ? "1 SIGNAL" : "\(node.mentionCount) SIGNALS").font(MirrorTheme.mono(11, weight: .medium))
                    } else {
                        Text(node.mentionCount == 1 ? "1 entry" : "\(node.mentionCount) entries").font(.system(size: 13, weight: .medium))
                    }
                }
                .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer()
            if let score = node.avgMoodScore {
                Text(String(format: "%.1f/5", score))
                    .font(displayMode == .sentinel ? MirrorTheme.mono(12, weight: .bold) : .system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        MirrorTheme.moodScoreColor(score),
                        in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) : AnyShape(Capsule())
                    )
            }
        }
    }

    private var askButton: some View {
        Button {
            onAsk(String(localized: "What have I written about \(node.label)?"))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: displayMode == .sentinel ? "waveform.badge.magnifyingglass" : "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                Group {
                    if displayMode == .sentinel {
                        Text("QUERY SIGNAL: \(node.label.uppercased())").font(MirrorTheme.mono(13, weight: .semibold))
                    } else {
                        Text("Ask Mirror about \(node.label)").font(.system(size: 15, weight: .semibold))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                displayMode == .sentinel ? AnyShapeStyle(MirrorTheme.ember) : AnyShapeStyle(MirrorTheme.accentGradient),
                in: displayMode == .sentinel ? AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) : AnyShape(Capsule())
            )
        }
        .buttonStyle(.plain)
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entries, id: \.id) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(entry.mood.map { MirrorTheme.moodColor(for: $0) } ?? MirrorTheme.textTertiary)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Group {
                            if displayMode == .sentinel {
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                                    .font(MirrorTheme.mono(11, weight: .semibold))
                            } else {
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundStyle(MirrorTheme.textSecondary)
                        Text(String(entry.insightContext.prefix(120)))
                            .font(.system(size: 14))
                            .foregroundStyle(MirrorTheme.textPrimary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .themedCard(cornerRadius: 16)
            }
        }
    }
}

// MARK: - Interactive pop gesture disabler

/// SwiftUI has no direct handle on `UINavigationController`'s edge-swipe-to-
/// pop gesture. This finds it via the view controller hierarchy and turns
/// it off while installed, back on when removed, so panning the graph from
/// near the left edge isn't swallowed by the system as "go back."
private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            controller.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}
