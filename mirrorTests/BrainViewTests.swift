import Testing
import Foundation
import CoreGraphics
@testable import mirror

// MARK: - ThemeExtractionService

struct ThemeExtractionServiceTests {

    @Test func shortTextYieldsNothing() {
        #expect(ThemeExtractionService.extract(from: "Tired today.").isEmpty)
        #expect(ThemeExtractionService.extract(from: "   ").isEmpty)
    }

    @Test func caseAndDiacriticsMergeWithinEntry() {
        let terms = ThemeExtractionService.extract(
            from: "Coffee first thing. Later more coffee, and then café coffee again before bed."
        )
        let coffeeTerms = terms.filter { $0.key == "coffee" }
        #expect(coffeeTerms.count == 1)
    }

    @Test func stopWordsAndScaffoldWordsFiltered() {
        let terms = ThemeExtractionService.extract(
            from: "Voice note transcript from this morning. Feeling like something about everything today, journal entry stuff."
        )
        let keys = Set(terms.map(\.key))
        for banned in ["voice", "note", "transcript", "morning", "feeling", "something", "everything", "journal", "entry", "stuff"] {
            #expect(!keys.contains(banned), "expected '\(banned)' to be filtered")
        }
    }

    @Test func numbersAndShortTokensRejected() {
        let terms = ThemeExtractionService.extract(
            from: "In 2025 my cat and my dog sat near the fireplace watching television quietly."
        )
        let keys = Set(terms.map(\.key))
        #expect(!keys.contains("2025"))
        #expect(!keys.contains("cat"))
        #expect(!keys.contains("dog"))
        #expect(keys.contains("fireplace") || keys.contains("television"))
    }

    @Test func nounsBecomeKeywords() {
        let terms = ThemeExtractionService.extract(
            from: "The meeting about the project ran long and the deadline pressure kept building all afternoon at the office."
        )
        let keys = Set(terms.map(\.key))
        #expect(keys.contains("meeting"))
        #expect(keys.contains("project"))
        #expect(keys.contains("deadline"))
    }
}

// MARK: - BrainGraphBuilder

struct BrainGraphBuilderTests {

    private let size = CGSize(width: 390, height: 700)

    private func term(_ key: String, _ type: ThemeNodeType = .keyword) -> ExtractedTerm {
        ExtractedTerm(key: key, label: key.capitalized, type: type)
    }

    @Test func singleMentionNodesFiltered() {
        let e1 = UUID(), e2 = UUID()
        let graph = BrainGraphBuilder.build(
            termsByEntry: [
                e1: [term("sleep"), term("lonely")],
                e2: [term("sleep")]
            ],
            moodScoreByEntry: [e1: nil, e2: nil],
            canvasSize: size
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes.first?.id == "sleep")
        #expect(graph.nodes.first?.mentionCount == 2)
    }

    @Test func nodeCapAtMaxNodes() {
        // 150 terms, each in 2 entries → all pass minMentions, capped at 100.
        var termsByEntry: [UUID: Set<ExtractedTerm>] = [:]
        let allTerms = (0..<150).map { term("word\($0)") }
        termsByEntry[UUID()] = Set(allTerms)
        termsByEntry[UUID()] = Set(allTerms)
        let graph = BrainGraphBuilder.build(
            termsByEntry: termsByEntry,
            moodScoreByEntry: [:],
            canvasSize: size
        )
        #expect(graph.nodes.count == BrainGraphBuilder.maxNodes)
    }

