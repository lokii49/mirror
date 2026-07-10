import Foundation
import CoreGraphics
import simd

struct BrainNode: Identifiable, Sendable {
    /// Normalized term key.
    let id: String
    let label: String
    let type: ThemeNodeType
    let entryIDs: Set<UUID>
    /// Document frequency — number of entries mentioning this node.
    let mentionCount: Int
    /// nil when no contributing entry has a scored mood.
    let avgMoodScore: Double?
    var position: CGPoint = .zero
    /// 3D layout position, unit-ish scale around origin (hub at .zero). Populated by `layout3D`.
    var position3: SIMD3<Double> = .zero
    let radius: CGFloat
}

struct BrainEdge: Identifiable, Sendable {
    let id: String
    let a: String
    let b: String
    /// Number of entries where both nodes appear (≥ minSharedEntriesForEdge).
    let weight: Int
}

struct BrainGraph: Sendable {
    var nodes: [BrainNode]
    var edges: [BrainEdge]
    /// World-space position of the "You" hub — the 2D layout world can be
    /// larger than the viewport (more room means less forced overlap), so
    /// this isn't assumed to be the viewport center; the view fits-to-content
    /// on appear instead, the way Obsidian's graph opens zoomed to fit.
    var hubPosition: CGPoint = .zero
}

enum BrainGraphBuilder {
    static let minMentions = 2
    static let maxNodes = 60
    static let minSharedEntriesForEdge = 1

    static func build(
        termsByEntry: [UUID: Set<ExtractedTerm>],
        moodScoreByEntry: [UUID: Double?],
        canvasSize: CGSize
    ) -> BrainGraph {
        // Invert: key → (label, best type, entries).
        struct Agg {
            var label: String
            var type: ThemeNodeType
            var entryIDs: Set<UUID> = []
        }
        var aggregates: [String: Agg] = [:]
        for (entryID, terms) in termsByEntry {
            for term in terms {
                if var agg = aggregates[term.key] {
                    agg.entryIDs.insert(entryID)
                    // Type precedence: person > place > keyword — merges e.g.
                    // "mom" tagged as noun in one entry and name in another.
                    if precedence(term.type) < precedence(agg.type) {
                        agg.type = term.type
                        agg.label = term.label
                    }
                    aggregates[term.key] = agg
                } else {
                    aggregates[term.key] = Agg(label: term.label, type: term.type, entryIDs: [entryID])
                }
            }
        }

        let ranked = aggregates
            .filter { $0.value.entryIDs.count >= minMentions }
            .sorted {
                if $0.value.entryIDs.count == $1.value.entryIDs.count { return $0.key < $1.key }
                return $0.value.entryIDs.count > $1.value.entryIDs.count
            }
            .prefix(maxNodes)

        let counts = ranked.map { $0.value.entryIDs.count }
        let minCount = counts.min() ?? minMentions
        let maxCount = counts.max() ?? minMentions

        let nodes: [BrainNode] = ranked.map { key, agg in
            let count = agg.entryIDs.count
            let normalized = maxCount > minCount
                ? Double(count - minCount) / Double(maxCount - minCount)
                : 0
            let scores = agg.entryIDs.compactMap { moodScoreByEntry[$0] ?? nil }
            return BrainNode(
                id: key,
                label: agg.label,
                type: agg.type,
                entryIDs: agg.entryIDs,
                mentionCount: count,
                avgMoodScore: scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count),
                radius: 8 + 18 * CGFloat(normalized.squareRoot())
            )
        }

        var edges: [BrainEdge] = []
        for i in nodes.indices {
            for j in nodes.indices where j > i {
                let shared = nodes[i].entryIDs.intersection(nodes[j].entryIDs).count
                if shared >= minSharedEntriesForEdge {
                    edges.append(BrainEdge(
                        id: "\(nodes[i].id)|\(nodes[j].id)",
                        a: nodes[i].id,
                        b: nodes[j].id,
                        weight: shared
                    ))
                }
            }
        }

