// PlaybackReducerTests.swift - Tests for playback reducer
// Pure function tests with no async or mocks needed

import XCTest
@testable import SwiftVJCore

final class PlaybackReducerTests: XCTestCase {

    // MARK: - Track Changed

    func testTrackChangedUpdatesState() {
        var state = PlaybackSubState()
        var appState = AppState(playback: state)

        let track = Track(artist: "Test Artist", title: "Test Song")
        let action = PlaybackAction.trackChanged(track)

        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertEqual(appState.playback.currentTrack?.artist, "Test Artist")
        XCTAssertEqual(appState.playback.currentTrack?.title, "Test Song")
    }

    func testTrackChangedLogsMessage() {
        var appState = AppState()
        let track = Track(artist: "Daft Punk", title: "Around The World")
        let action = PlaybackAction.trackChanged(track)

        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("Daft Punk") })
        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("Around The World") })
    }

    // MARK: - Position Updated

    func testPositionUpdatedUpdatesState() {
        var appState = AppState()
        let action = PlaybackAction.positionUpdated(position: 45.5, isPlaying: true)

        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertEqual(appState.playback.position, 45.5)
        XCTAssertTrue(appState.playback.isPlaying)
    }

    func testPositionUpdatedWithPausedState() {
        var appState = AppState()
        appState.playback.isPlaying = true

        let action = PlaybackAction.positionUpdated(position: 30.0, isPlaying: false)
        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertEqual(appState.playback.position, 30.0)
        XCTAssertFalse(appState.playback.isPlaying)
    }

    // MARK: - Source Changed

    func testSourceChangedUpdatesState() {
        var appState = AppState()
        appState.playback.source = "vdj"

        let action = PlaybackAction.sourceChanged("spotify")
        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertEqual(appState.playback.source, "spotify")
    }

    func testSourceChangedLogsMessage() {
        var appState = AppState()

        let action = PlaybackAction.sourceChanged("vdj")
        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("vdj") })
    }

    // MARK: - Timing Offset

    func testTimingOffsetChangedUpdatesState() {
        var appState = AppState()
        appState.playback.timingOffsetMs = 0

        let action = PlaybackAction.timingOffsetChanged(100)
        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertEqual(appState.playback.timingOffsetMs, 100)
    }

    func testTimingOffsetChangedLogsMessage() {
        var appState = AppState()

        let action = PlaybackAction.timingOffsetChanged(-50)
        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("-50ms") })
    }

    // MARK: - Playing State Changed

    func testPlayingStateChangedUpdatesState() {
        var appState = AppState()
        appState.playback.isPlaying = false

        let action = PlaybackAction.playingStateChanged(true)
        _ = playbackReducer(state: &appState.playback, action: action, appState: &appState)

        XCTAssertTrue(appState.playback.isPlaying)
    }
}
