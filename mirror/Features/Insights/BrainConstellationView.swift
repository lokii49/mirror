import SwiftUI

/// Obsidian-style graph: flat dark canvas, plain solid nodes, thin neutral
/// links. Labels aren't fixed — they progressively reveal as you zoom in
/// (screen-space size crosses a legibility threshold), same as Obsidian's
/// own graph view, so overview stays clean and detail arrives on demand.
struct BrainConstellationView: View {
    let graph: BrainGraph
    let onNodeTap: (BrainNode) -> Void
    @Environment(\.appDisplayMode) private var displayMode
    private var hubColor: Color { displayMode == .sentinel ? MirrorTheme.ember : Self.violetHubColor }

    @State private var steadyScale: CGFloat = 1
    @State private var steadyOffset: CGSize = .zero
    @State private var selectedNodeID: String?
    /// True once the user has actually pinched/panned — until then, every
    /// appear/resize keeps re-fitting instead of locking in on the first
    /// call. onAppear vs onChange(size) firing order isn't guaranteed, and
    /// GeometryReader can report a transitional size before settling; a
    /// one-shot "fit once" guard could permanently lock in whichever fired
    /// first, good or bad. Re-fitting until real interaction removes that
    /// race instead of just hiding it behind a size sanity check.
    @State private var userInteracted = false

    private let minScale: CGFloat = 0.3
    private let maxScale: CGFloat = 5.0
    /// Screen-space radius (pt) a node must reach before its label appears.
    private let labelRevealRadius: CGFloat = 13
    /// Always-visible baseline so the overview isn't completely unlabeled.
    private let alwaysLabeledCount = 3

