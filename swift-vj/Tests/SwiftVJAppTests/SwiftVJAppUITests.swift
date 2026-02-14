import XCTest
import ViewInspector
@testable import SwiftVJApp
import SongRepository

@MainActor
final class SwiftVJAppUITests: XCTestCase {
    private func makeTestAppState() -> AppState {
        AppState(testMode: true)
    }

    func testContentViewHasSidebarAndPhaseIdentifiers() throws {
        let appState = makeTestAppState()
        let view = ContentView().environmentObject(appState)
        let inspector = try view.inspect()

        let scrollView = try inspector.find(ViewType.ScrollView.self)
        XCTAssertEqual(try scrollView.accessibilityIdentifier(), A11yID.sidebarList)

        let picker = try inspector.find(ViewType.Picker.self)
        XCTAssertEqual(try picker.accessibilityIdentifier(), A11yID.toolbarPhasePicker)

        let buttonIds = try inspector.findAll(ViewType.Button.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(buttonIds.contains(A11yID.sidebarTab("Master")))
        XCTAssertTrue(buttonIds.contains(A11yID.sidebarTab("Launchpad")))
    }

    func testKaraokeLyricsPanelIdentifiers() throws {
        let engine = KaraokeEngine()
        let view = KaraokeLyricsPanel(karaokeEngine: engine, playbackPosition: 0, isPlaying: false)
        let inspector = try view.inspect()

        let toggle = try inspector.find(ViewType.Toggle.self)
        XCTAssertEqual(try toggle.accessibilityIdentifier(), A11yID.karaokeAutoScrollToggle)

        let buttonIds = inspector.findAll(ViewType.Button.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(buttonIds.contains(A11yID.karaokeLoadTestButton))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokePrevButton))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokeNextButton))
    }

    func testKaraokeSettingsIdentifiers() throws {
        let engine = KaraokeEngine()
        let view = KaraokeSettingsView(karaokeEngine: engine)
        let inspector = try view.inspect()

        let pickerIds = inspector.findAll(ViewType.Picker.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(pickerIds.contains(A11yID.karaokeSettingsAnimationPicker))

        let buttonIds = inspector.findAll(ViewType.Button.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(buttonIds.contains(A11yID.karaokePreset("default")))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokePreset("compact")))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokePreset("dramatic")))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokePreset("subtle")))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokePreset("clean")))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokeSettingsPreviewLoadTest))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokeSettingsPreviewPrev))
        XCTAssertTrue(buttonIds.contains(A11yID.karaokeSettingsPreviewNext))
    }

    func testLaunchpadViewIdentifiers() throws {
        let appState = makeTestAppState()
        let view = LaunchpadView().environmentObject(appState)
        let inspector = try view.inspect()

        let textIds = inspector.findAll(ViewType.Text.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(textIds.contains(A11yID.launchpadStatus))
    }

    func testMasterControlLauncherIdentifiers() throws {
        let appState = makeTestAppState()
        let view = MasterControlView().environmentObject(appState)
        let inspector = try view.inspect()

        let buttonIds = inspector.findAll(ViewType.Button.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(buttonIds.contains(A11yID.masterLaunchAllButton))
        XCTAssertTrue(buttonIds.contains(A11yID.masterAddCommandButton))
    }

    func testSongDetailViewDemoPlayButtonIdentifier() throws {
        let song = Song(
            id: SongID(artist: "Test Artist", title: "Test Title"),
            artist: "Test Artist",
            title: "Test Title"
        )
        let view = SongDetailView(
            song: song,
            onShaderChange: { _ in },
            onReanalyze: {},
            onDemoPlay: {},
            onDelete: {},
            onDeleteImage: { _ in },
            onClearCache: {}
        )
        let inspector = try view.inspect()

        let buttonIds = inspector.findAll(ViewType.Button.self).compactMap {
            try? $0.accessibilityIdentifier()
        }
        XCTAssertTrue(buttonIds.contains(A11yID.songDemoPlayButton))
    }
}
