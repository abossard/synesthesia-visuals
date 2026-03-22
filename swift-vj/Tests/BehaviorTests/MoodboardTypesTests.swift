import XCTest
@testable import SwiftVJCore
import SongRepository

final class MoodboardTypesTests: XCTestCase {

    // MARK: - MoodboardNode

    func test_songNode_setsIdAndKind() {
        let songId = SongID(artist: "Queen", title: "Radio Ga Ga")
        let node = MoodboardNode.songNode(for: songId)

        XCTAssertEqual(node.id, "song:Queen::Radio Ga Ga")
        XCTAssertEqual(node.kind, .song)
        XCTAssertEqual(node.songId, songId)
        XCTAssertNil(node.tagLabel)
        XCTAssertNil(node.tagCategory)
    }

    func test_songNode_usesProvidedPosition() {
        let songId = SongID(artist: "A", title: "B")
        let node = MoodboardNode.songNode(for: songId, at: CGPoint(x: 10, y: 20))

        XCTAssertEqual(node.position, CGPoint(x: 10, y: 20))
    }

    func test_songNode_defaultsToZeroPosition() {
        let node = MoodboardNode.songNode(for: SongID(artist: "A", title: "B"))

        XCTAssertEqual(node.position, .zero)
    }

    func test_tagNode_setsIdAndKindAndCategory() {
        let node = MoodboardNode.tagNode(label: "chill", category: .mood)

        XCTAssertEqual(node.id, "tag:mood:chill")
        XCTAssertEqual(node.kind, .tag)
        XCTAssertEqual(node.tagLabel, "chill")
        XCTAssertEqual(node.tagCategory, .mood)
        XCTAssertNil(node.songId)
    }

    func test_tagNode_usesProvidedPosition() {
        let node = MoodboardNode.tagNode(label: "rock", category: .genre, at: CGPoint(x: 5, y: 15))

        XCTAssertEqual(node.position, CGPoint(x: 5, y: 15))
    }

    func test_withPosition_returnsNewNodeOriginalUnchanged() {
        let original = MoodboardNode.songNode(for: SongID(artist: "A", title: "B"), at: .zero)

        let moved = original.withPosition(CGPoint(x: 42, y: 99))

        XCTAssertEqual(original.position, .zero, "Original unchanged")
        XCTAssertEqual(moved.position, CGPoint(x: 42, y: 99))
        XCTAssertEqual(moved.id, original.id, "ID preserved")
        XCTAssertEqual(moved.kind, original.kind, "Kind preserved")
    }

    func test_moodboardNode_equatable_sameValuesAreEqual() {
        let a = MoodboardNode.tagNode(label: "dark", category: .mood, at: CGPoint(x: 1, y: 2))
        let b = MoodboardNode.tagNode(label: "dark", category: .mood, at: CGPoint(x: 1, y: 2))

        XCTAssertEqual(a, b)
    }

    func test_moodboardNode_equatable_differentValuesAreNotEqual() {
        let a = MoodboardNode.tagNode(label: "dark", category: .mood)
        let b = MoodboardNode.tagNode(label: "light", category: .mood)

        XCTAssertNotEqual(a, b)
    }

    func test_moodboardNode_codableRoundTrip() throws {
        let node = MoodboardNode.songNode(for: SongID(artist: "Daft Punk", title: "Aerodynamic"), at: CGPoint(x: 3, y: 7))

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(MoodboardNode.self, from: data)

        XCTAssertEqual(decoded, node)
    }

    // MARK: - MoodboardEdge

    func test_withWeight_returnsNewEdgeOriginalUnchanged() {
        let original = MoodboardEdge(id: "e1", sourceId: "a", targetId: "b", edgeType: .similarity, weight: 0.5)

        let updated = original.withWeight(0.9)

        XCTAssertEqual(original.weight, 0.5, "Original unchanged")
        XCTAssertEqual(updated.weight, 0.9)
        XCTAssertEqual(updated.id, original.id, "ID preserved")
        XCTAssertEqual(updated.edgeType, original.edgeType, "Type preserved")
    }

