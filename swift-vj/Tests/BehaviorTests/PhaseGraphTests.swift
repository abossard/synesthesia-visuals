import Testing
@testable import SwiftVJCore

// MARK: - order Tests

@Suite("PhaseGraph.order")
struct PhaseGraphOrderTests {

    @Test("Empty edges produce empty order")
    func emptyEdges() {
        let result = PhaseGraph.order(edges: [])
        #expect(result.isEmpty)
    }

    @Test("Linear chain preserves topological order")
    func linearChain() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "C"),
            PhaseFlowEdge(fromPhase: "C", toPhase: "D"),
        ]
        let order = PhaseGraph.order(edges: edges)
        #expect(order.count == 4)
        // A must appear before B, B before C, C before D
        let idxA = order.firstIndex(of: "A")!
        let idxB = order.firstIndex(of: "B")!
        let idxC = order.firstIndex(of: "C")!
        let idxD = order.firstIndex(of: "D")!
        #expect(idxA < idxB)
        #expect(idxB < idxC)
        #expect(idxC < idxD)
    }

    @Test("Branching DAG includes all nodes")
    func branchingDAG() {
        //   A -> B -> D
        //   A -> C -> D
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "A", toPhase: "C"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "D"),
            PhaseFlowEdge(fromPhase: "C", toPhase: "D"),
        ]
        let order = PhaseGraph.order(edges: edges)
        #expect(order.count == 4)
        #expect(Set(order) == Set(["A", "B", "C", "D"]))
        // A before B and C, both before D
        let idxA = order.firstIndex(of: "A")!
        let idxD = order.firstIndex(of: "D")!
        #expect(idxA < idxD)
    }

    @Test("Weighted edges influence tie-breaking order")
    func weightedTieBreaking() {
        // A -> B (weight 0.5), A -> C (weight 1.0)
        // Both B and C have in-degree 0 after A is processed;
        // C has higher max incoming weight so should appear first among the tie group
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B", weight: 0.5),
            PhaseFlowEdge(fromPhase: "A", toPhase: "C", weight: 1.0),
        ]
        let order = PhaseGraph.order(edges: edges)
        #expect(order.count == 3)
        #expect(order.first == "A")
        // C should come before B due to higher incoming weight
        let idxB = order.firstIndex(of: "B")!
        let idxC = order.firstIndex(of: "C")!
        #expect(idxC < idxB)
    }

    @Test("Cycle falls back to edge-appearance order")
    func cycleFallback() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "A"),
        ]
        let order = PhaseGraph.order(edges: edges)
        // Should still return all phases (fallback to edge-appearance)
        #expect(Set(order) == Set(["A", "B"]))
    }
}

// MARK: - validate Tests

@Suite("PhaseGraph.validate")
struct PhaseGraphValidateTests {

    @Test("Valid DAG returns true with nil cycle")
    func validDAG() {
        let edges = [
            PhaseFlowEdge(fromPhase: "intro", toPhase: "buildup"),
            PhaseFlowEdge(fromPhase: "buildup", toPhase: "peak"),
        ]
        let (valid, cycle) = PhaseGraph.validate(edges: edges)
        #expect(valid == true)
        #expect(cycle == nil)
    }

    @Test("Empty edges are valid")
    func emptyValid() {
        let (valid, cycle) = PhaseGraph.validate(edges: [])
        #expect(valid == true)
        #expect(cycle == nil)
    }

