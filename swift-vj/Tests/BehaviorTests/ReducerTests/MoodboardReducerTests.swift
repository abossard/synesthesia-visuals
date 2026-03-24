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
        // Snaps to grid: (10,20) → (20,20)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 20, y: 20))
        XCTAssertEqual(state.nodes[0].kind, .song)
    }

    func testAddSongNodeDoesNotAddDuplicate() {
        var state = MoodboardSubState()
        let songId = makeSongID("Song1")

        _ = apply(.addSongNode(songId, position: CGPoint(x: 10, y: 20)), to: &state)
        _ = apply(.addSongNode(songId, position: CGPoint(x: 99, y: 99)), to: &state)

        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 20, y: 20))
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

        // Snaps to grid: (50,75) → (60,80)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 60, y: 80))
    }

    func testMoveNodeIgnoresUnknownId() {
        let node = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        var state = MoodboardSubState(nodes: [node])

        _ = apply(.moveNode("unknown-id", to: CGPoint(x: 99, y: 99)), to: &state)

        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 0, y: 0))
    }

    // MARK: - moveNodes

    func testMoveNodesBatchUpdatesPositions() {
        let nodeA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let nodeB = makeSongNode("B", at: CGPoint(x: 20, y: 20))
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

    // MARK: - Tag Manager Actions

    // MARK: toggleTagManagerPanel

    func testToggleTagManagerPanel() {
        var state = MoodboardSubState(tagManagerPanelOpen: false)
        _ = apply(.toggleTagManagerPanel, to: &state)
        XCTAssertTrue(state.tagManagerPanelOpen)
        _ = apply(.toggleTagManagerPanel, to: &state)
        XCTAssertFalse(state.tagManagerPanelOpen)
    }

    // MARK: mergeTags

    func testMergeTagsRewiresEdgesAndRemovesSource() {
        let tagA = MoodboardNode.tagNode(label: "Rock", category: .genre, at: CGPoint(x: 0, y: 0))
        let tagB = MoodboardNode.tagNode(label: "Alternative", category: .genre, at: CGPoint(x: 100, y: 0))
        let song1 = makeSongNode("Song1", at: CGPoint(x: 50, y: 50))
        let song2 = makeSongNode("Song2", at: CGPoint(x: 50, y: 100))
        let edgeA1 = makeEdge(sourceId: tagA.id, targetId: song1.id, edgeType: .tagMembership)
        let edgeB2 = makeEdge(sourceId: tagB.id, targetId: song2.id, edgeType: .tagMembership)

        var state = MoodboardSubState(
            nodes: [tagA, tagB, song1, song2],
            edges: [edgeA1, edgeB2]
        )

        _ = apply(.mergeTags(sourceTagId: tagA.id, targetTagId: tagB.id), to: &state)

        // Source tag should be removed
        XCTAssertFalse(state.nodes.contains(where: { $0.id == tagA.id }))
        XCTAssertTrue(state.nodes.contains(where: { $0.id == tagB.id }))
        // Edges from tagA should now point to tagB
        XCTAssertTrue(state.edges.allSatisfy { $0.sourceId != tagA.id && $0.targetId != tagA.id })
        // Both songs should be connected to tagB
        let tagBEdges = state.edges.filter { $0.sourceId == tagB.id || $0.targetId == tagB.id }
        XCTAssertEqual(tagBEdges.count, 2)
    }

    func testMergeTagsIgnoresSameTag() {
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre)
        var state = MoodboardSubState(nodes: [tag])

        _ = apply(.mergeTags(sourceTagId: tag.id, targetTagId: tag.id), to: &state)

        XCTAssertEqual(state.nodes.count, 1)
    }

    func testMergeTagsIgnoresNonTagNodes() {
        let song = makeSongNode("Song1")
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre)
        var state = MoodboardSubState(nodes: [song, tag])

        _ = apply(.mergeTags(sourceTagId: song.id, targetTagId: tag.id), to: &state)

        XCTAssertEqual(state.nodes.count, 2, "Should not merge a song node")
    }

    func testMergeTagsRemovesDuplicateEdges() {
        let tagA = MoodboardNode.tagNode(label: "Rock", category: .genre)
        let tagB = MoodboardNode.tagNode(label: "Alt", category: .genre)
        let song1 = makeSongNode("Song1")
        // Both tags connected to same song
        let edgeA1 = makeEdge(sourceId: tagA.id, targetId: song1.id, edgeType: .tagMembership)
        let edgeB1 = makeEdge(sourceId: tagB.id, targetId: song1.id, edgeType: .tagMembership)

        var state = MoodboardSubState(
            nodes: [tagA, tagB, song1],
            edges: [edgeA1, edgeB1]
        )

        _ = apply(.mergeTags(sourceTagId: tagA.id, targetTagId: tagB.id), to: &state)

        // Should have only 1 edge (not duplicate)
        XCTAssertEqual(state.edges.count, 1)
        XCTAssertEqual(state.edges[0].sourceId, tagB.id)
    }

    // MARK: selectSongsForTag

    func testSelectSongsForTagSelectsConnectedSongNodes() {
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre)
        let song1 = makeSongNode("Song1")
        let song2 = makeSongNode("Song2")
        let song3 = makeSongNode("Song3")
        let edge1 = makeEdge(sourceId: tag.id, targetId: song1.id, edgeType: .tagMembership)
        let edge2 = makeEdge(sourceId: song2.id, targetId: tag.id, edgeType: .tagMembership)
        // song3 is not connected to tag

        var state = MoodboardSubState(
            nodes: [tag, song1, song2, song3],
            edges: [edge1, edge2]
        )

        _ = apply(.selectSongsForTag(tagNodeId: tag.id), to: &state)

        XCTAssertTrue(state.selectedNodeIds.contains(song1.id))
        XCTAssertTrue(state.selectedNodeIds.contains(song2.id))
        XCTAssertFalse(state.selectedNodeIds.contains(song3.id))
        XCTAssertFalse(state.selectedNodeIds.contains(tag.id), "Tag itself should not be selected")
    }

    func testSelectSongsForTagClearsEdgeSelection() {
        let tag = MoodboardNode.tagNode(label: "Chill", category: .mood)
        var state = MoodboardSubState(
            nodes: [tag],
            selectedEdgeIds: ["some-edge"]
        )

        _ = apply(.selectSongsForTag(tagNodeId: tag.id), to: &state)

        XCTAssertTrue(state.selectedEdgeIds.isEmpty)
    }

    // MARK: focusOnTag

    func testFocusOnTagChangesViewportAndSelects() {
        let tag = MoodboardNode.tagNode(label: "EDM", category: .genre, at: CGPoint(x: 300, y: 300))
        let song1 = makeSongNode("Song1", at: CGPoint(x: 250, y: 250))
        let song2 = makeSongNode("Song2", at: CGPoint(x: 350, y: 350))
        let edge1 = makeEdge(sourceId: tag.id, targetId: song1.id, edgeType: .tagMembership)
        let edge2 = makeEdge(sourceId: tag.id, targetId: song2.id, edgeType: .tagMembership)

        var state = MoodboardSubState(
            nodes: [tag, song1, song2],
            edges: [edge1, edge2],
            viewport: .default
        )

        _ = apply(.focusOnTag(tagNodeId: tag.id), to: &state)

        XCTAssertNotEqual(state.viewport, .default, "Viewport should change")
        XCTAssertTrue(state.selectedNodeIds.contains(song1.id))
        XCTAssertTrue(state.selectedNodeIds.contains(song2.id))
    }

    func testFocusOnTagWithNoConnectedSongsDoesNotCrash() {
        let tag = MoodboardNode.tagNode(label: "Empty", category: .custom, at: CGPoint(x: 100, y: 100))
        var state = MoodboardSubState(nodes: [tag])

        _ = apply(.focusOnTag(tagNodeId: tag.id), to: &state)

        XCTAssertNotEqual(state.viewport, .default)
    }

    // MARK: renameTag

    func testRenameTagUpdatesNodeAndEdges() {
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre, at: CGPoint(x: 50, y: 50))
        let song = makeSongNode("Song1")
        let edge = makeEdge(sourceId: tag.id, targetId: song.id, edgeType: .tagMembership)

        var state = MoodboardSubState(
            nodes: [tag, song],
            edges: [edge],
            selectedNodeIds: [tag.id]
        )

        _ = apply(.renameTag(tagNodeId: tag.id, newLabel: "Alternative Rock"), to: &state)

        let newId = "tag:genre:Alternative Rock"
        XCTAssertTrue(state.nodes.contains(where: { $0.id == newId }))
        XCTAssertFalse(state.nodes.contains(where: { $0.id == tag.id }))
        XCTAssertEqual(state.nodes.first(where: { $0.id == newId })?.tagLabel, "Alternative Rock")
        XCTAssertEqual(state.nodes.first(where: { $0.id == newId })?.position, CGPoint(x: 50, y: 50))
        // Edge should reference new id
        XCTAssertTrue(state.edges[0].sourceId == newId)
        // Selection should be updated
        XCTAssertTrue(state.selectedNodeIds.contains(newId))
        XCTAssertFalse(state.selectedNodeIds.contains(tag.id))
    }

    func testRenameTagRejectsEmptyLabel() {
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre)
        var state = MoodboardSubState(nodes: [tag])

        _ = apply(.renameTag(tagNodeId: tag.id, newLabel: "  "), to: &state)

        XCTAssertEqual(state.nodes[0].tagLabel, "Rock")
    }

    func testRenameTagRejectsDuplicateId() {
        let tagA = MoodboardNode.tagNode(label: "Rock", category: .genre)
        let tagB = MoodboardNode.tagNode(label: "Alt", category: .genre)
        var state = MoodboardSubState(nodes: [tagA, tagB])

        // Try to rename Rock to Alt (which already exists)
        _ = apply(.renameTag(tagNodeId: tagA.id, newLabel: "Alt"), to: &state)

        XCTAssertEqual(state.nodes.count, 2)
        XCTAssertTrue(state.nodes.contains(where: { $0.tagLabel == "Rock" }), "Original should remain")
    }

    // MARK: - Helper Function Tests

    func testConnectedSongNodeIds() {
        let tag = MoodboardNode.tagNode(label: "Jazz", category: .genre)
        let song1 = makeSongNode("Song1")
        let song2 = makeSongNode("Song2")
        let song3 = makeSongNode("Song3")
        let edge1 = makeEdge(sourceId: tag.id, targetId: song1.id, edgeType: .tagMembership)
        let edge2 = makeEdge(sourceId: song2.id, targetId: tag.id, edgeType: .tagMembership)

        let result = connectedSongNodeIds(
            tagNodeId: tag.id,
            nodes: [tag, song1, song2, song3],
            edges: [edge1, edge2]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(song1.id))
        XCTAssertTrue(result.contains(song2.id))
        XCTAssertFalse(result.contains(song3.id))
    }

    func testConnectedSongNodeIdsExcludesTagNodes() {
        let tag1 = MoodboardNode.tagNode(label: "Jazz", category: .genre)
        let tag2 = MoodboardNode.tagNode(label: "Chill", category: .mood)
        let edge = makeEdge(sourceId: tag1.id, targetId: tag2.id, edgeType: .tagMembership)

        let result = connectedSongNodeIds(
            tagNodeId: tag1.id,
            nodes: [tag1, tag2],
            edges: [edge]
        )

        XCTAssertTrue(result.isEmpty, "Tag-to-tag edges should not return tag nodes")
    }

    func testComputeViewportToFitReturnsReasonableValues() {
        let nodes = [
            MoodboardNode.tagNode(label: "A", category: .genre, at: CGPoint(x: 100, y: 100)),
            MoodboardNode.tagNode(label: "B", category: .genre, at: CGPoint(x: 500, y: 400))
        ]

        let viewport = computeViewportToFit(nodes: nodes)

        XCTAssertGreaterThan(viewport.zoom, 0.29)
        XCTAssertLessThanOrEqual(viewport.zoom, 2.0)
    }

    func testComputeViewportToFitEmptyReturnsDefault() {
        let viewport = computeViewportToFit(nodes: [])
        XCTAssertEqual(viewport, .default)
    }

    func testCollectTagEntriesReturnsOnlyTagNodes() {
        let tag1 = MoodboardNode.tagNode(label: "Rock", category: .genre)
        let tag2 = MoodboardNode.tagNode(label: "Happy", category: .mood)
        let song = makeSongNode("Song1")

        let entries = collectTagEntries(from: [tag1, tag2, song])

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains(where: { $0.label == "Rock" }))
        XCTAssertTrue(entries.contains(where: { $0.label == "Happy" }))
    }

    func testCollectTagEntriesSortsByCategoryThenLabel() {
        let tagC = MoodboardNode.tagNode(label: "Zzz", category: .genre)
        let tagA = MoodboardNode.tagNode(label: "Aaa", category: .genre)
        let tagM = MoodboardNode.tagNode(label: "Happy", category: .mood)

        let entries = collectTagEntries(from: [tagC, tagA, tagM])

        // genre comes before mood alphabetically by rawValue
        XCTAssertEqual(entries[0].label, "Aaa")
        XCTAssertEqual(entries[1].label, "Zzz")
        XCTAssertEqual(entries[2].label, "Happy")
    }

    // MARK: - Snap-to-Grid Tests

    func testSnapToGridRoundsToNearestGridPoint() {
        // gridSize = 20
        XCTAssertEqual(snapToGrid(CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(snapToGrid(CGPoint(x: 10, y: 10)), CGPoint(x: 20, y: 20))
        XCTAssertEqual(snapToGrid(CGPoint(x: 9, y: 9)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(snapToGrid(CGPoint(x: 30, y: 45)), CGPoint(x: 40, y: 40))
        XCTAssertEqual(snapToGrid(CGPoint(x: -15, y: -25)), CGPoint(x: -20, y: -20))
    }

    func testSnapToGridCustomSize() {
        XCTAssertEqual(snapToGrid(CGPoint(x: 7, y: 13), gridSize: 10), CGPoint(x: 10, y: 10))
        XCTAssertEqual(snapToGrid(CGPoint(x: 4, y: 4), gridSize: 10), CGPoint(x: 0, y: 0))
    }

    func testMoveNodeSnapsToGrid() {
        let node = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        var state = MoodboardSubState(nodes: [node])

        _ = apply(.moveNode(node.id, to: CGPoint(x: 33, y: 47)), to: &state)

        // (33,47) snaps to (40,40) with gridSize=20
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 40, y: 40))
    }

    func testAddSongNodeSnapsToGrid() {
        var state = MoodboardSubState()
        let songId = makeSongID("GridSong")

        _ = apply(.addSongNode(songId, position: CGPoint(x: 55, y: 73)), to: &state)

        // (55,73) snaps to (60,80)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 60, y: 80))
    }

    func testAddTagNodeSnapsToGrid() {
        var state = MoodboardSubState()

        _ = apply(.addTagNode(label: "Rock", category: .genre, position: CGPoint(x: 35, y: 48)), to: &state)

        // (35,48) snaps to (40,40)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 40, y: 40))
    }

    // MARK: - Edge Directionality Tests

    func testEdgeIsDirectedSongToSong() {
        XCTAssertTrue(edgeIsDirected(sourceKind: .song, targetKind: .song))
    }

    func testEdgeIsDirectedTagToTag() {
        XCTAssertTrue(edgeIsDirected(sourceKind: .tag, targetKind: .tag))
    }

    func testEdgeIsNotDirectedSongToTag() {
        XCTAssertFalse(edgeIsDirected(sourceKind: .song, targetKind: .tag))
    }

    func testEdgeIsNotDirectedTagToSong() {
        XCTAssertFalse(edgeIsDirected(sourceKind: .tag, targetKind: .song))
    }

    func testFinishDrawingEdgeSongToSongIsDirected() {
        let songA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let songB = makeSongNode("B", at: CGPoint(x: 100, y: 0))
        var state = MoodboardSubState(
            nodes: [songA, songB],
            isDrawingEdge: true,
            drawingEdgeSourceId: songA.id
        )

        _ = apply(.finishDrawingEdge(targetId: songB.id), to: &state)

        XCTAssertEqual(state.edges.count, 1)
        XCTAssertTrue(state.edges[0].isDirected)
    }

    func testFinishDrawingEdgeSongToTagIsUndirected() {
        let song = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre, at: CGPoint(x: 100, y: 0))
        var state = MoodboardSubState(
            nodes: [song, tag],
            isDrawingEdge: true,
            drawingEdgeSourceId: song.id
        )

        _ = apply(.finishDrawingEdge(targetId: tag.id), to: &state)

        XCTAssertEqual(state.edges.count, 1)
        XCTAssertFalse(state.edges[0].isDirected)
        XCTAssertEqual(state.edges[0].edgeType, .tagMembership)
    }

    func testFinishDrawingEdgeTagToTagIsDirected() {
        let tagA = MoodboardNode.tagNode(label: "Rock", category: .genre, at: CGPoint(x: 0, y: 0))
        let tagB = MoodboardNode.tagNode(label: "Metal", category: .genre, at: CGPoint(x: 100, y: 0))
        var state = MoodboardSubState(
            nodes: [tagA, tagB],
            isDrawingEdge: true,
            drawingEdgeSourceId: tagA.id
        )

        _ = apply(.finishDrawingEdge(targetId: tagB.id), to: &state)

        XCTAssertEqual(state.edges.count, 1)
        XCTAssertTrue(state.edges[0].isDirected)
    }

    func testConnectNodesSetsDirectionalityCorrectly() {
        let songA = makeSongNode("A")
        let songB = makeSongNode("B")
        var state = MoodboardSubState(nodes: [songA, songB])

        _ = apply(.connectNodes(sourceId: songA.id, targetId: songB.id, edgeType: .transition, weight: 1.0), to: &state)

        XCTAssertTrue(state.edges[0].isDirected, "song→song should be directed")
    }

    // MARK: - Layout Tests

    func testForceDirectedLayoutReturnsPositionsForAllNodes() {
        let nodes = [
            makeSongNode("A", at: CGPoint(x: 0, y: 0)),
            makeSongNode("B", at: CGPoint(x: 100, y: 0)),
            makeSongNode("C", at: CGPoint(x: 0, y: 100))
        ]
        let edge = makeEdge(sourceId: nodes[0].id, targetId: nodes[1].id)

        let positions = forceDirectedLayout(nodes: nodes, edges: [edge], iterations: 50)

        XCTAssertEqual(positions.count, 3)
        for node in nodes {
            XCTAssertNotNil(positions[node.id])
        }
    }

    func testForceDirectedLayoutSnapsToGrid() {
        let nodes = [
            makeSongNode("A", at: CGPoint(x: 0, y: 0)),
            makeSongNode("B", at: CGPoint(x: 200, y: 200))
        ]

        let positions = forceDirectedLayout(nodes: nodes, edges: [], iterations: 10)

        for (_, pos) in positions {
            XCTAssertEqual(pos.x.truncatingRemainder(dividingBy: moodboardGridSize), 0, accuracy: 0.01)
            XCTAssertEqual(pos.y.truncatingRemainder(dividingBy: moodboardGridSize), 0, accuracy: 0.01)
        }
    }

    func testHierarchicalLayoutLayersRoots() {
        let nodeA = makeSongNode("A", at: .zero)
        let nodeB = makeSongNode("B", at: .zero)
        let nodeC = makeSongNode("C", at: .zero)
        let edgeAB = MoodboardEdge(
            id: "\(nodeA.id)::\(nodeB.id)::transition",
            sourceId: nodeA.id, targetId: nodeB.id,
            edgeType: .transition, isDirected: true
        )
        let edgeBC = MoodboardEdge(
            id: "\(nodeB.id)::\(nodeC.id)::transition",
            sourceId: nodeB.id, targetId: nodeC.id,
            edgeType: .transition, isDirected: true
        )

        let positions = hierarchicalLayout(
            nodes: [nodeA, nodeB, nodeC],
            edges: [edgeAB, edgeBC]
        )

        XCTAssertEqual(positions.count, 3)
        // A should be leftmost (layer 0), B middle, C rightmost
        let ax = positions[nodeA.id]!.x
        let bx = positions[nodeB.id]!.x
        let cx = positions[nodeC.id]!.x
        XCTAssertLessThan(ax, bx)
        XCTAssertLessThan(bx, cx)
    }

    func testHierarchicalLayoutHandlesNoEdges() {
        let nodes = [makeSongNode("A"), makeSongNode("B")]

        let positions = hierarchicalLayout(nodes: nodes, edges: [])

        XCTAssertEqual(positions.count, 2)
    }

    func testGroupedLayoutSeparatesTagsAndSongs() {
        let tag = MoodboardNode.tagNode(label: "Rock", category: .genre, at: .zero)
        let song = makeSongNode("Song1", at: .zero)
        let edge = makeEdge(sourceId: tag.id, targetId: song.id, edgeType: .tagMembership)

        let positions = groupedLayout(nodes: [tag, song], edges: [edge])

        XCTAssertEqual(positions.count, 2)
        // Tag should be to the left of song
        XCTAssertLessThan(positions[tag.id]!.x, positions[song.id]!.x)
    }

    func testGroupedLayoutHandlesEmptyNodes() {
        let positions = groupedLayout(nodes: [], edges: [])
        XCTAssertTrue(positions.isEmpty)
    }

    func testApplyLayoutUpdatesAllNodePositions() {
        let nodeA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let nodeB = makeSongNode("B", at: CGPoint(x: 0, y: 0))
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.applyLayout(.auto), to: &state)

        // Positions should have changed from origin
        let posA = state.nodes.first(where: { $0.id == nodeA.id })?.position
        let posB = state.nodes.first(where: { $0.id == nodeB.id })?.position
        XCTAssertNotNil(posA)
        XCTAssertNotNil(posB)
        // Force-directed should push apart nodes at same position
        XCTAssertNotEqual(posA, posB, "Nodes at same position should be pushed apart")
    }

    func testApplyLayoutUpdatesViewport() {
        let nodeA = makeSongNode("A", at: CGPoint(x: 0, y: 0))
        let nodeB = makeSongNode("B", at: CGPoint(x: 500, y: 500))
        var state = MoodboardSubState(nodes: [nodeA, nodeB])

        _ = apply(.applyLayout(.grouped), to: &state)

        XCTAssertNotEqual(state.viewport, .default, "Viewport should fit the new layout")
    }
}