    private static let background = Color(red: 0.09, green: 0.09, blue: 0.10)
    private static let linkColor = Color.white.opacity(0.16)
    private static let linkColorNearHub = Color.white.opacity(0.32)
    private static let linkColorHighlighted = Color.white.opacity(0.9)
    private static let violetHubColor = Color(red: 0.62, green: 0.5, blue: 1.0)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            Canvas { context, _ in
                context.translateBy(x: center.x + steadyOffset.width, y: center.y + steadyOffset.height)
                context.scaleBy(x: steadyScale, y: steadyScale)
                context.translateBy(x: -center.x, y: -center.y)

                var positions: [String: CGPoint] = [:]
                for node in graph.nodes { positions[node.id] = node.position }

                // Links first, under everything. Ones touching the selected
                // node draw brighter and thicker so its connections read at
                // a glance instead of blending into the rest of the web.
                for node in graph.nodes {
                    let isSelected = node.id == selectedNodeID
                    var path = Path()
                    path.move(to: graph.hubPosition)
                    path.addLine(to: node.position)
                    context.stroke(
                        path,
                        with: .color(isSelected ? Self.linkColorHighlighted : Self.linkColorNearHub),
                        style: StrokeStyle(lineWidth: (isSelected ? 1.8 : 0.7) / steadyScale)
                    )
                }
                for edge in graph.edges {
                    guard let a = positions[edge.a], let b = positions[edge.b] else { continue }
                    let isSelected = edge.a == selectedNodeID || edge.b == selectedNodeID
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(
                        path,
                        with: .color(isSelected ? Self.linkColorHighlighted : Self.linkColor),
                        style: StrokeStyle(lineWidth: (isSelected ? 1.6 : 0.6) / steadyScale)
                    )
                }

                // Hub.
                let hubRadius: CGFloat = 15
                let hubCenter = graph.hubPosition
                let hubRect = CGRect(x: hubCenter.x - hubRadius, y: hubCenter.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
                context.fill(Circle().path(in: hubRect), with: .color(hubColor))
                context.stroke(Circle().path(in: hubRect), with: .color(.white.opacity(0.4)), lineWidth: 1 / steadyScale)
                drawLabel(&context, text: String(localized: "You"), at: CGPoint(x: hubCenter.x, y: hubCenter.y + hubRadius + 12), bold: true)

                // Nodes + progressively revealed labels.
                for (index, node) in graph.nodes.enumerated() {
                    let color = nodeColor(node)
                    let rect = CGRect(
                        x: node.position.x - node.radius, y: node.position.y - node.radius,
                        width: node.radius * 2, height: node.radius * 2
                    )
                    context.fill(Circle().path(in: rect), with: .color(color))
                    context.stroke(
                        Circle().path(in: rect),
                        with: .color(.white.opacity(node.id == selectedNodeID ? 0.9 : 0.25)),
                        lineWidth: (node.id == selectedNodeID ? 2 : 1) / steadyScale
                    )

                    let onScreenRadius = node.radius * steadyScale
                    let alwaysShow = index < alwaysLabeledCount || node.id == selectedNodeID
                    guard alwaysShow || onScreenRadius >= labelRevealRadius else { continue }
                    drawLabel(&context, text: node.label, at: CGPoint(x: node.position.x, y: node.position.y + node.radius + 12))
                }
            }
            .background(Self.background)
            .onAppear { fitToContent(size: size, center: center) }
            .onChange(of: size) { _, newSize in fitToContent(size: newSize, center: CGPoint(x: newSize.width / 2, y: newSize.height / 2)) }

            // UIKit overlay instead of SwiftUI's MagnifyGesture/DragGesture:
            // MagnifyGesture.Value carries no location, so pinch-zoom could
            // only ever pivot on a fixed point (viewport center) — anything
            // off-center visibly drifted away from your fingers instead of
            // zooming toward them. UIPinchGestureRecognizer has a real
            // location(in:), which is what the anchor math below needs.
            PanPinchTapOverlay(
                onPan: { delta in
                    userInteracted = true
                    steadyOffset.width += delta.width
                    steadyOffset.height += delta.height
                },
                onPinch: { factor, location in
                    userInteracted = true
                    let worldPoint = inverseTransform(location, center: center)
                    let newScale = min(max(steadyScale * factor, minScale), maxScale)
                    steadyOffset = CGSize(
                        width: location.x - newScale * (worldPoint.x - center.x) - center.x,
                        height: location.y - newScale * (worldPoint.y - center.y) - center.y
                    )
                    steadyScale = newScale
                },
                onTap: { location in
                    let p = inverseTransform(location, center: center)
                    var best: BrainNode?
                    var bestDist: CGFloat = .greatestFiniteMagnitude
                    for node in graph.nodes {
                        let dx = node.position.x - p.x
                        let dy = node.position.y - p.y
                        let dist = (dx * dx + dy * dy).squareRoot()
                        guard dist <= node.radius + 22 / steadyScale, dist < bestDist else { continue }
                        best = node
                        bestDist = dist
                    }
                    if let best {
                        selectedNodeID = best.id
                        onNodeTap(best)
                    }
                }
            )

            zoomControls
        }
    }

    private func drawLabel(_ context: inout GraphicsContext, text: String, at point: CGPoint, bold: Bool = false) {
        let label = Text(text)
            .font(.system(size: (bold ? 13 : 11) / steadyScale, weight: bold ? .bold : .medium))
        // Manual dark outline (draw offset in black, then the real text on
        // top) — legible over any node color without a boxy chip background.
        let shadowColor = Text(text)
            .font(.system(size: (bold ? 13 : 11) / steadyScale, weight: bold ? .bold : .medium))
            .foregroundColor(.black.opacity(0.85))
        let d = 0.8 / steadyScale
        for offset in [CGPoint(x: -d, y: 0), CGPoint(x: d, y: 0), CGPoint(x: 0, y: -d), CGPoint(x: 0, y: d)] {
            context.draw(shadowColor, at: CGPoint(x: point.x + offset.x, y: point.y + offset.y))
        }
        context.draw(label.foregroundColor(.white), at: point)
    }

    /// Opens zoomed out enough to fit the whole layout with the hub kept
    /// exactly centered (not the content bounding box, which can be
    /// lopsided for an asymmetric graph and would land the hub in a
    /// corner) — the world is laid out larger than the screen on purpose
    /// (room to avoid overlap), so this is what makes the initial view
    /// still show everything at once, centered the same way every time.
    private func fitToContent(size: CGSize, center: CGPoint) {
        // Re-fits on every appear/resize until the user actually interacts
        // (see `userInteracted`) — a degenerate size just no-ops rather
        // than locking in garbage, since there's no "only once" guard left
        // to accidentally freeze on a bad early call.
        guard !userInteracted, size.width > 20, size.height > 20, !graph.nodes.isEmpty else { return }
        let hub = graph.hubPosition
        var halfWidth: CGFloat = 1, halfHeight: CGFloat = 1
        for node in graph.nodes {
            halfWidth = max(halfWidth, abs(node.position.x - hub.x) + node.radius)
            halfHeight = max(halfHeight, abs(node.position.y - hub.y) + node.radius)
        }
        let fitScale = min(size.width / (2 * halfWidth), size.height / (2 * halfHeight)) * 0.88
        let clamped = min(max(fitScale, minScale), maxScale)
        steadyScale = clamped
        steadyOffset = CGSize(
            width: (center.x - hub.x) * clamped,
            height: (center.y - hub.y) * clamped
        )
    }

    private func inverseTransform(_ screen: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(
            x: (screen.x - center.x - steadyOffset.width) / steadyScale + center.x,
            y: (screen.y - center.y - steadyOffset.height) / steadyScale + center.y
        )
    }

    private func nodeColor(_ node: BrainNode) -> Color {
        node.avgMoodScore.map { MirrorTheme.moodScoreColor($0) } ?? hubColor.opacity(0.75)
    }

    private var zoomControls: some View {
        VStack(spacing: 10) {
            zoomButton(systemName: "plus") {
                steadyScale = min(steadyScale * 1.35, maxScale)
            }
            zoomButton(systemName: "minus") {
                steadyScale = max(steadyScale / 1.35, minScale)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func zoomButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            userInteracted = true
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Pan + pinch + tap via real UIKit gesture recognizers rather than
/// SwiftUI's DragGesture/MagnifyGesture/onTapGesture — SwiftUI's
/// MagnifyGesture in particular carries no location, so it can't drive a
/// pinch-to-a-point anchor. UIPinchGestureRecognizer's `location(in:)` can.
private struct PanPinchTapOverlay: UIViewRepresentable {
    let onPan: (CGSize) -> Void
    let onPinch: (CGFloat, CGPoint) -> Void
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = coordinator
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)

        coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.onPinch = onPinch
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan, onPinch: onPinch, onTap: onTap)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPan: (CGSize) -> Void
        var onPinch: (CGFloat, CGPoint) -> Void
        var onTap: (CGPoint) -> Void
        weak var view: UIView?

        init(onPan: @escaping (CGSize) -> Void, onPinch: @escaping (CGFloat, CGPoint) -> Void, onTap: @escaping (CGPoint) -> Void) {
            self.onPan = onPan
            self.onPinch = onPinch
            self.onTap = onTap
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view else { return }
            let t = gr.translation(in: view)
            onPan(CGSize(width: t.x, height: t.y))
            gr.setTranslation(.zero, in: view)
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard let view else { return }
            onPinch(gr.scale, gr.location(in: view))
            gr.scale = 1
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let view else { return }
            onTap(gr.location(in: view))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