    @Test("Simple cycle detected")
    func simpleCycle() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "C"),
            PhaseFlowEdge(fromPhase: "C", toPhase: "A"),
        ]
        let (valid, cycle) = PhaseGraph.validate(edges: edges)
        #expect(valid == false)
        #expect(cycle != nil)
        // The cycle path should contain the cycle nodes
        if let cycle = cycle {
            #expect(cycle.count >= 2)
        }
    }

    @Test("Self-loop detected as cycle")
    func selfLoop() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "A"),
        ]
        let (valid, cycle) = PhaseGraph.validate(edges: edges)
        #expect(valid == false)
        #expect(cycle != nil)
    }

    @Test("Complex DAG with multiple branches is valid")
    func complexValid() {
        let edges = [
            PhaseFlowEdge(fromPhase: "intro", toPhase: "warmup"),
            PhaseFlowEdge(fromPhase: "intro", toPhase: "buildup"),
            PhaseFlowEdge(fromPhase: "warmup", toPhase: "peak"),
            PhaseFlowEdge(fromPhase: "buildup", toPhase: "peak"),
            PhaseFlowEdge(fromPhase: "peak", toPhase: "cooldown"),
        ]
        let (valid, cycle) = PhaseGraph.validate(edges: edges)
        #expect(valid == true)
        #expect(cycle == nil)
    }
}

// MARK: - wouldCreateCycle Tests

@Suite("PhaseGraph.wouldCreateCycle")
struct PhaseGraphWouldCreateCycleTests {

    @Test("Adding forward edge to DAG does not create cycle")
    func safeForwardEdge() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "C"),
        ]
        let result = PhaseGraph.wouldCreateCycle(edges: edges, from: "A", to: "C")
        #expect(result == false)
    }

    @Test("Adding back edge creates cycle")
    func unsafeBackEdge() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "C"),
        ]
        let result = PhaseGraph.wouldCreateCycle(edges: edges, from: "C", to: "A")
        #expect(result == true)
    }

    @Test("Adding self-loop creates cycle")
    func selfLoopCycle() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
        ]
        let result = PhaseGraph.wouldCreateCycle(edges: edges, from: "A", to: "A")
        #expect(result == true)
    }

    @Test("Adding edge to new node is safe")
    func newNodeSafe() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
        ]
        let result = PhaseGraph.wouldCreateCycle(edges: edges, from: "B", to: "C")
        #expect(result == false)
    }

    @Test("Adding edge from new node is safe")
    func fromNewNodeSafe() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
        ]
        let result = PhaseGraph.wouldCreateCycle(edges: edges, from: "C", to: "A")
        #expect(result == false)
    }
}

// MARK: - suggestDefaultFlow Tests

@Suite("PhaseGraph.suggestDefaultFlow")
struct PhaseGraphSuggestDefaultFlowTests {

    @Test("Empty phases produce no edges")
    func emptyPhases() {
        let edges = PhaseGraph.suggestDefaultFlow(phases: [])
        #expect(edges.isEmpty)
    }

    @Test("Single phase produces no edges")
    func singlePhase() {
        let edges = PhaseGraph.suggestDefaultFlow(phases: ["intro"])
        #expect(edges.isEmpty)
    }

    @Test("Standard DJ phases sorted into natural progression")
    func standardPhases() {
        let phases = ["peak", "intro", "cooldown", "buildup", "outro"]
        let edges = PhaseGraph.suggestDefaultFlow(phases: phases)

        #expect(edges.count == 4)
        // Verify the chain follows natural DJ order:
        // intro(0) -> buildup(2) -> peak(3) -> cooldown(4) -> outro(5)
        let chain = edgesToChain(edges)
        let introIdx = chain.firstIndex(of: "intro")!
        let buildupIdx = chain.firstIndex(of: "buildup")!
        let peakIdx = chain.firstIndex(of: "peak")!
        let cooldownIdx = chain.firstIndex(of: "cooldown")!
        let outroIdx = chain.firstIndex(of: "outro")!
        #expect(introIdx < buildupIdx)
        #expect(buildupIdx < peakIdx)
        #expect(peakIdx < cooldownIdx)
        #expect(cooldownIdx < outroIdx)
    }

