// SongsReducerTests.swift - Tests for songs reducer demo-play flow

import XCTest
@testable import SwiftVJCore
import SongRepository

final class SongsReducerTests: XCTestCase {

    private func applySongsReducer(_ action: SongsAction, to appState: inout AppState) -> Effect<AppAction> {
        var songsState = appState.songs
        let effect = songsReducer(state: &songsState, action: action, appState: &appState)
        appState.songs = songsState
        return effect
    }

    func testDemoPlayRequestedSelectsSongAndReturnsEffect() {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Title")

        let effect = applySongsReducer(.demoPlayRequested(songID), to: &appState)

        XCTAssertEqual(appState.songs.selectedSongId, songID)
        if case .none = effect.operation {
            XCTFail("Expected non-none effect for demo play request")
        }
    }

    func testDemoPlayStartedLogsInfo() {
        var appState = AppState()
        let songID = SongID(artist: "Daft Punk", title: "One More Time")

        let effect = applySongsReducer(.demoPlayStarted(songID), to: &appState)

        XCTAssertEqual(appState.songs.selectedSongId, songID)
        XCTAssertTrue(appState.ui.logEntries.contains { entry in
            entry.level == .info &&
                entry.message.contains("Demo Play") &&
                entry.message.contains("Daft Punk")
        })
        if case .none = effect.operation {
            // expected
        } else {
            XCTFail("Expected .none for demoPlayStarted")
        }
    }

    func testDemoPlayFailedLogsError() {
        var appState = AppState()
        let songID = SongID(artist: "Unknown", title: "Missing")

        let effect = applySongsReducer(.demoPlayFailed(songID, "Song not found"), to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { entry in
            entry.level == .error && entry.message.contains("Song not found")
        })
        if case .none = effect.operation {
            // expected
        } else {
            XCTFail("Expected .none for demoPlayFailed")
        }
    }

    func testStressDemoPlayRequestedFinalSelectionIsLastRequested() {
        var appState = AppState()
        let iterations = 250

        for i in 0..<iterations {
            let id = SongID(artist: "Artist\(i)", title: "Title\(i)")
            _ = applySongsReducer(.demoPlayRequested(id), to: &appState)
        }

        XCTAssertEqual(
            appState.songs.selectedSongId,
            SongID(artist: "Artist\(iterations - 1)", title: "Title\(iterations - 1)")
        )
    }
}
