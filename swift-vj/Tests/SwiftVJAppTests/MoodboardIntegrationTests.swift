import XCTest
@testable import SwiftVJApp
import struct SwiftVJCore.MoodboardSubState
import struct SwiftVJCore.MoodboardNode
import struct SwiftVJCore.MoodboardEdge
import struct SwiftVJCore.PhaseFlowEdge
import struct SwiftVJCore.ViewportState
import enum SwiftVJCore.TagCategory
import enum SwiftVJCore.EdgeType
import enum SwiftVJCore.MoodboardSaveStatus
import SongRepository

@MainActor
final class MoodboardIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeTestAppState() -> AppState {
        AppState(testMode: true)
    }

    private func waitForStateSync() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    private func songID(_ n: Int) -> SongID {
        SongID(artist: "Artist", title: "Song\(n)")
    }

    private func nodeID(_ n: Int) -> String {
        "song:\(songID(n).rawValue)"
    }

    // MARK: - 1. Add Song and Select Opens Detail

    func testAddSongAndSelectOpensDetail() async {
        let app = makeTestAppState()
        let id = songID(1)
        let nid = nodeID(1)

        app.send(.moodboard(.addSongNode(id, position: CGPoint(x: 100, y: 200))))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 1)

        app.send(.moodboard(.selectNodes(Set([nid]))))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.selectedNodeIds, Set([nid]))

        app.send(.moodboard(.showSongDetail(id)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.detailPanelSongId, id)
    }

    // MARK: - 2. Drag and Drop Flow

    func testDragAndDropFlow() async {
        let app = makeTestAppState()
        let id = songID(1)
        let nid = nodeID(1)

        app.send(.moodboard(.addSongNode(id, position: CGPoint(x: 100, y: 200))))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.first?.position, CGPoint(x: 100, y: 200))

        app.send(.moodboard(.moveNode(nid, to: CGPoint(x: 300, y: 400))))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.first?.position, CGPoint(x: 300, y: 400))
    }

    // MARK: - 3. Draw Edge Full Flow

    func testDrawEdgeFullFlow() async {
        let app = makeTestAppState()

        app.send(.moodboard(.addSongNode(songID(1), position: CGPoint(x: 50, y: 50))))
        app.send(.moodboard(.addSongNode(songID(2), position: CGPoint(x: 200, y: 200))))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 2)

        let srcId = nodeID(1)
        let tgtId = nodeID(2)

        app.send(.moodboard(.startDrawingEdge(sourceId: srcId)))
        await waitForStateSync()

        XCTAssertTrue(app.moodboardState.isDrawingEdge)
        XCTAssertEqual(app.moodboardState.drawingEdgeSourceId, srcId)

        app.send(.moodboard(.finishDrawingEdge(targetId: tgtId)))
        await waitForStateSync()

        XCTAssertFalse(app.moodboardState.isDrawingEdge)
        XCTAssertNil(app.moodboardState.drawingEdgeSourceId)
        XCTAssertEqual(app.moodboardState.edges.count, 1)
        XCTAssertEqual(app.moodboardState.edges.first?.sourceId, srcId)
        XCTAssertEqual(app.moodboardState.edges.first?.targetId, tgtId)
    }

    // MARK: - 4. Cancel Edge Drawing

    func testCancelEdgeDrawing() async {
        let app = makeTestAppState()

        app.send(.moodboard(.addSongNode(songID(1), position: .zero)))
        await waitForStateSync()

        app.send(.moodboard(.startDrawingEdge(sourceId: nodeID(1))))
        await waitForStateSync()
        XCTAssertTrue(app.moodboardState.isDrawingEdge)

        app.send(.moodboard(.cancelDrawingEdge))
        await waitForStateSync()

        XCTAssertFalse(app.moodboardState.isDrawingEdge)
        XCTAssertNil(app.moodboardState.drawingEdgeSourceId)
        XCTAssertTrue(app.moodboardState.edges.isEmpty)
    }

    // MARK: - 5. Remove Edge From Canvas

    func testRemoveEdgeFromCanvas() async {
        let app = makeTestAppState()
        let src = nodeID(1)
        let tgt = nodeID(2)

        app.send(.moodboard(.addSongNode(songID(1), position: CGPoint(x: 0, y: 0))))
        app.send(.moodboard(.addSongNode(songID(2), position: CGPoint(x: 100, y: 0))))
        await waitForStateSync()

        app.send(.moodboard(.connectNodes(sourceId: src, targetId: tgt, edgeType: .custom, weight: 1.0)))
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.edges.count, 1)

        let edgeId = app.moodboardState.edges.first!.id
        app.send(.moodboard(.removeEdge(edgeId)))
        await waitForStateSync()

        XCTAssertTrue(app.moodboardState.edges.isEmpty)
    }

    // MARK: - 6. Add Genre Tag

    func testAddGenreTag() async {
        let app = makeTestAppState()
        let id = songID(1)

        app.send(.moodboard(.addSongNode(id, position: .zero)))
        await waitForStateSync()

        // addTagToSong is effect-only; dispatching should not crash
        app.send(.moodboard(.addTagToSong(id, label: "Rock", category: .genre)))
        await waitForStateSync()

        // The action dispatches an effect that calls SongStore.
        // In test mode the environment is nil, so state won't rebuild.
        // Verify the node still exists (no crash / no state corruption).
        XCTAssertEqual(app.moodboardState.nodes.count, 1)
    }

    // MARK: - 7. Add Mood Tag

    func testAddMoodTag() async {
        let app = makeTestAppState()
        let id = songID(1)

        app.send(.moodboard(.addSongNode(id, position: .zero)))
        await waitForStateSync()

        app.send(.moodboard(.addTagToSong(id, label: "Energetic", category: .mood)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 1)
    }

    // MARK: - 8. Add Phase Tag

    func testAddPhaseTag() async {
        let app = makeTestAppState()
        let id = songID(1)

        app.send(.moodboard(.addSongNode(id, position: .zero)))
        await waitForStateSync()

        app.send(.moodboard(.addTagToSong(id, label: "buildup", category: .phase)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 1)
    }

    // MARK: - 9. Remove Tag

    func testRemoveTag() async {
        let app = makeTestAppState()
        let id = songID(1)

        app.send(.moodboard(.addSongNode(id, position: .zero)))
        await waitForStateSync()

        app.send(.moodboard(.addTagToSong(id, label: "Rock", category: .genre)))
        await waitForStateSync()

        // removeTagFromSong is also effect-only; verify no crash
        app.send(.moodboard(.removeTagFromSong(id, label: "Rock", category: .genre)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 1)
    }

    // MARK: - 10. Add Tag Node All Categories

    func testAddTagNodeAllCategories() async {
        let app = makeTestAppState()
        let categories: [(TagCategory, String)] = [
            (.genre, "Rock"),
            (.mood, "Chill"),
            (.phase, "buildup"),
            (.topic, "Love"),
            (.custom, "Favourite"),
        ]

        for (category, label) in categories {
            app.send(.moodboard(.addTagNode(
                label: label,
                category: category,
                position: CGPoint(x: Double(categories.firstIndex(where: { $0.0 == category })!) * 50, y: 0)
            )))
        }
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 5)
        let tagNodes = app.moodboardState.nodes.filter { $0.kind == .tag }
        XCTAssertEqual(tagNodes.count, 5)

        let nodeCategories = Set(tagNodes.compactMap(\.tagCategory))
        XCTAssertEqual(nodeCategories, Set(TagCategory.allCases))
    }

    // MARK: - 11. Phase Flow Edge And Order

    func testPhaseFlowEdgeAndOrder() async {
        let app = makeTestAppState()

        app.send(.moodboard(.addPhaseEdge(from: "disco", to: "buildup", weight: 1.0)))
        app.send(.moodboard(.addPhaseEdge(from: "buildup", to: "peak", weight: 1.0)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.phaseFlowEdges.count, 2)
        let phases = app.moodboardState.phaseFlowEdges.map(\.fromPhase)
        XCTAssertTrue(phases.contains("disco"))
        XCTAssertTrue(phases.contains("buildup"))
    }

    // MARK: - 12. Phase Flow Cycle Rejected

    func testPhaseFlowCycleRejected() async {
        let app = makeTestAppState()

        app.send(.moodboard(.addPhaseEdge(from: "A", to: "B", weight: 1.0)))
        app.send(.moodboard(.addPhaseEdge(from: "B", to: "C", weight: 1.0)))
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.phaseFlowEdges.count, 2)

        // C→A would create a cycle; should be rejected
        app.send(.moodboard(.addPhaseEdge(from: "C", to: "A", weight: 1.0)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.phaseFlowEdges.count, 2, "Cycle-creating edge should be rejected")
    }

    // MARK: - 13. Filter By Phase

    func testFilterByPhase() async {
        let app = makeTestAppState()

        app.send(.moodboard(.filterByPhase("disco")))
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.activePhaseFilter, "disco")

        app.send(.moodboard(.filterByPhase(nil)))
        await waitForStateSync()
        XCTAssertNil(app.moodboardState.activePhaseFilter)
    }

    // MARK: - 14. Board Lifecycle

    func testBoardLifecycle() async {
        let app = makeTestAppState()

        app.send(.moodboard(.newBoard))
        await waitForStateSync()

        XCTAssertNil(app.moodboardState.currentBoardName)
        XCTAssertNil(app.moodboardState.currentBoardId)
        XCTAssertTrue(app.moodboardState.nodes.isEmpty)
        XCTAssertTrue(app.moodboardState.edges.isEmpty)

        // Add songs to the fresh board
        app.send(.moodboard(.addSongNode(songID(1), position: CGPoint(x: 10, y: 10))))
        app.send(.moodboard(.addSongNode(songID(2), position: CGPoint(x: 50, y: 50))))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.nodes.count, 2)
        XCTAssertNil(app.moodboardState.currentBoardName, "New board should have nil name until saved")
    }

    // MARK: - 15. Library Panel Toggle

    func testLibraryPanelToggle() async {
        let app = makeTestAppState()
        let initial = app.moodboardState.libraryPanelOpen

        app.send(.moodboard(.toggleLibraryPanel))
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.libraryPanelOpen, !initial)

        app.send(.moodboard(.toggleLibraryPanel))
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.libraryPanelOpen, initial)
    }

    // MARK: - 16. Multi Select Nodes

    func testMultiSelectNodes() async {
        let app = makeTestAppState()

        for i in 1...3 {
            app.send(.moodboard(.addSongNode(songID(i), position: CGPoint(x: Double(i) * 50, y: 0))))
        }
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.nodes.count, 3)

        let ids = Set([nodeID(1), nodeID(2), nodeID(3)])
        app.send(.moodboard(.selectNodes(ids)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.selectedNodeIds.count, 3)
        XCTAssertEqual(app.moodboardState.selectedNodeIds, ids)
    }

    // MARK: - 17. Select All Nodes

    func testSelectAllNodes() async {
        let app = makeTestAppState()

        for i in 1...5 {
            app.send(.moodboard(.addSongNode(songID(i), position: CGPoint(x: Double(i) * 30, y: 0))))
        }
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.nodes.count, 5)

        let allIds = Set(app.moodboardState.nodes.map(\.id))
        app.send(.moodboard(.selectNodes(allIds)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.selectedNodeIds.count, 5)
    }

    // MARK: - 18. Viewport Pan And Zoom

    func testViewportPanAndZoom() async {
        let app = makeTestAppState()

        let newViewport = ViewportState(offset: CGPoint(x: 100, y: 50), zoom: 2.0)
        app.send(.moodboard(.viewportChanged(newViewport)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.viewport.offset, CGPoint(x: 100, y: 50))
        XCTAssertEqual(app.moodboardState.viewport.zoom, 2.0)
    }

    // MARK: - 19. Edge Weight Update

    func testEdgeWeightUpdate() async {
        let app = makeTestAppState()

        app.send(.moodboard(.addSongNode(songID(1), position: .zero)))
        app.send(.moodboard(.addSongNode(songID(2), position: CGPoint(x: 100, y: 0))))
        await waitForStateSync()

        app.send(.moodboard(.connectNodes(
            sourceId: nodeID(1), targetId: nodeID(2),
            edgeType: .custom, weight: 1.0
        )))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.edges.count, 1)
        XCTAssertEqual(app.moodboardState.edges.first?.weight, 1.0)

        let edgeId = app.moodboardState.edges.first!.id
        app.send(.moodboard(.updateEdgeWeight(edgeId, weight: 0.5)))
        await waitForStateSync()

        XCTAssertEqual(app.moodboardState.edges.first?.weight, 0.5)
    }

    // MARK: - 20. Batch Move Nodes

    func testBatchMoveNodes() async {
        let app = makeTestAppState()

        for i in 1...3 {
            app.send(.moodboard(.addSongNode(songID(i), position: CGPoint(x: Double(i) * 10, y: 0))))
        }
        await waitForStateSync()
        XCTAssertEqual(app.moodboardState.nodes.count, 3)

        let moves: [(String, CGPoint)] = [
            (nodeID(1), CGPoint(x: 500, y: 500)),
            (nodeID(2), CGPoint(x: 600, y: 600)),
            (nodeID(3), CGPoint(x: 700, y: 700)),
        ]

        app.send(.moodboard(.moveNodes(moves)))
        await waitForStateSync()

        for (nid, expected) in moves {
            let node = app.moodboardState.nodes.first(where: { $0.id == nid })
            XCTAssertEqual(node?.position, expected, "Node \(nid) should have moved")
        }
    }
}
