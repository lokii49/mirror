import SwiftUI
import SwiftData

struct BrainView: View {
    let viewModel: InsightViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $selectedNode) { node in
            BrainNodeDetailSheet(
                node: node,
                entries: brainModel.entries(for: node, in: entries),
                onAsk: { question in
                    selectedNode = nil
                    askPrefill = AskPrefill(question: question)
                }
            )
        }
        .sheet(item: $askPrefill) { prefill in
            NavigationStack {
                AskView(viewModel: viewModel, initialQuestion: prefill.question)
            }
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

    private func dimensionSegment(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .frame(width: 44, height: 26)
                .background(isSelected ? Color.white.opacity(0.22) : Color.clear, in: Capsule())
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
                Text("Mapping your mind…")
                    .font(.system(size: 14))
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
                    .fill(MirrorTheme.violetDim)
                    .frame(width: 72, height: 72)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(MirrorTheme.violetLight)
            }
            Text("No recurring themes yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Mirror builds this map from names and topics\nthat repeat across your entries.")
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
                    Text("Brain View")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("A living map of your people, places,\nand themes is part of Deep.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Button { showPaywall = true } label: {
                    Text("Unlock with Deep")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [MirrorTheme.violet, Color.indigo], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .shadow(color: MirrorTheme.violet.opacity(0.4), radius: 16, x: 0, y: 6)
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
                let hubRect = CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)
                context.fill(Circle().path(in: hubRect), with: .color(Color(red: 0.62, green: 0.5, blue: 1.0)))
                for node in mock {
                    let p = CGPoint(x: node.x * w, y: node.y * h)
                    let color = node.score.map { MirrorTheme.moodScoreColor($0) } ?? Color(red: 0.62, green: 0.5, blue: 1.0).opacity(0.75)
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
                Text(node.label)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(node.mentionCount == 1 ? "1 entry" : "\(node.mentionCount) entries")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MirrorTheme.textSecondary)
            }
            Spacer()
            if let score = node.avgMoodScore {
                Text(String(format: "%.1f/5", score))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MirrorTheme.moodScoreColor(score), in: Capsule())
            }
        }
    }

    private var askButton: some View {
        Button {
            onAsk(String(localized: "What have I written about \(node.label)?"))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Ask Mirror about \(node.label)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(MirrorTheme.accentGradient, in: Capsule())
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
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MirrorTheme.textSecondary)
                        Text(String(entry.insightContext.prefix(120)))
                            .font(.system(size: 14))
                            .foregroundStyle(MirrorTheme.textPrimary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .inkSurface(cornerRadius: 16)
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