        var graph = BrainGraph(nodes: nodes, edges: edges)
        layout(&graph, in: canvasSize)
        layout3D(&graph)
        return graph
    }

    private static func precedence(_ type: ThemeNodeType) -> Int {
        switch type {
        case .person: return 0
        case .place: return 1
        case .theme: return 2
        case .keyword: return 3
        }
    }

    // MARK: - Force-directed layout (Fruchterman–Reingold with gravity)

    static func layout(_ graph: inout BrainGraph, in viewportSize: CGSize) {
        let n = graph.nodes.count
        guard n > 0, viewportSize.width > 0, viewportSize.height > 0 else { return }

        // Lay out in a world that can be larger than the viewport — forcing
        // everything into the exact visible rectangle at 1x is what caused
        // real overlap once node count grew (no algorithm fixes a room that's
        // physically too small). The view fits-to-content on appear instead,
        // same as Obsidian: laid out with room to breathe, zoomed to fit.
        let densityScale = max(1, (CGFloat(n) / 16).squareRoot())
        let size = CGSize(width: viewportSize.width * densityScale, height: viewportSize.height * densityScale)

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let seedRadius = 0.3 * min(size.width, size.height)

        // Frequency-weighted gravity: frequent topics orbit closer to the
        // central "You" hub, rare ones drift to the periphery.
        let counts = graph.nodes.map(\.mentionCount)
        let minCount = counts.min() ?? 1
        let maxCount = counts.max() ?? 1
        let gravities: [CGFloat] = graph.nodes.map { node in
            let normalized = maxCount > minCount
                ? CGFloat(node.mentionCount - minCount) / CGFloat(maxCount - minCount)
                : 0.5
            return 0.08 + 0.12 * normalized
        }

        // Deterministic seed: stable FNV-1a hash of node id → angle on a circle.
        var positions: [CGPoint] = graph.nodes.map { node in
            let angle = 2 * .pi * Double(fnv1a(node.id) % 360) / 360
            return CGPoint(
                x: center.x + seedRadius * cos(angle),
                y: center.y + seedRadius * sin(angle)
            )
        }
        guard n > 1 else {
            graph.nodes[0].position = center
            graph.hubPosition = center
            return
        }

        var indexByID: [String: Int] = [:]
        for (i, node) in graph.nodes.enumerated() { indexByID[node.id] = i }

        let area = size.width * size.height
        let k = 0.62 * (area / CGFloat(n)).squareRoot()
        var temperature = size.width / 8

        for _ in 0..<250 {
            var displacement = [CGPoint](repeating: .zero, count: n)

            // Repulsion between all pairs.
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var dx = positions[i].x - positions[j].x
                    var dy = positions[i].y - positions[j].y
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.01 {
                        dx = jitter(i, j)
                        dy = jitter(j, i)
                        dist = 0.01
                    }
                    let force = (k * k) / dist
                    let fx = dx / dist * force
                    let fy = dy / dist * force
                    displacement[i].x += fx
                    displacement[i].y += fy
                    displacement[j].x -= fx
                    displacement[j].y -= fy
                }
            }

            // Attraction along edges, scaled by weight.
            for edge in graph.edges {
                guard let i = indexByID[edge.a], let j = indexByID[edge.b] else { continue }
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let dist = max(0.01, (dx * dx + dy * dy).squareRoot())
                let force = (dist * dist / k) * CGFloat(1 + log(Double(edge.weight)))
                let fx = dx / dist * force
                let fy = dy / dist * force
                displacement[i].x -= fx
                displacement[i].y -= fy
                displacement[j].x += fx
                displacement[j].y += fy
            }

            // Gravity toward the central hub keeps the graph cohesive;
            // strength scales with node frequency (see gravities above).
            for i in 0..<n {
                displacement[i].x += (center.x - positions[i].x) * gravities[i]
                displacement[i].y += (center.y - positions[i].y) * gravities[i]
            }

            // Apply, clamped to current temperature.
            for i in 0..<n {
                let d = displacement[i]
                let len = max(0.01, (d.x * d.x + d.y * d.y).squareRoot())
                let capped = min(len, temperature)
                positions[i].x += d.x / len * capped
                positions[i].y += d.y / len * capped
            }
            temperature *= 0.95
        }

        // Keep nodes clear of the central "You" hub drawn at the center.
        let hubClearance: CGFloat = 64
        for i in 0..<n {
            let dx = positions[i].x - center.x
            let dy = positions[i].y - center.y
            let dist = (dx * dx + dy * dy).squareRoot()
            let minDist = hubClearance + graph.nodes[i].radius
            if dist < minDist {
                let angle = dist < 0.01
                    ? 2 * .pi * Double(fnv1a(graph.nodes[i].id) % 360) / 360
                    : atan2(Double(dy), Double(dx))
                positions[i].x = center.x + minDist * CGFloat(cos(angle))
                positions[i].y = center.y + minDist * CGFloat(sin(angle))
            }
        }

        // Final pairwise separation pass — repulsion decays with distance
        // and can still leave near-collisions; nudge apart anything closer
        // than both radii plus a small gap so nodes never visually overlap.
        // Re-clamps into bounds after every push in the SAME pass — doing
        // the bounds clamp as a separate step afterward could shove two
        // different nodes into the same corner, undoing the separation it
        // just did.
        func clampPosition(_ i: Int) {
            let inset = graph.nodes[i].radius + 24
            positions[i].x = min(max(positions[i].x, inset), size.width - inset)
            positions[i].y = min(max(positions[i].y, inset), size.height - inset)
        }
        for i in 0..<n { clampPosition(i) }
        for _ in 0..<40 {
            var moved = false
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let minSep = graph.nodes[i].radius + graph.nodes[j].radius + 6
                    var dx = positions[i].x - positions[j].x
                    var dy = positions[i].y - positions[j].y
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.01 {
                        dx = jitter(i, j)
                        dy = jitter(j, i)
                        dist = 0.01
                    }
                    if dist < minSep {
                        let push = (minSep - dist) / 2
                        let ux = dx / dist, uy = dy / dist
                        positions[i].x += ux * push
                        positions[i].y += uy * push
                        positions[j].x -= ux * push
                        positions[j].y -= uy * push
                        clampPosition(i)
                        clampPosition(j)
                        moved = true
                    }
                }
            }
            if !moved { break }
        }

        for i in 0..<n {
            graph.nodes[i].position = positions[i]
        }
        graph.hubPosition = center
    }

    // MARK: - Force-directed layout (3D, spherical seed + gravity)

    static func layout3D(_ graph: inout BrainGraph) {
        let n = graph.nodes.count
        guard n > 0 else { return }
        guard n > 1 else {
            graph.nodes[0].position3 = .zero
            return
        }

        let counts = graph.nodes.map(\.mentionCount)
        let minCount = counts.min() ?? 1
        let maxCount = counts.max() ?? 1
        let gravities: [Double] = graph.nodes.map { node in
            let normalized = maxCount > minCount
                ? Double(node.mentionCount - minCount) / Double(maxCount - minCount)
                : 0.5
            return 0.045 + 0.05 * normalized
        }

        // Deterministic seed: hash → point on a sphere (golden-angle spiral, stable per id).
        let seedRadius = 1.4
        var positions: [SIMD3<Double>] = graph.nodes.map { node in
            let h = fnv1a(node.id)
            let u = Double(h % 10_000) / 10_000.0        // [0, 1)
            let v = Double((h / 10_000) % 10_000) / 10_000.0
            let theta = 2 * Double.pi * u
            let phi = acos(1 - 2 * v)
            return SIMD3(
                seedRadius * sin(phi) * cos(theta),
                seedRadius * sin(phi) * sin(theta),
                seedRadius * cos(phi)
            )
        }

        var indexByID: [String: Int] = [:]
        for (i, node) in graph.nodes.enumerated() { indexByID[node.id] = i }

        let k = 5.6 / cbrt(Double(n))
        var temperature = 0.6

        for _ in 0..<250 {
            var displacement = [SIMD3<Double>](repeating: .zero, count: n)

            for i in 0..<n {
                for j in (i + 1)..<n {
                    var delta = positions[i] - positions[j]
                    var dist = length(delta)
                    if dist < 0.001 {
                        delta = SIMD3(jitter3D(i, j), jitter3D(j, i), jitter3D(i &+ j, i))
                        dist = 0.001
                    }
                    let force = (k * k) / dist
                    let f = delta / dist * force
                    displacement[i] += f
                    displacement[j] -= f
                }
            }

            for edge in graph.edges {
                guard let i = indexByID[edge.a], let j = indexByID[edge.b] else { continue }
                let delta = positions[i] - positions[j]
                let dist = max(0.001, length(delta))
                let force = (dist * dist / k) * (1 + log(Double(edge.weight)))
                let f = delta / dist * force
                displacement[i] -= f
                displacement[j] += f
            }

            for i in 0..<n {
                displacement[i] += -positions[i] * gravities[i]
            }

            for i in 0..<n {
                let len = max(0.001, length(displacement[i]))
                let capped = min(len, temperature)
                positions[i] += displacement[i] / len * capped
            }
            temperature *= 0.95
        }

        // Normalize spread to a stable target radius BEFORE hub-clearance
        // and separation, so those two passes (which reason in real scene
        // units matching BrainSceneView's sphere sizes) aren't undone by a
        // later rescale shrinking the gaps they just created.
        let rawMaxDist = positions.map(length).max() ?? 1
        let targetRadius = 4.5
        let seedScale = rawMaxDist > 0.01 ? targetRadius / rawMaxDist : 1
        for i in 0..<n { positions[i] *= seedScale }

        // Keep nodes clear of the hub at the origin.
        let hubClearance = 1.05
        for i in 0..<n {
            let dist = length(positions[i])
            let minDist = hubClearance + Double(graph.nodes[i].radius) / 100
            if dist < minDist {
                let dir = dist < 0.001 ? positions[i] + SIMD3(0.01, 0.01, 0.01) : positions[i]
                positions[i] = normalize(dir) * minDist
            }
        }

        // Final pairwise separation pass — pure spring relaxation can still
        // leave near-collisions; nudge apart anything closer than both
        // rendered radii. Matches BrainSceneView's `0.035 + radius/230` scene
        // scale exactly, plus a real gap so links stay visible between
        // nodes — this should look like a constellation, not a ball pit.
        for _ in 0..<40 {
            var moved = false
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let sceneRadiusI = 0.035 + Double(graph.nodes[i].radius) / 230
                    let sceneRadiusJ = 0.035 + Double(graph.nodes[j].radius) / 230
                    let minSep = sceneRadiusI + sceneRadiusJ + 0.16
                    var delta = positions[i] - positions[j]
                    var dist = length(delta)
                    if dist < 0.001 {
                        delta = SIMD3(0.01, 0.0, 0.0)
                        dist = 0.001
                    }
                    if dist < minSep {
                        let push = (minSep - dist) / 2
                        let dir = delta / dist
                        positions[i] += dir * push
                        positions[j] -= dir * push
                        moved = true
                    }
                }
            }
            if !moved { break }
        }

        for i in 0..<n {
            graph.nodes[i].position3 = positions[i]
        }
    }

    /// Deterministic stand-in for a random nudge when two nodes land exactly
    /// coincident — a real `.random` here made layout non-reproducible
    /// across runs of the *same* graph (coincidences aren't rare over 250
    /// iterations with 60 nodes), which broke both the "stable layout"
    /// contract and the fit-to-content framing that depends on it.
    private static func jitter(_ i: Int, _ j: Int) -> CGFloat {
        let h = UInt64(bitPattern: Int64(i &* 92_821 &+ j &* 68_917 &+ 104_729))
        return CGFloat(h % 1000) / 1000 - 0.5
    }

    private static func jitter3D(_ i: Int, _ j: Int) -> Double {
        let h = UInt64(bitPattern: Int64(i &* 92_821 &+ j &* 68_917 &+ 104_729))
        return Double(h % 1000) / 1000 * 0.1 - 0.05
    }

    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
