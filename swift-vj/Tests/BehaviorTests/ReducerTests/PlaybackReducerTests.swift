// PlaybackReducerTests.swift - Tests for playback reducer
// Pure function tests with no async or mocks needed

import XCTest
@testable import SwiftVJCore

final class PlaybackReducerTests: XCTestCase {

    // Helper to avoid overlapping access issues when calling reducers
    private func applyPlaybackReducer(_ action: PlaybackAction, to appState: inout AppState) {
        var playbackState = appState.playback
        _ = playbackReducer(state: &playbackState, action: action, appState: &appState)
        appState.playback = playbackState
    }

    // MARK: - Track Changed

    func testTrackChangedUpdatesState() {
        let state = PlaybackSubState()
        var appState = AppState(playback: state)

        let track = Track(artist: "Test Artist", title: "Test Song")
        let action = PlaybackAction.trackChanged(track)

        applyPlaybackReducer(action, to: &appState)

        XCTAssertEqual(appState.playback.currentTrack?.artist, "Test Artist")
        XCTAssertEqual(appState.playback.currentTrack?.title, "Test Song")
    }

    func testTrackChangedLogsMessage() {
        var appState = AppState()
        let track = Track(artist: "Daft Punk", title: "Around The World")
        let action = PlaybackAction.trackChanged(track)

        applyPlaybackReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("Daft Punk") })
        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("Around The World") })
    }

    // MARK: - Position Updated

    func testPositionUpdatedUpdatesState() {
        var appState = AppState()
        let action = PlaybackAction.positionUpdated(position: 45.5, isPlaying: true)

        applyPlaybackReducer(action, to: &appState)

        XCTAssertEqual(appState.playback.position, 45.5)
        XCTAssertTrue(appState.playback.isPlaying)
    }

    func testPositionUpdatedWithPausedState() {
        var appState = AppState()
        appState.playback.isPlaying = true

        let action = PlaybackAction.positionUpdated(position: 30.0, isPlaying: false)
        applyPlaybackReducer(action, to: &appState)

        XCTAssertEqual(appState.playback.position, 30.0)
        XCTAssertFalse(appState.playback.isPlaying)
    }

    // MARK: - Source Changed

    func testSourceChangedUpdatesState() {
        var appState = AppState()
        appState.playback.source = "vdj"

        let action = PlaybackAction.sourceChanged("spotify")
        applyPlaybackReducer(action, to: &appState)

        XCTAssertEqual(appState.playback.source, "spotify")
    }

    func testSourceChangedLogsMessage() {
        var appState = AppState()

        let action = PlaybackAction.sourceChanged("vdj")
        applyPlaybackReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("vdj") })
    }

    // MARK: - Timing Offset

    func testTimingOffsetChangedUpdatesState() {
        var appState = AppState()
        appState.playback.timingOffsetMs = 0

        let action = PlaybackAction.timingOffsetChanged(100)
        applyPlaybackReducer(action, to: &appState)

        XCTAssertEqual(appState.playback.timingOffsetMs, 100)
    }

    func testTimingOffsetChangedLogsMessage() {
        var appState = AppState()

        let action = PlaybackAction.timingOffsetChanged(-50)
        applyPlaybackReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("-50ms") })
    }

    // MARK: - Playing State Changed

    func testPlayingStateChangedUpdatesState() {
        var appState = AppState()
        appState.playback.isPlaying = false

        let action = PlaybackAction.playingStateChanged(true)
        applyPlaybackReducer(action, to: &appState)

        XCTAssertTrue(appState.playback.isPlaying)
    }
}
