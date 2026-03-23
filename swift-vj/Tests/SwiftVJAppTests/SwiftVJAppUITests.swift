import XCTest
import ViewInspector
@testable import SwiftVJApp
import Metal
import SyphonKit
import class SwiftVJCore.EffectEnvironment
import protocol SwiftVJCore.LaunchpadEffectHandling
import enum SwiftVJCore.OscArg
import struct SwiftVJCore.OscEvent
import struct SwiftVJCore.Track
import SongRepository

private actor LaunchpadHandlerSpy: LaunchpadEffectHandling {
    private var receivedEvents: [OscEvent] = []

    func start() async {}
    func stop() async {}
    func buttonPressed(x: Int, y: Int) async {}
    func buttonReleased(x: Int, y: Int) async {}
    func enterLearnMode() async {}
    func exitLearnMode() async {}
    func forceProgrammerMode() async {}
    func flashAll() async {}
    func rainbowPattern() async {}
    func clearAll() async {}
    func receiveOscEvent(_ event: OscEvent) async {
        receivedEvents.append(event)
    }

    func snapshot() -> [OscEvent] {
        receivedEvents
    }
}

@MainActor
final class SwiftVJAppUITests: XCTestCase {
    private func makeTestAppState() -> AppState {
        AppState(testMode: true)
    }

    private func waitForStateSync() async {
        try? await Task.sleep(for: .milliseconds(20))
    }

    func testContentViewHasTopNavAndPhaseIdentifiers() throws {
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

    func testTilePreviewViewUsesSyphonMTKView() async throws {
        let renderEngine = await RenderEngine.create()
        let view = TilePreviewView(tileName: "shader", renderEngine: renderEngine)
        let inspector = try view.inspect()

        _ = try inspector.find(ViewType.View<SyphonMTKView>.self)
    }

    func testSyphonThumbnailViewUsesSyphonMTKView() throws {
        let view = SyphonThumbnailView(serverName: "Shader")
        let inspector = try view.inspect()

        _ = try inspector.find(ViewType.View<SyphonMTKView>.self)
    }

    func testBrightquadsCaptureCreatesFreshPNG() async throws {
        let renderEngine = await RenderEngine.create()
        try await renderEngine.start()
        defer { Task { await renderEngine.stop() } }

        renderEngine.setOutputEnabled(.shader, enabled: true)
        renderEngine.shaderSelection.selectMain(name: "brightquads")
        try? await Task.sleep(for: .milliseconds(900))

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device unavailable")
        }

        let receiver = SyphonReceiver(device: device)
        defer { receiver.disconnect() }

        var connected = false
        for _ in 0..<20 where !connected {
            connected = receiver.connect(appName: nil, serverName: TileConfig.shader.syphonName)
            if !connected {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        guard connected else {
            throw XCTSkip("Could not connect to Syphon Shader server")
        }

        var frame: MTLTexture?
        for _ in 0..<120 where frame == nil {
            frame = receiver.currentFrame()
            if frame == nil {
                try? await Task.sleep(for: .milliseconds(33))
            }
        }

        guard let frame else {
            XCTFail("No Syphon frame received for Shader output")
            return
        }

        let outputPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Shaders/glsl/brightquads.png")
        let capture = ShaderScreenshotCapture(logger: { _, _ in })
        let result = await capture.captureTextureWithBlackCheck(
            frame,
            outputPath: outputPath,
            shaderName: "brightquads"
        )

        XCTAssertTrue(result.success)
        XCTAssertFalse(result.isBlack, "Brightquads capture should not be black")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path))
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

    func testRenderOutputBindingUpdatesAppState() async {
        let appState = makeTestAppState()

        XCTAssertTrue(appState.isRenderOutputEnabled(.shader))
        appState.renderOutputBinding(.shader).wrappedValue = false
        await waitForStateSync()
        XCTAssertFalse(appState.isRenderOutputEnabled(.shader))

        appState.renderOutputBinding(.shader).wrappedValue = true
        await waitForStateSync()
        XCTAssertTrue(appState.isRenderOutputEnabled(.shader))
    }

    func testRenderOutputToggleWorksWhenRendererOff() async {
        let appState = makeTestAppState()

        appState.setRenderEnabled(false)
        await waitForStateSync()
        XCTAssertFalse(appState.renderEnabled)
        appState.renderOutputBinding(.lyrics).wrappedValue = false
        await waitForStateSync()

        XCTAssertFalse(appState.isRenderOutputEnabled(.lyrics))
    }

    func testAutomationPrefixesBindingUpdatesState() async {
        let appState = makeTestAppState()

        appState.automationAutoRecordPrefixesStringBinding.wrappedValue = "/ledfx/, /custom/"
        await waitForStateSync()

        XCTAssertEqual(appState.automationState.autoRecordPrefixes, ["/ledfx/", "/custom/"])
    }

    func testOutgoingLedFXOSCBridgeDispatchesLaunchpadEvent() async {
        let appState = makeTestAppState()
        let handler = LaunchpadHandlerSpy()
        EffectEnvironment.shared.launchpadHandler = handler
        defer { EffectEnvironment.shared.reset() }

        appState.oscHub.outgoingMessageHandler?(
            "magic",
            "/ledfx/scene/strobe/0",
            [.float(1.0)],
            "ui"
        )
        await waitForStateSync()

        let events = await handler.snapshot()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.address, "/ledfx/scene/strobe/0")
        XCTAssertEqual(events.first?.args, [.float(1.0)])
    }

