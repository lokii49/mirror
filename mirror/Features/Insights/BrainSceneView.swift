import SwiftUI
import SceneKit
import Combine

/// Bridges the +/- zoom buttons (SwiftUI) to the manual camera rig inside
/// the SceneKit coordinator, which owns yaw/pitch/distance directly.
final class BrainCameraController: ObservableObject {
    let zoomIn = PassthroughSubject<Void, Never>()
    let zoomOut = PassthroughSubject<Void, Never>()
}

/// Self-contained 3D graph: real matte spheres (not glow sprites), orbit
/// camera, and depth conveyed by SceneKit's built-in fog rather than any
/// glow/bloom — dimming and desaturating far nodes toward the background
/// instead of blowing them out. Composes its own zoom controls to match
/// BrainConstellationView's call shape.
struct Brain3DView: View {
    let graph: BrainGraph
    let onNodeTap: (BrainNode) -> Void

    @StateObject private var cameraController = BrainCameraController()

    var body: some View {
        ZStack {
            BrainSceneView(graph: graph, cameraController: cameraController, onNodeTap: onNodeTap)
                .id(graph.nodes.map(\.id).joined(separator: "|"))
                .ignoresSafeArea()
            zoomControls
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 10) {
            zoomButton(systemName: "plus") { cameraController.zoomIn.send(()) }
            zoomButton(systemName: "minus") { cameraController.zoomOut.send(()) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func zoomButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

private struct BrainSceneView: UIViewRepresentable {
    let graph: BrainGraph
    let cameraController: BrainCameraController
    let onNodeTap: (BrainNode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(graph: graph, onNodeTap: onNodeTap)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let coordinator = context.coordinator
        view.scene = coordinator.scene
        view.pointOfView = coordinator.cameraNode
        view.backgroundColor = Coordinator.background
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.delegate = coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        // Two-finger pan shifts the look-at target instead of orbiting, so
        // the hub isn't permanently pinned to the exact screen center —
        // matches the free panning the 2D view already has.
        let twoFingerPan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.delegate = coordinator
        view.addGestureRecognizer(twoFingerPan)
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = coordinator
        view.addGestureRecognizer(pinch)
        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(tap)

        coordinator.view = view
        coordinator.subscribe(to: cameraController)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        private let graph: BrainGraph
        private let onNodeTap: (BrainNode) -> Void
        private var graphNodeByID: [String: BrainNode] = [:]
        private var labelInfo: [(container: SCNNode, alwaysVisible: Bool, sceneRadius: Double)] = []
        private var cancellables = Set<AnyCancellable>()
        weak var view: SCNView?

        /// Lines touching each node id (its spoke + any co-occurrence
        /// edges), so a tap can brighten just that node's connections.
        private var linesTouchingNode: [String: [SCNNode]] = [:]
        private var baseLineAlpha: [ObjectIdentifier: CGFloat] = [:]
        private var highlightedLines: [SCNNode] = []
        /// The visible sphere per node id — a tap can resolve to the larger
        /// invisible hit-target instead, so pulse/selection feedback always
        /// looks this up rather than animating whichever node was hit.
        private var sphereNodeByID: [String: SCNNode] = [:]

        private var yaw = -0.5
        private var pitch = 0.28
        private var distance = 6.4
        /// World-space look-at target, shifted by two-finger pan — the hub
        /// sits at the origin, so this is what frees it from always being
        /// screen-center; orbiting still revolves around this point.
        private var targetOffset = SCNVector3Zero
        private let minDistance = 2.8
        private let maxDistance = 14.0
        private let defaultYaw = -0.5
        private let defaultPitch = 0.28
        private let defaultDistance = 6.4
        private var autoRotateEnabled = true

        static let background = UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        private static let hubColor = UIColor(red: 0.62, green: 0.5, blue: 1.0, alpha: 1)
        /// Any bit outside SceneKit's default (1) so tap hit-testing can
        /// exclude labels via a category mask instead of relying on opacity.
        private static let labelCategory = 2

        init(graph: BrainGraph, onNodeTap: @escaping (BrainNode) -> Void) {
            self.graph = graph
            self.onNodeTap = onNodeTap
            super.init()
            for node in graph.nodes { graphNodeByID[node.id] = node }
            buildScene()
            updateCameraPosition()
        }

        func subscribe(to controller: BrainCameraController) {
            controller.zoomIn.sink { [weak self] in self?.animatedZoom(factor: 0.78) }.store(in: &cancellables)
            controller.zoomOut.sink { [weak self] in self?.animatedZoom(factor: 1.28) }.store(in: &cancellables)
        }

        // MARK: Scene construction

        private func buildScene() {
            scene.background.contents = Self.background
            scene.fogColor = Self.background
            scene.fogDensityExponent = 1.0

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 50
            cameraNode.camera?.zNear = 0.05
            cameraNode.camera?.zFar = 40
            scene.rootNode.addChildNode(cameraNode)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 420
            key.light?.color = UIColor.white
            key.eulerAngles = SCNVector3(-Float.pi / 3.4, Float.pi / 5, 0)
            scene.rootNode.addChildNode(key)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 430
            ambient.light?.color = UIColor(white: 0.78, alpha: 1)
            scene.rootNode.addChildNode(ambient)

            // Hub, matte sphere, no glow.
            let hubGeometry = SCNSphere(radius: 0.22)
            let hubMaterial = SCNMaterial()
            hubMaterial.lightingModel = .lambert
            hubMaterial.diffuse.contents = Self.hubColor
            hubGeometry.materials = [hubMaterial]
            let hubNode = SCNNode(geometry: hubGeometry)
            hubNode.name = "__hub__"
            scene.rootNode.addChildNode(hubNode)
            addLabel(text: "You", to: hubNode, sceneRadius: 0.22, alwaysVisible: true, bold: true)

            var positionByID: [String: SCNVector3] = [:]
            for node in graph.nodes {
                positionByID[node.id] = SCNVector3(Float(node.position3.x), Float(node.position3.y), Float(node.position3.z))
            }

            // Spokes hub → node, faint.
            for node in graph.nodes {
                guard let p = positionByID[node.id] else { continue }
                let line = lineNode(from: SCNVector3Zero, to: p, alpha: 0.34)
                scene.rootNode.addChildNode(line)
                registerLine(line, alpha: 0.34, touching: [node.id])
            }
            // Co-occurrence edges, fainter still.
            for edge in graph.edges {
                guard let a = positionByID[edge.a], let b = positionByID[edge.b] else { continue }
                let line = lineNode(from: a, to: b, alpha: 0.20)
                scene.rootNode.addChildNode(line)
                registerLine(line, alpha: 0.20, touching: [edge.a, edge.b])
            }

            // Nodes — graph.nodes is already ranked by frequency desc.
            for (index, node) in graph.nodes.enumerated() {
                guard let p = positionByID[node.id] else { continue }
                let sceneRadius = 0.035 + Double(node.radius) / 230.0
                let geometry = SCNSphere(radius: sceneRadius)
                let material = SCNMaterial()
                material.lightingModel = .lambert
                material.diffuse.contents = nodeColor(node)
                geometry.materials = [material]
                let sphereNode = SCNNode(geometry: geometry)
                sphereNode.name = node.id
                sphereNode.position = p
                scene.rootNode.addChildNode(sphereNode)
                sphereNode.addChildNode(hitTargetNode(id: node.id, visualRadius: sceneRadius))
                sphereNodeByID[node.id] = sphereNode
                addLabel(text: node.label, to: sphereNode, sceneRadius: sceneRadius, alwaysVisible: index < 3, bold: false)
            }
        }

        /// Invisible, larger companion sphere so small nodes stay easy to
        /// tap without growing visually — decouples touch target size from
        /// the composition's node size. Fully transparent geometry still
        /// hit-tests in SceneKit (same fact that caused the label tap bug,
        /// used deliberately here).
        private func hitTargetNode(id: String, visualRadius: Double) -> SCNNode {
            let geometry = SCNSphere(radius: visualRadius + 0.2)
            let material = SCNMaterial()
            material.transparency = 0
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = false
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = id
            return node
        }

        private func lineNode(from a: SCNVector3, to b: SCNVector3, alpha: CGFloat) -> SCNNode {
            let source = SCNGeometrySource(vertices: [a, b])
            let element = SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.white.withAlphaComponent(alpha)
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.categoryBitMask = Self.labelCategory
            return node
        }

        private func registerLine(_ line: SCNNode, alpha: CGFloat, touching ids: [String]) {
            baseLineAlpha[ObjectIdentifier(line)] = alpha
            for id in ids { linesTouchingNode[id, default: []].append(line) }
        }

        /// Brightens the lines touching `id` and reverts whatever was
        /// highlighted before, so only the selected node's connections
        /// stand out from the rest of the web.
        private func highlightLines(for id: String) {
            for line in highlightedLines {
                guard let base = baseLineAlpha[ObjectIdentifier(line)] else { continue }
                line.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(base)
            }
            highlightedLines = linesTouchingNode[id] ?? []
            for line in highlightedLines {
                line.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.95)
            }
        }

        private func addLabel(text: String, to parent: SCNNode, sceneRadius: Double, alwaysVisible: Bool, bold: Bool) {
            let scnText = SCNText(string: text, extrusionDepth: 0)
            scnText.font = UIFont.systemFont(ofSize: bold ? 1.15 : 1.0, weight: bold ? .bold : .semibold)
            scnText.flatness = 0.2
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor.white
            material.isDoubleSided = true
            scnText.materials = [material]

            let textNode = SCNNode(geometry: scnText)
            let (minBound, maxBound) = scnText.boundingBox
            let centeringOffset = (maxBound.x - minBound.x) / 2
            textNode.position = SCNVector3(-centeringOffset, 0, 0)

            let container = SCNNode()
            container.name = "__label__"
            container.addChildNode(textNode)
            container.position = SCNVector3(0, Float(sceneRadius) + 0.09, 0)
            container.constraints = [SCNBillboardConstraint()]
            container.opacity = alwaysVisible ? 1 : 0
            container.scale = SCNVector3(0.001, 0.001, 0.001)
            // Opacity 0 still hit-tests by default in SceneKit — exclude
            // labels from the tap ray entirely so a not-yet-revealed label
            // can never swallow a tap meant for the sphere behind it.
            container.categoryBitMask = Self.labelCategory
            parent.addChildNode(container)

            labelInfo.append((container: container, alwaysVisible: alwaysVisible, sceneRadius: sceneRadius))
        }

        private func nodeColor(_ node: BrainNode) -> UIColor {
            if let score = node.avgMoodScore {
                return UIColor(MirrorTheme.moodScoreColor(score))
            }
            return Self.blend(Self.hubColor, Self.background, 0.15)
        }

        private static func blend(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
            var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
            b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
        }

        // MARK: Camera rig

        private func updateCameraPosition() {
            let x = Float(distance * cos(pitch) * sin(yaw)) + targetOffset.x
            let y = Float(distance * sin(pitch)) + targetOffset.y
            let z = Float(distance * cos(pitch) * cos(yaw)) + targetOffset.z
            cameraNode.position = SCNVector3(x, y, z)
            cameraNode.look(at: targetOffset, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }

        /// Right/up basis vectors for the current orbit orientation, so a
        /// screen-space pan drag translates into the correct world-space
        /// shift regardless of which way the camera is currently facing.
        private func cameraBasis() -> (right: SCNVector3, up: SCNVector3) {
            let forward = SCNVector3(
                Float(-cos(pitch) * sin(yaw)),
                Float(-sin(pitch)),
                Float(-cos(pitch) * cos(yaw))
            )
            let worldUp = SCNVector3(0, 1, 0)
            var right = Self.cross(forward, worldUp)
            let rLen = Self.length(right)
            right = rLen > 0.0001 ? Self.scale(right, 1 / rLen) : SCNVector3(1, 0, 0)
            let up = Self.cross(right, forward)
            return (right, up)
        }

        private static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        }
        private static func length(_ v: SCNVector3) -> Float { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }
        private static func scale(_ v: SCNVector3, _ s: Float) -> SCNVector3 { SCNVector3(v.x * s, v.y * s, v.z * s) }
        private static func add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }

        private func animatedZoom(factor: Double) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            distance = max(minDistance, min(maxDistance, distance * factor))
            updateCameraPosition()
            SCNTransaction.commit()
        }

        @objc func handleTwoFingerPan(_ gr: UIPanGestureRecognizer) {
            guard let view else { return }
            let translation = gr.translation(in: view)
            let (right, up) = cameraBasis()
            let panScale = Float(distance) * 0.0022
            targetOffset = Self.add(targetOffset, Self.scale(right, -Float(translation.x) * panScale))
            targetOffset = Self.add(targetOffset, Self.scale(up, Float(translation.y) * panScale))
            gr.setTranslation(.zero, in: view)
            updateCameraPosition()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view else { return }
            let translation = gr.translation(in: view)
            yaw -= Double(translation.x) * 0.0055
            pitch = max(-1.4, min(1.4, pitch + Double(translation.y) * 0.0055))
            gr.setTranslation(.zero, in: view)
            updateCameraPosition()
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard let view else { return }
            let oldDistance = distance
            let newDistance = max(minDistance, min(maxDistance, distance / Double(gr.scale)))
            // A pure dolly (camera distance change) only zooms toward the
            // lookAt target — anything off-center in the pinch appears to
            // drift instead of zooming toward where you actually pinched.
            // Nudge the target toward the pinch point, proportional to how
            // much we're zooming, so it approximates a real zoom-to-cursor.
            let location = gr.location(in: view)
            let bounds = view.bounds
            if bounds.width > 0, bounds.height > 0 {
                let dx = Double((location.x - bounds.midX) / (bounds.width / 2))
                let dy = Double((location.y - bounds.midY) / (bounds.height / 2))
                let (right, up) = cameraBasis()
                let pull = Float((oldDistance - newDistance) * 0.5)
                targetOffset = Self.add(targetOffset, Self.scale(right, Float(dx) * pull))
                targetOffset = Self.add(targetOffset, Self.scale(up, Float(-dy) * pull))
            }
            distance = newDistance
            gr.scale = 1
            updateCameraPosition()
        }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            yaw = defaultYaw
            pitch = defaultPitch
            distance = defaultDistance
            targetOffset = SCNVector3Zero
            updateCameraPosition()
            SCNTransaction.commit()
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gr.location(in: view)
            let hits = view.hitTest(location, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
                SCNHitTestOption.categoryBitMask: 1,
            ])
            guard let hit = hits.first, let resolved = resolvedNode(from: hit.node) else { return }
            autoRotateEnabled = false
            guard resolved.name != "__hub__", let id = resolved.name, let node = graphNodeByID[id] else { return }
            let pulse = SCNAction.sequence([.scale(to: 1.35, duration: 0.12), .scale(to: 1.0, duration: 0.18)])
            (sphereNodeByID[id] ?? resolved).runAction(pulse)
            highlightLines(for: id)
            onNodeTap(node)
        }

