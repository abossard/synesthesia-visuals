import XCTest
import ViewInspector
@testable import SwiftVJApp
import struct SwiftVJCore.MoodboardNode
import struct SwiftVJCore.MoodboardEdge
import struct SwiftVJCore.MoodboardSubState
import enum SwiftVJCore.TagCategory
import enum SwiftVJCore.EdgeType
import SongRepository
import ShaderRepository

@MainActor
final class MoodboardUITests: XCTestCase {

    // MARK: - Helpers

    private func makeTestAppState() -> AppState {
        AppState(testMode: true)
    }

    private func waitForStateSync() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    private func makeSong(
        artist: String = "Test Artist",
        title: String = "Test Title",
        album: String = "Test Album",
        bpm: Double = 128,
        phase: Phase? = nil,
        audioFilePath: String? = nil
    ) -> Song {
        Song(
            id: SongID(artist: artist, title: title),
            artist: artist,
            title: title,
            album: album,
            bpm: bpm,
            analysis: phase.map {
                StoredSongAnalysis(
                    keywords: [], themes: [], visualAdjectives: [],
                    mood: "energetic", energy: 0.8, valence: 0.6,
                    categories: [:], djPhase: $0
                )
            },
            audioFilePath: audioFilePath
        )
    }

    private func makeSongNode(
        artist: String = "Test Artist",
        title: String = "Test Title",
        at position: CGPoint = CGPoint(x: 100, y: 200)
    ) -> MoodboardNode {
        MoodboardNode.songNode(
            for: SongID(artist: artist, title: title),
            at: position
        )
    }

    private func makeTagNode(
        label: String = "Rock",
        category: TagCategory = .genre,
        at position: CGPoint = CGPoint(x: 300, y: 200)
    ) -> MoodboardNode {
        MoodboardNode.tagNode(label: label, category: category, at: position)
    }

    // MARK: - SongNodeView Tests

    func testSongNodeViewRendersTitleAndArtist() throws {
        let node = makeSongNode()
        let song = makeSong()
        let view = SongNodeView(
            node: node, song: song,
            isSelected: false, isPreviewingThis: false, isPreviewPlaying: false
        )
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(textValues.contains("Test Title"), "Should display song title")
        XCTAssertTrue(textValues.contains("Test Artist"), "Should display artist name")
    }

    func testSongNodeViewShowsPhaseBadge() throws {
        let node = makeSongNode()
        let song = makeSong(phase: .peak)
        let view = SongNodeView(
            node: node, song: song,
            isSelected: false, isPreviewingThis: false, isPreviewPlaying: false
        )
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(
            textValues.contains("Peak"),
            "Should show phase badge for peak phase"
        )
    }

    func testSongNodeViewHiddenPhaseBadgeWhenNoPhase() throws {
        let node = makeSongNode()
        let song = makeSong(phase: nil)
        let view = SongNodeView(
            node: node, song: song,
            isSelected: false, isPreviewingThis: false, isPreviewPlaying: false
        )
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        for phaseName in ["Disco/Jungle", "Buildup", "Peak", "Release", "Feature"] {
            XCTAssertFalse(
                textValues.contains(phaseName),
                "Should not show phase badge '\(phaseName)' when song has no phase"
            )
        }
    }

    func testSongNodeViewShowsUnknownWhenNoSong() throws {
        let node = makeSongNode()
        let view = SongNodeView(
            node: node, song: nil,
            isSelected: false, isPreviewingThis: false, isPreviewPlaying: false
        )
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(textValues.contains("Unknown"), "Should show 'Unknown' when no song provided")
    }

    // MARK: - TagNodeView Tests

    func testTagNodeViewShowsLabel() throws {
        let node = makeTagNode(label: "Electronic", category: .genre)
        let view = TagNodeView(node: node, isSelected: false, connectedCount: 0)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(textValues.contains("Electronic"), "Should display tag label")
    }

    func testTagNodeViewShowsCategoryLabel() throws {
        let categories: [(TagCategory, String)] = [
            (.genre, "Genre"),
            (.mood, "Mood"),
            (.phase, "Phase"),
            (.topic, "Topic"),
            (.custom, "Custom"),
        ]

        for (category, expectedLabel) in categories {
            let node = makeTagNode(label: "Test", category: category)
            let view = TagNodeView(node: node, isSelected: false, connectedCount: 0)
            let inspector = try view.inspect()

            let texts = inspector.findAll(ViewType.Text.self)
            let textValues = texts.compactMap { try? $0.string() }
            XCTAssertTrue(
                textValues.contains(expectedLabel),
                "Should show category label '\(expectedLabel)' for .\(category.rawValue)"
            )
        }
    }

    func testTagNodeViewShowsConnectedCount() throws {
        let node = makeTagNode(label: "Chill", category: .mood)
        let view = TagNodeView(node: node, isSelected: false, connectedCount: 5)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(textValues.contains("5"), "Should show connected count of 5")
    }

    func testTagNodeViewHidesConnectedCountWhenZero() throws {
        let node = makeTagNode(label: "Chill", category: .mood)
        let view = TagNodeView(node: node, isSelected: false, connectedCount: 0)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        // "0" should not appear as a count badge
        let hasCountBadge = textValues.contains("0")
        XCTAssertFalse(hasCountBadge, "Should not show count badge when connectedCount is 0")
    }

    // MARK: - PhaseFlowBarView Tests