    func testOutgoingLedFXOSCBridgeIgnoresAutomationReplaySource() async {
        let appState = makeTestAppState()
        let handler = LaunchpadHandlerSpy()
        EffectEnvironment.shared.launchpadHandler = handler
        defer { EffectEnvironment.shared.reset() }

        appState.oscHub.outgoingMessageHandler?(
            "magic",
            "/ledfx/scene/strobe/0",
            [.float(1.0)],
            "automation-replay"
        )
        await waitForStateSync()

        let events = await handler.snapshot()
        XCTAssertTrue(events.isEmpty)
    }

    func testOutgoingLedFXOSCDoesNotRecordAutomationWithoutPlayback() async {
        let appState = makeTestAppState()
        let songID = SongID(artist: "Artist", title: "Manual Song")

        appState.setAutomationEnabled(true)
        appState.setAutomationAutoRecordEnabled(true)
        appState.selectAutomationSong(songID)
        await waitForStateSync()

        appState.oscHub.outgoingMessageHandler?(
            "magic",
            "/ledfx/scene/strobe/0",
            [.float(1.0)],
            "ui"
        )
        await waitForStateSync()

        let cues = appState.automationTimeline(for: songID)?.cues ?? []
        XCTAssertTrue(cues.isEmpty)
    }

    func testSendLedFXActionDoesNotRecordWithoutPlayback() async {
        let appState = makeTestAppState()
        let songID = SongID(artist: "Artist", title: "Manual Song")

        appState.setAutomationEnabled(true)
        appState.setAutomationAutoRecordEnabled(true)
        appState.selectAutomationSong(songID)
        await waitForStateSync()

        appState.sendLedFXAction(.activateScene("drop"))
        await waitForStateSync()

        let cues = appState.automationTimeline(for: songID)?.cues ?? []
        XCTAssertTrue(cues.isEmpty)
    }

    func testSendLedFXActionRecordsToCurrentPlaybackSongWhenPlaying() async {
        let appState = makeTestAppState()
        let selectedSong = SongID(artist: "Artist", title: "Manual Song")
        let playbackTrack = Track(artist: "DJ", title: "Live Track")
        let playbackSong = SongID(artist: playbackTrack.artist, title: playbackTrack.title)

        appState.setAutomationEnabled(true)
        appState.setAutomationAutoRecordEnabled(true)
        appState.selectAutomationSong(selectedSong)
        appState.send(.playback(.trackChanged(playbackTrack)))
        appState.send(.playback(.positionUpdated(position: 42, isPlaying: true)))
        await waitForStateSync()

        appState.sendLedFXAction(.activateScene("drop"))
        await waitForStateSync()

        let playbackCues = appState.automationTimeline(for: playbackSong)?.cues ?? []
        XCTAssertEqual(playbackCues.count, 1)
        XCTAssertEqual(playbackCues.first?.actionType, .ledfxActivateScene)
        XCTAssertEqual(playbackCues.first?.value, "drop")
        XCTAssertEqual(playbackCues.first?.source, "auto-ledfx")

        let selectedCues = appState.automationTimeline(for: selectedSong)?.cues ?? []
        XCTAssertTrue(selectedCues.isEmpty)
    }

    func testAutomationPlaybackEnableDefaultsOffAndCanBeEnabledPerSong() async {
        let appState = makeTestAppState()
        let songID = SongID(artist: "Artist", title: "Song")

        appState.selectAutomationSong(songID)
        await waitForStateSync()
        XCTAssertFalse(appState.automationPlaybackEnabled(songID: songID))

        appState.setAutomationPlaybackEnabled(songID: songID, enabled: true)
        await waitForStateSync()
        XCTAssertTrue(appState.automationPlaybackEnabled(songID: songID))
    }
}