    func test_moodboardEdge_equatable() {
        let a = MoodboardEdge(id: "e1", sourceId: "a", targetId: "b", edgeType: .transition, weight: 1.0, isDirected: true)
        let b = MoodboardEdge(id: "e1", sourceId: "a", targetId: "b", edgeType: .transition, weight: 1.0, isDirected: true)
        let c = MoodboardEdge(id: "e2", sourceId: "a", targetId: "b", edgeType: .transition, weight: 1.0, isDirected: true)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_moodboardEdge_codableRoundTrip() throws {
        let edge = MoodboardEdge(id: "e1", sourceId: "s1", targetId: "s2", edgeType: .remix, weight: 0.7, isDirected: true)

        let data = try JSONEncoder().encode(edge)
        let decoded = try JSONDecoder().decode(MoodboardEdge.self, from: data)

        XCTAssertEqual(decoded, edge)
    }

    // MARK: - SongConnection

    func test_songConnection_computedId() {
        let conn = SongConnection(
            sourceSongId: SongID(artist: "A", title: "X"),
            targetSongId: SongID(artist: "B", title: "Y"),
            connectionType: .custom
        )

        XCTAssertEqual(conn.id, "A::X::B::Y::custom")
    }

    func test_songConnection_withWeight_returnsNewInstanceOriginalUnchanged() {
        let original = SongConnection(
            sourceSongId: SongID(artist: "A", title: "X"),
            targetSongId: SongID(artist: "B", title: "Y"),
            weight: 1.0
        )

        let updated = original.withWeight(0.3)

        XCTAssertEqual(original.weight, 1.0, "Original unchanged")
        XCTAssertEqual(updated.weight, 0.3)
        XCTAssertEqual(updated.sourceSongId, original.sourceSongId)
    }

    func test_songConnection_codableRoundTrip() throws {
        let conn = SongConnection(
            sourceSongId: SongID(artist: "Daft Punk", title: "Around The World"),
            targetSongId: SongID(artist: "Daft Punk", title: "Harder Better Faster Stronger"),
            connectionType: .remix,
            weight: 0.8
        )

        let data = try JSONEncoder().encode(conn)
        let decoded = try JSONDecoder().decode(SongConnection.self, from: data)

        XCTAssertEqual(decoded, conn)
    }

    // MARK: - PhaseFlowEdge

    func test_phaseFlowEdge_computedId() {
        let edge = PhaseFlowEdge(fromPhase: "buildup", toPhase: "drop")

        XCTAssertEqual(edge.id, "buildup::drop")
    }

    func test_phaseFlowEdge_withWeight_returnsNewInstanceOriginalUnchanged() {
        let original = PhaseFlowEdge(fromPhase: "intro", toPhase: "verse", weight: 1.0)

        let updated = original.withWeight(2.5)

        XCTAssertEqual(original.weight, 1.0, "Original unchanged")
        XCTAssertEqual(updated.weight, 2.5)
        XCTAssertEqual(updated.fromPhase, "intro")
    }

    func test_phaseFlowEdge_codableRoundTrip() throws {
        let edge = PhaseFlowEdge(fromPhase: "verse", toPhase: "chorus", weight: 0.6)

        let data = try JSONEncoder().encode(edge)
        let decoded = try JSONDecoder().decode(PhaseFlowEdge.self, from: data)

        XCTAssertEqual(decoded, edge)
    }

    // MARK: - ViewportState

    func test_viewportState_defaultValues() {
        let state = ViewportState.default

        XCTAssertEqual(state.offset, .zero)
        XCTAssertEqual(state.zoom, 1.0)
    }

    func test_viewportState_customInit() {
        let state = ViewportState(offset: CGPoint(x: 100, y: -50), zoom: 2.5)

        XCTAssertEqual(state.offset, CGPoint(x: 100, y: -50))
        XCTAssertEqual(state.zoom, 2.5)
    }

    func test_viewportState_codableRoundTrip() throws {
        let state = ViewportState(offset: CGPoint(x: 42, y: -10), zoom: 0.75)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ViewportState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    // MARK: - CanvasPositionEntry

    func test_canvasPositionEntry_computedIdIsNodeId() {
        let entry = CanvasPositionEntry(nodeId: "song:A::B", x: 10, y: 20)

        XCTAssertEqual(entry.id, "song:A::B")
    }

    func test_canvasPositionEntry_storesCoordinates() {
        let entry = CanvasPositionEntry(nodeId: "node1", x: 3.5, y: -7.2)

        XCTAssertEqual(entry.x, 3.5)
        XCTAssertEqual(entry.y, -7.2)
    }

    // MARK: - SongGraphNode

    func test_songGraphNode_tagSetEquality() {
        let a = SongGraphNode(id: SongID(artist: "A", title: "X"), tags: ["rock", "loud"])
        let b = SongGraphNode(id: SongID(artist: "A", title: "X"), tags: ["loud", "rock"])

        XCTAssertEqual(a, b, "Tag sets are order-independent")
    }

    func test_songGraphNode_differentTagsAreNotEqual() {
        let a = SongGraphNode(id: SongID(artist: "A", title: "X"), tags: ["rock"])
        let b = SongGraphNode(id: SongID(artist: "A", title: "X"), tags: ["pop"])

        XCTAssertNotEqual(a, b)
    }

    // MARK: - SongGraphEdge

    func test_songGraphEdge_computedId() {
        let edge = SongGraphEdge(
            sourceId: SongID(artist: "A", title: "X"),
            targetId: SongID(artist: "B", title: "Y"),
            edgeType: .similarity,
            weight: 0.5
        )

        XCTAssertEqual(edge.id, "A::X::B::Y")
    }

    func test_songGraphEdge_equatable() {
        let a = SongGraphEdge(sourceId: SongID(artist: "A", title: "X"), targetId: SongID(artist: "B", title: "Y"), edgeType: .similarity, weight: 0.5)
        let b = SongGraphEdge(sourceId: SongID(artist: "A", title: "X"), targetId: SongID(artist: "B", title: "Y"), edgeType: .similarity, weight: 0.5)

        XCTAssertEqual(a, b)
    }
}
