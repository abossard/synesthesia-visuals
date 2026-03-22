// MoodboardReducerTests.swift - Pure state transition tests for moodboard reducer

import XCTest
@testable import SwiftVJCore
import SongRepository
import CoreGraphics

final class MoodboardReducerTests: XCTestCase {

    // MARK: - Helpers

    private func apply(_ action: MoodboardAction, to state: inout MoodboardSubState) -> Effect<MoodboardAction> {
        moodboardReducer(state: &state, action: action)
    }

    private func makeSongID(_ name: String) -> SongID {
        SongID(artist: "Artist", title: name)
    }

    private func makeSongNode(_ name: String, at position: CGPoint = .zero) -> MoodboardNode {
        MoodboardNode.songNode(for: makeSongID(name), at: position)
    }

    private func makeEdge(
        sourceId: String, targetId: String,
        edgeType: EdgeType = .similarity, weight: Double = 1.0
    ) -> MoodboardEdge {
        MoodboardEdge(
            id: "\(sourceId)::\(targetId)::\(edgeType.rawValue)",
            sourceId: sourceId, targetId: targetId,
            edgeType: edgeType, weight: weight, isDirected: false
        )
    }

    // MARK: - addSongNode

    func testAddSongNodeToEmptyState() {
        var state = MoodboardSubState()
        let songId = makeSongID("Song1")

        _ = apply(.addSongNode(songId, position: CGPoint(x: 10, y: 20)), to: &state)

        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes[0].songId, songId)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 10, y: 20))
        XCTAssertEqual(state.nodes[0].kind, .song)
    }

    func testAddSongNodeDoesNotAddDuplicate() {
        var state = MoodboardSubState()
        let songId = makeSongID("Song1")

        _ = apply(.addSongNode(songId, position: CGPoint(x: 10, y: 20)), to: &state)
        _ = apply(.addSongNode(songId, position: CGPoint(x: 99, y: 99)), to: &state)

        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 10, y: 20))
    }

    // MARK: - removeNode

    func testRemoveNodeRemovesNodeAndConnectedEdges() {
        let nodeA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let nodeB = makeSongNode("B", at: CGPoint(x: 10, y: 10))
        let nodeC = makeSongNode("C", at: CGPoint(x: 20, y: 20))
        let edgeAB = makeEdge(sourceId: nodeA.id, targetId: nodeB.id)
        let edgeBC = makeEdge(sourceId: nodeB.id, targetId: nodeC.id)

        var state = MoodboardSubState(
            nodes: [nodeA, nodeB, nodeC],
            edges: [edgeAB, edgeBC],
            selectedNodeIds: [nodeB.id]
        )

        _ = apply(.removeNode(nodeB.id), to: &state)

        XCTAssertEqual(state.nodes.count, 2)
        XCTAssertFalse(state.nodes.contains(where: { $0.id == nodeB.id }))
        XCTAssertTrue(state.edges.isEmpty, "Both edges connected to nodeB should be removed")
        XCTAssertFalse(state.selectedNodeIds.contains(nodeB.id))
    }

    func testRemoveNodeRemovesFromSelection() {
        let nodeA = makeSongNode("A")
        var state = MoodboardSubState(
            nodes: [nodeA],
            selectedNodeIds: [nodeA.id]
        )

        _ = apply(.removeNode(nodeA.id), to: &state)

        XCTAssertTrue(state.selectedNodeIds.isEmpty)
    }

    // MARK: - moveNode

    func testMoveNodeUpdatesPosition() {
        let node = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        var state = MoodboardSubState(nodes: [node])

        _ = apply(.moveNode(node.id, to: CGPoint(x: 50, y: 75)), to: &state)

        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 50, y: 75))
    }

    func testMoveNodeIgnoresUnknownId() {
        let node = makeSongNode("A", at: CGPoint(x: 5, y: 5))
        var state = MoodboardSubState(nodes: [node])

        _ = apply(.moveNode("unknown-id", to: CGPoint(x: 99, y: 99)), to: &state)

        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 5, y: 5))
    }

    // MARK: - moveNodes

    func testMoveNodesBatchUpdatesPositions() {
        let nodeA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let nodeB = makeSongNode("B", at: CGPoint(x: 10, y: 10))
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.moveNodes([
            (nodeA.id, CGPoint(x: 100, y: 200)),
            (nodeB.id, CGPoint(x: 300, y: 400))
        ]), to: &state)

        XCTAssertEqual(state.nodes.first(where: { $0.id == nodeA.id })?.position, CGPoint(x: 100, y: 200))
        XCTAssertEqual(state.nodes.first(where: { $0.id == nodeB.id })?.position, CGPoint(x: 300, y: 400))
    }

    // MARK: - connectNodes

    func testConnectNodesAddsEdge() {
        let nodeA = makeSongNode("A")
        let nodeB = makeSongNode("B")
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.connectNodes(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .similarity, weight: 0.8), to: &state)

        XCTAssertEqual(state.edges.count, 1)
        XCTAssertEqual(state.edges[0].sourceId, nodeA.id)
        XCTAssertEqual(state.edges[0].targetId, nodeB.id)
        XCTAssertEqual(state.edges[0].edgeType, .similarity)
        XCTAssertEqual(state.edges[0].weight, 0.8)
    }

    func testConnectNodesDoesNotAddDuplicateEdge() {
        let nodeA = makeSongNode("A")
        let nodeB = makeSongNode("B")
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.connectNodes(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .similarity, weight: 0.8), to: &state)
        _ = apply(.connectNodes(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .similarity, weight: 0.5), to: &state)

        XCTAssertEqual(state.edges.count, 1)
        XCTAssertEqual(state.edges[0].weight, 0.8, "Original weight should be preserved")
    }

    func testConnectNodesDifferentTypeCreatesSecondEdge() {
        let nodeA = makeSongNode("A")
        let nodeB = makeSongNode("B")
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.connectNodes(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .similarity, weight: 1.0), to: &state)
        _ = apply(.connectNodes(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .transition, weight: 1.0), to: &state)

        XCTAssertEqual(state.edges.count, 2)
    }

    func testConnectSongNodesAlsoAddsSongConnection() {
        let nodeA = makeSongNode("A")
        let nodeB = makeSongNode("B")
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.connectNodes(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .custom, weight: 0.5), to: &state)

        XCTAssertEqual(state.connections.count, 1)
        XCTAssertEqual(state.connections[0].sourceSongId, nodeA.songId)
        XCTAssertEqual(state.connections[0].targetSongId, nodeB.songId)
        XCTAssertEqual(state.connections[0].weight, 0.5)
    }

    // MARK: - removeEdge

    func testRemoveEdgeRemovesEdgeAndFromSelection() {
        let nodeA = makeSongNode("A")
        let nodeB = makeSongNode("B")
        let edge = makeEdge(sourceId: nodeA.id, targetId: nodeB.id)
        var state = MoodboardSubState(
            nodes: [nodeA, nodeB],
            edges: [edge],
            selectedEdgeIds: [edge.id]
        )

        _ = apply(.removeEdge(edge.id), to: &state)

        XCTAssertTrue(state.edges.isEmpty)
        XCTAssertFalse(state.selectedEdgeIds.contains(edge.id))
    }

    func testRemoveEdgeAlsoRemovesSongConnection() {
        let nodeA = makeSongNode("A")
        let nodeB = makeSongNode("B")
        let edge = makeEdge(sourceId: nodeA.id, targetId: nodeB.id, edgeType: .custom)
        let connection = SongConnection(
            sourceSongId: nodeA.songId!, targetSongId: nodeB.songId!,
            connectionType: .custom, weight: 1.0
        )
        var state = MoodboardSubState(
            nodes: [nodeA, nodeB],
            edges: [edge],
            connections: [connection]
        )

        _ = apply(.removeEdge(edge.id), to: &state)

        XCTAssertTrue(state.connections.isEmpty)
    }

    // MARK: - updateEdgeWeight

    func testUpdateEdgeWeightUpdatesWeight() {
        let edge = makeEdge(sourceId: "a", targetId: "b", weight: 1.0)
        var state = MoodboardSubState(edges: [edge])

        let effect = apply(.updateEdgeWeight(edge.id, weight: 0.3), to: &state)

        XCTAssertEqual(state.edges[0].weight, 0.3)
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for updateEdgeWeight")
        }
    }

    func testUpdateEdgeWeightIgnoresUnknownId() {
        let edge = makeEdge(sourceId: "a", targetId: "b", weight: 1.0)
        var state = MoodboardSubState(edges: [edge])

        _ = apply(.updateEdgeWeight("unknown", weight: 0.5), to: &state)

        XCTAssertEqual(state.edges[0].weight, 1.0)
    }

    // MARK: - addPhaseEdge

    func testAddPhaseEdgeAddsEdge() {
        var state = MoodboardSubState()

        _ = apply(.addPhaseEdge(from: "intro", to: "peak", weight: 1.0), to: &state)

        XCTAssertEqual(state.phaseFlowEdges.count, 1)
        XCTAssertEqual(state.phaseFlowEdges[0].fromPhase, "intro")
        XCTAssertEqual(state.phaseFlowEdges[0].toPhase, "peak")
    }

    func testAddPhaseEdgeUpdatesPhaseOrder() {
        var state = MoodboardSubState()

        _ = apply(.addPhaseEdge(from: "intro", to: "peak", weight: 1.0), to: &state)

        XCTAssertFalse(state.phaseOrder.isEmpty)
        XCTAssertTrue(state.phaseOrder.contains("intro"))
        XCTAssertTrue(state.phaseOrder.contains("peak"))
    }

    func testAddPhaseEdgeRejectsIfWouldCreateCycle() {
        var state = MoodboardSubState(
            phaseFlowEdges: [
                PhaseFlowEdge(fromPhase: "intro", toPhase: "peak"),
                PhaseFlowEdge(fromPhase: "peak", toPhase: "outro")
            ]
        )
        state.phaseOrder = PhaseGraph.order(edges: state.phaseFlowEdges)

        _ = apply(.addPhaseEdge(from: "outro", to: "intro", weight: 1.0), to: &state)

        XCTAssertEqual(state.phaseFlowEdges.count, 2, "Cycle-creating edge should be rejected")
    }

    // MARK: - removePhaseEdge

    func testRemovePhaseEdgeRemovesEdge() {
        var state = MoodboardSubState(
            phaseFlowEdges: [
                PhaseFlowEdge(fromPhase: "intro", toPhase: "peak"),
                PhaseFlowEdge(fromPhase: "peak", toPhase: "outro")
            ]
        )

        _ = apply(.removePhaseEdge(from: "intro", to: "peak"), to: &state)

        XCTAssertEqual(state.phaseFlowEdges.count, 1)
        XCTAssertEqual(state.phaseFlowEdges[0].fromPhase, "peak")
    }

    func testRemovePhaseEdgeUpdatesPhaseOrder() {
        var state = MoodboardSubState(
            phaseFlowEdges: [
                PhaseFlowEdge(fromPhase: "intro", toPhase: "peak"),
                PhaseFlowEdge(fromPhase: "peak", toPhase: "outro")
            ]
        )
        state.phaseOrder = PhaseGraph.order(edges: state.phaseFlowEdges)

        _ = apply(.removePhaseEdge(from: "peak", to: "outro"), to: &state)

        XCTAssertFalse(state.phaseOrder.contains("outro"))
    }

    // MARK: - filterByPhase

    func testFilterByPhaseSetsFilter() {
        var state = MoodboardSubState()

        let effect = apply(.filterByPhase("peak"), to: &state)

        XCTAssertEqual(state.activePhaseFilter, "peak")
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for filterByPhase")
        }
    }

    func testFilterByPhaseNilClearsFilter() {
        var state = MoodboardSubState(activePhaseFilter: "peak")

        _ = apply(.filterByPhase(nil), to: &state)

        XCTAssertNil(state.activePhaseFilter)
    }

    // MARK: - viewportChanged

    func testViewportChangedUpdatesViewport() {
        var state = MoodboardSubState()
        let newViewport = ViewportState(offset: CGPoint(x: 100, y: 200), zoom: 2.5)

        let effect = apply(.viewportChanged(newViewport), to: &state)

        XCTAssertEqual(state.viewport.offset, CGPoint(x: 100, y: 200))
        XCTAssertEqual(state.viewport.zoom, 2.5)
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for viewportChanged")
        }
    }

    // MARK: - selectNodes

    func testSelectNodesReplacesSelection() {
        var state = MoodboardSubState(selectedNodeIds: ["old1", "old2"])

        let effect = apply(.selectNodes(["new1", "new2", "new3"]), to: &state)

        XCTAssertEqual(state.selectedNodeIds, ["new1", "new2", "new3"])
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for selectNodes")
        }
    }

    func testSelectNodesEmptyClearsSelection() {
        var state = MoodboardSubState(selectedNodeIds: ["a", "b"])

        _ = apply(.selectNodes([]), to: &state)

        XCTAssertTrue(state.selectedNodeIds.isEmpty)
    }

    // MARK: - selectEdges

    func testSelectEdgesReplacesSelection() {
        var state = MoodboardSubState(selectedEdgeIds: ["e1"])

        let effect = apply(.selectEdges(["e2", "e3"]), to: &state)

        XCTAssertEqual(state.selectedEdgeIds, ["e2", "e3"])
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for selectEdges")
        }
    }

    // MARK: - toggleLibraryPanel

    func testToggleLibraryPanelTogglesState() {
        var state = MoodboardSubState(libraryPanelOpen: true)

        let effect = apply(.toggleLibraryPanel, to: &state)

        XCTAssertFalse(state.libraryPanelOpen)
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for toggleLibraryPanel")
        }

        _ = apply(.toggleLibraryPanel, to: &state)
        XCTAssertTrue(state.libraryPanelOpen)
    }

    // MARK: - showSongDetail

    func testShowSongDetailSetsSongId() {
        var state = MoodboardSubState()
        let songId = makeSongID("DetailSong")

        let effect = apply(.showSongDetail(songId), to: &state)

        XCTAssertEqual(state.detailPanelSongId, songId)
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for showSongDetail")
        }
    }

    func testShowSongDetailNilClearsSongId() {
        var state = MoodboardSubState(detailPanelSongId: makeSongID("Existing"))

        _ = apply(.showSongDetail(nil), to: &state)

        XCTAssertNil(state.detailPanelSongId)
    }

    // MARK: - canvasLoaded

    func testCanvasLoadedAppliesPositionsToNodes() {
        var state = MoodboardSubState()
        let nodeA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let nodeB = makeSongNode("B", at: CGPoint(x: 0, y: 0))
        let edge = makeEdge(sourceId: nodeA.id, targetId: nodeB.id)
        let connection = SongConnection(
            sourceSongId: nodeA.songId!, targetSongId: nodeB.songId!
        )
        let positions = [
            CanvasPositionEntry(nodeId: nodeA.id, x: 100, y: 200),
            CanvasPositionEntry(nodeId: nodeB.id, x: 300, y: 400)
        ]

        let effect = apply(
            .canvasLoaded(
                nodes: [nodeA, nodeB],
                edges: [edge],
                connections: [connection],
                phaseEdges: [],
                positions: positions
            ),
            to: &state
        )

        XCTAssertEqual(state.nodes.count, 2)
        XCTAssertEqual(state.nodes.first(where: { $0.id == nodeA.id })?.position, CGPoint(x: 100, y: 200))
        XCTAssertEqual(state.nodes.first(where: { $0.id == nodeB.id })?.position, CGPoint(x: 300, y: 400))
        XCTAssertEqual(state.edges.count, 1)
        XCTAssertEqual(state.connections.count, 1)
        XCTAssertFalse(state.isLoading)
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for canvasLoaded")
        }
    }

    func testCanvasLoadedWithoutPositionsKeepsOriginal() {
        var state = MoodboardSubState()
        let node = makeSongNode("A", at: CGPoint(x: 42, y: 42))

        _ = apply(
            .canvasLoaded(nodes: [node], edges: [], connections: [], phaseEdges: [], positions: []),
            to: &state
        )

        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 42, y: 42))
    }

    func testCanvasLoadedSetsPhaseOrderFromEdges() {
        var state = MoodboardSubState()
        let phaseEdges = [
            PhaseFlowEdge(fromPhase: "intro", toPhase: "peak"),
            PhaseFlowEdge(fromPhase: "peak", toPhase: "outro")
        ]

        _ = apply(
            .canvasLoaded(nodes: [], edges: [], connections: [], phaseEdges: phaseEdges, positions: []),
            to: &state
        )

        XCTAssertEqual(state.phaseFlowEdges.count, 2)
        XCTAssertEqual(state.phaseOrder, PhaseGraph.order(edges: phaseEdges))
    }

    func testCanvasLoadedClearsLoadingState() {
        var state = MoodboardSubState(isLoading: true)

        _ = apply(
            .canvasLoaded(nodes: [], edges: [], connections: [], phaseEdges: [], positions: []),
            to: &state
        )

        XCTAssertFalse(state.isLoading)
    }

    // MARK: - graphRebuilt

    func testGraphRebuiltPreservesExistingPositions() {
        let existingNode = makeSongNode("A", at: CGPoint(x: 50, y: 75))
        var state = MoodboardSubState(nodes: [existingNode])

        let rebuiltNode = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let newNode = makeSongNode("B", at: CGPoint(x: 10, y: 10))

        let effect = apply(.graphRebuilt(nodes: [rebuiltNode, newNode], edges: []), to: &state)

        let nodeA = state.nodes.first(where: { $0.id == existingNode.id })
        XCTAssertEqual(nodeA?.position, CGPoint(x: 50, y: 75), "Existing position should be preserved")

        let nodeB = state.nodes.first(where: { $0.id == newNode.id })
        XCTAssertEqual(nodeB?.position, CGPoint(x: 10, y: 10), "New node keeps its original position")

        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for graphRebuilt")
        }
    }

    func testGraphRebuiltUpdatesEdges() {
        let nodeA = makeSongNode("A")
        let oldEdge = makeEdge(sourceId: nodeA.id, targetId: "old-target")
        var state = MoodboardSubState(nodes: [nodeA], edges: [oldEdge])

        let newEdge = makeEdge(sourceId: nodeA.id, targetId: "new-target")
        _ = apply(.graphRebuilt(nodes: [nodeA], edges: [newEdge]), to: &state)

        XCTAssertEqual(state.edges.count, 1)
        XCTAssertEqual(state.edges[0].targetId, "new-target")
    }

    // MARK: - canvasPositionsSaved

    func testCanvasPositionsSavedUpdatesSaveStatus() {
        var state = MoodboardSubState(saveStatus: .saving)

        let effect = apply(.canvasPositionsSaved, to: &state)

        XCTAssertEqual(state.saveStatus, .saved)
        if case .none = effect.operation {} else {
            XCTFail("Expected .none effect for canvasPositionsSaved")
        }
    }
}