    @Test("Unknown phase names placed at end")
    func unknownPhases() {
        let phases = ["intro", "mystery", "peak"]
        let edges = PhaseGraph.suggestDefaultFlow(phases: phases)

        #expect(edges.count == 2)
        let chain = edgesToChain(edges)
        // intro(0) -> peak(3) -> mystery(6)
        let introIdx = chain.firstIndex(of: "intro")!
        let mysteryIdx = chain.firstIndex(of: "mystery")!
        #expect(introIdx < mysteryIdx)
    }

    @Test("All edges have weight 1.0")
    func allWeightsOne() {
        let edges = PhaseGraph.suggestDefaultFlow(phases: ["intro", "peak", "outro"])
        for edge in edges {
            #expect(edge.weight == 1.0)
        }
    }

    @Test("Result forms valid DAG")
    func resultIsValidDAG() {
        let phases = ["peak", "opener", "warmup", "cooldown", "closer"]
        let edges = PhaseGraph.suggestDefaultFlow(phases: phases)
        let (valid, _) = PhaseGraph.validate(edges: edges)
        #expect(valid == true)
    }
}

// MARK: - longestPath Tests

@Suite("PhaseGraph.longestPath")
struct PhaseGraphLongestPathTests {

    @Test("Empty edges produce empty path")
    func emptyEdges() {
        let path = PhaseGraph.longestPath(edges: [])
        #expect(path.isEmpty)
    }

    @Test("Linear chain returns full path")
    func linearChain() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B", weight: 1.0),
            PhaseFlowEdge(fromPhase: "B", toPhase: "C", weight: 1.0),
            PhaseFlowEdge(fromPhase: "C", toPhase: "D", weight: 1.0),
        ]
        let path = PhaseGraph.longestPath(edges: edges)
        #expect(path == ["A", "B", "C", "D"])
    }

    @Test("Branching DAG picks longest weighted path")
    func branchingDAG() {
        //   A -1-> B -1-> D   (total: 2)
        //   A -5-> C -5-> D   (total: 10)
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B", weight: 1.0),
            PhaseFlowEdge(fromPhase: "B", toPhase: "D", weight: 1.0),
            PhaseFlowEdge(fromPhase: "A", toPhase: "C", weight: 5.0),
            PhaseFlowEdge(fromPhase: "C", toPhase: "D", weight: 5.0),
        ]
        let path = PhaseGraph.longestPath(edges: edges)
        #expect(path == ["A", "C", "D"])
    }

    @Test("Cycle returns empty path")
    func cycleReturnsEmpty() {
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B"),
            PhaseFlowEdge(fromPhase: "B", toPhase: "A"),
        ]
        let path = PhaseGraph.longestPath(edges: edges)
        #expect(path.isEmpty)
    }

    @Test("Single edge returns two-node path")
    func singleEdge() {
        let edges = [
            PhaseFlowEdge(fromPhase: "X", toPhase: "Y", weight: 3.0),
        ]
        let path = PhaseGraph.longestPath(edges: edges)
        #expect(path == ["X", "Y"])
    }

    @Test("Disconnected components — returns longest among all")
    func disconnectedComponents() {
        // Component 1: A -> B (weight 1)
        // Component 2: X -> Y -> Z (weight 1 each, total 2)
        let edges = [
            PhaseFlowEdge(fromPhase: "A", toPhase: "B", weight: 1.0),
            PhaseFlowEdge(fromPhase: "X", toPhase: "Y", weight: 1.0),
            PhaseFlowEdge(fromPhase: "Y", toPhase: "Z", weight: 1.0),
        ]
        let path = PhaseGraph.longestPath(edges: edges)
        // Should be the longer path: X -> Y -> Z
        #expect(path.count == 3)
        #expect(path == ["X", "Y", "Z"])
    }
}

// MARK: - Test Helpers

/// Convert a list of sequential edges into the ordered chain of phases.
private func edgesToChain(_ edges: [PhaseFlowEdge]) -> [String] {
    guard let first = edges.first else { return [] }
    var chain = [first.fromPhase]
    for edge in edges {
        chain.append(edge.toPhase)
    }
    return chain
}