    @Test func edgeWeightIsSharedEntryCount() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID()
        let graph = BrainGraphBuilder.build(
            termsByEntry: [
                e1: [term("sleep"), term("stress")],
                e2: [term("sleep"), term("stress")],
                e3: [term("sleep"), term("running")],
            ],
            moodScoreByEntry: [:],
            canvasSize: size
        )
        // sleep–stress share 2 entries → edge weight 2; running has 1 mention
        // → not even a node, so no sleep–running edge.
        #expect(graph.edges.count == 1)
        let edge = graph.edges[0]
        #expect(Set([edge.a, edge.b]) == Set(["sleep", "stress"]))
        #expect(edge.weight == 2)
    }

    @Test func singleSharedEntryFormsEdge() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID()
        let graph = BrainGraphBuilder.build(
            termsByEntry: [
                e1: [term("sleep"), term("stress")],
                e2: [term("sleep")],
                e3: [term("stress")],
            ],
            moodScoreByEntry: [:],
            canvasSize: size
        )
        // Both nodes pass minMentions; they share exactly one entry → weight-1 edge.
        #expect(graph.edges.count == 1)
        #expect(graph.edges[0].weight == 1)
    }

    @Test func avgMoodScoreNilWhenNoScoredMoods() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID()
        let graph = BrainGraphBuilder.build(
            termsByEntry: [
                e1: [term("sleep"), term("stress")],
                e2: [term("sleep"), term("stress")],
                e3: [term("stress")],
            ],
            moodScoreByEntry: [e1: nil, e2: nil, e3: 4.0],
            canvasSize: size
        )
        let sleep = graph.nodes.first { $0.id == "sleep" }
        let stress = graph.nodes.first { $0.id == "stress" }
        #expect(sleep?.avgMoodScore == nil)
        #expect(stress?.avgMoodScore == 4.0)
    }

    @Test func personBeatsKeywordAcrossEntries() {
        let e1 = UUID(), e2 = UUID()
        let graph = BrainGraphBuilder.build(
            termsByEntry: [
                e1: [ExtractedTerm(key: "mom", label: "mom", type: .keyword)],
                e2: [ExtractedTerm(key: "mom", label: "Mom", type: .person)],
            ],
            moodScoreByEntry: [:],
            canvasSize: size
        )
        #expect(graph.nodes.count == 1)
        #expect(graph.nodes.first?.type == .person)
        #expect(graph.nodes.first?.label == "Mom")
    }

    @Test func layoutIsDeterministicAndInBounds() {
        let e1 = UUID(), e2 = UUID(), e3 = UUID()
        let termsByEntry: [UUID: Set<ExtractedTerm>] = [
            e1: [term("sleep"), term("stress"), term("running")],
            e2: [term("sleep"), term("stress"), term("running")],
            e3: [term("sleep"), term("stress")],
        ]
        let a = BrainGraphBuilder.build(termsByEntry: termsByEntry, moodScoreByEntry: [:], canvasSize: size)
        let b = BrainGraphBuilder.build(termsByEntry: termsByEntry, moodScoreByEntry: [:], canvasSize: size)
        #expect(a.nodes.map(\.id) == b.nodes.map(\.id))
        for (na, nb) in zip(a.nodes, b.nodes) {
            #expect(abs(na.position.x - nb.position.x) < 0.001)
            #expect(abs(na.position.y - nb.position.y) < 0.001)
        }
        for node in a.nodes {
            #expect(node.position.x >= 0 && node.position.x <= size.width)
            #expect(node.position.y >= 0 && node.position.y <= size.height)
        }
    }

    /// Regression for a real bug: a `.random` fallback in the coincident-
    /// point branch of the force simulation made layout non-reproducible
    /// across builds of the *same* graph whenever two nodes landed exactly
    /// on top of each other during iteration — likely with 60 nodes over
    /// 250 iterations. Exercises the >16-node path where the layout world
    /// is scaled larger than the passed canvas (see `densityScale`), and
    /// checks no two nodes overlap (the actual point of separation).
    @Test func layoutIsDeterministicAndNonOverlappingAtScale() {
        var termsByEntry: [UUID: Set<ExtractedTerm>] = [:]
        for i in 0..<24 {
            let e1 = UUID(), e2 = UUID()
            termsByEntry[e1] = [term("topic\(i)")]
            termsByEntry[e2] = [term("topic\(i)")]
        }
        let a = BrainGraphBuilder.build(termsByEntry: termsByEntry, moodScoreByEntry: [:], canvasSize: size)
        let b = BrainGraphBuilder.build(termsByEntry: termsByEntry, moodScoreByEntry: [:], canvasSize: size)
        #expect(a.nodes.map(\.id) == b.nodes.map(\.id))
        for (na, nb) in zip(a.nodes, b.nodes) {
            #expect(abs(na.position.x - nb.position.x) < 0.001)
            #expect(abs(na.position.y - nb.position.y) < 0.001)
        }
        for i in a.nodes.indices {
            for j in (i + 1)..<a.nodes.count {
                let dx = a.nodes[i].position.x - a.nodes[j].position.x
                let dy = a.nodes[i].position.y - a.nodes[j].position.y
                let dist = (dx * dx + dy * dy).squareRoot()
                #expect(dist >= a.nodes[i].radius + a.nodes[j].radius - 0.5)
            }
        }
    }

    @Test func radiusScalesWithFrequency() {
        let entries = (0..<5).map { _ in UUID() }
        var termsByEntry: [UUID: Set<ExtractedTerm>] = [:]
        for (i, e) in entries.enumerated() {
            var set: Set<ExtractedTerm> = [term("frequent")]
            if i < 2 { set.insert(term("rare")) }
            termsByEntry[e] = set
        }
        let graph = BrainGraphBuilder.build(termsByEntry: termsByEntry, moodScoreByEntry: [:], canvasSize: size)
        let frequent = graph.nodes.first { $0.id == "frequent" }
        let rare = graph.nodes.first { $0.id == "rare" }
        #expect((frequent?.radius ?? 0) > (rare?.radius ?? 0))
    }
}