        /// Hit-test resolves to the sphere/text child geometry, not the
        /// named container — walk up, but a "__label__" ancestor isn't a
        /// terminal match, only a node id or the hub is. Skip past it.
        private func resolvedNode(from start: SCNNode) -> SCNNode? {
            var current: SCNNode? = start
            while let n = current {
                if n.name == "__hub__" { return n }
                if let name = n.name, name != "__label__", graphNodeByID[name] != nil { return n }
                current = n.parent
            }
            return nil
        }

        // MARK: Per-frame — label reveal/scale + fog band, both distance-driven

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if autoRotateEnabled {
                yaw += 0.0009
                updateCameraPosition()
            }
            let camPos = cameraNode.position
            for info in labelInfo {
                let p = info.container.worldPosition
                let dx = Double(p.x - camPos.x), dy = Double(p.y - camPos.y), dz = Double(p.z - camPos.z)
                let d = (dx * dx + dy * dy + dz * dz).squareRoot()
                let scale = Float(max(0.012, min(0.05, 0.028 * d)))
                info.container.scale = SCNVector3(scale, scale, scale)
                if !info.alwaysVisible {
                    let revealNear = info.sceneRadius * 11
                    let revealFar = info.sceneRadius * 26
                    let t = (revealFar - d) / max(0.0001, revealFar - revealNear)
                    info.container.opacity = CGFloat(max(0, min(1, t)))
                }
            }
            scene.fogStartDistance = CGFloat(max(0.2, distance - 1.6))
            scene.fogEndDistance = CGFloat(distance + 3.2)
        }
    }
}