    func testPhaseFlowBarViewHasAccessibilityIdentifier() throws {
        let appState = makeTestAppState()
        let view = PhaseFlowBarView().environmentObject(appState)
        let inspector = try view.inspect()

        let identifiers = inspector.findAll(where: {
            (try? $0.accessibilityIdentifier()) == A11yID.moodboardPhaseBar
        })
        XCTAssertFalse(identifiers.isEmpty, "PhaseFlowBarView should have moodboardPhaseBar a11y ID")
    }

    func testPhaseFlowBarViewContainsPhasePills() throws {
        let appState = makeTestAppState()
        let view = PhaseFlowBarView().environmentObject(appState)
        let inspector = try view.inspect()

        let buttons = inspector.findAll(ViewType.Button.self)
        // At minimum, the default phases plus the auto-suggest button should be present
        XCTAssertGreaterThanOrEqual(
            buttons.count, 2,
            "PhaseFlowBarView should contain at least phase pill buttons"
        )
    }

    func testPhaseFlowBarViewHasAutoSuggestButton() throws {
        let appState = makeTestAppState()
        let view = PhaseFlowBarView().environmentObject(appState)
        let inspector = try view.inspect()

        let buttons = inspector.findAll(ViewType.Button.self)
        let labels = buttons.compactMap { button -> String? in
            let texts = button.findAll(ViewType.Text.self)
            return texts.compactMap { try? $0.string() }.first
        }
        XCTAssertTrue(
            labels.contains("Auto-suggest"),
            "PhaseFlowBarView should have an 'Auto-suggest' button"
        )
    }

    // MARK: - PreviewBarView Tests

    func testPreviewBarViewHasTransportControls() throws {
        let appState = makeTestAppState()
        let view = PreviewBarView().environmentObject(appState)
        let inspector = try view.inspect()

        let buttons = inspector.findAll(ViewType.Button.self)
        XCTAssertGreaterThanOrEqual(
            buttons.count, 2,
            "PreviewBarView should have at least stop and play/pause buttons"
        )
    }

    func testPreviewBarViewShowsNoPreviewWhenInactive() throws {
        let appState = makeTestAppState()
        let view = PreviewBarView().environmentObject(appState)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(
            textValues.contains("No preview"),
            "Should display 'No preview' when no song is active"
        )
    }

    func testPreviewBarViewShowsTimeDisplay() throws {
        let appState = makeTestAppState()
        let view = PreviewBarView().environmentObject(appState)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        // Default state: "0:00 / 0:00"
        XCTAssertTrue(
            textValues.contains("0:00 / 0:00"),
            "Should display time as '0:00 / 0:00' when idle"
        )
    }

    // MARK: - MoodboardLibraryPanel Tests

    func testLibraryPanelHasAccessibilityIdentifier() throws {
        let appState = makeTestAppState()
        let view = MoodboardLibraryPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let identifiers = inspector.findAll(where: {
            (try? $0.accessibilityIdentifier()) == A11yID.moodboardLibrary
        })
        XCTAssertFalse(identifiers.isEmpty, "MoodboardLibraryPanel should have moodboardLibrary a11y ID")
    }

    func testLibraryPanelHasSearchField() throws {
        let appState = makeTestAppState()
        let view = MoodboardLibraryPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let textFields = inspector.findAll(ViewType.TextField.self)
        XCTAssertFalse(textFields.isEmpty, "Library panel should have a search text field")
    }

    func testLibraryPanelHasAddAllButton() throws {
        let appState = makeTestAppState()
        let view = MoodboardLibraryPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let buttons = inspector.findAll(ViewType.Button.self)
        let labels = buttons.compactMap { button -> String? in
            let texts = button.findAll(ViewType.Text.self)
            return texts.compactMap { try? $0.string() }.joined(separator: " ")
        }
        let hasAddAll = labels.contains { $0.contains("Add All") }
        XCTAssertTrue(hasAddAll, "Library panel should have an 'Add All' button")
    }

    func testLibraryPanelHasLibraryHeader() throws {
        let appState = makeTestAppState()
        let view = MoodboardLibraryPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(textValues.contains("Library"), "Library panel should have 'Library' header")
    }

    // MARK: - MoodboardDetailPanel Tests

    func testDetailPanelHasAccessibilityIdentifier() throws {
        let appState = makeTestAppState()
        let view = MoodboardDetailPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let identifiers = inspector.findAll(where: {
            (try? $0.accessibilityIdentifier()) == A11yID.moodboardDetail
        })
        XCTAssertFalse(identifiers.isEmpty, "MoodboardDetailPanel should have moodboardDetail a11y ID")
    }

    func testDetailPanelShowsPlaceholderWhenNoSongSelected() throws {
        let appState = makeTestAppState()
        // Default state has no detailPanelSongId, so placeholder should appear
        let view = MoodboardDetailPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(
            textValues.contains("Select a song to view details"),
            "Should show placeholder text when no song is selected"
        )
    }

    func testDetailPanelHasSongDetailHeader() throws {
        let appState = makeTestAppState()
        let view = MoodboardDetailPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let texts = inspector.findAll(ViewType.Text.self)
        let textValues = texts.compactMap { try? $0.string() }
        XCTAssertTrue(
            textValues.contains("Song Detail"),
            "Detail panel should have 'Song Detail' header"
        )
    }

    func testDetailPanelHasCloseButton() throws {
        let appState = makeTestAppState()
        let view = MoodboardDetailPanel().environmentObject(appState)
        let inspector = try view.inspect()

        let buttons = inspector.findAll(ViewType.Button.self)
        XCTAssertFalse(buttons.isEmpty, "Detail panel should have at least a close button")
    }
}
