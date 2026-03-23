@testable import SwiftVJCore
import SongRepository
import XCTest

final class PreviewReducerTests: XCTestCase {

    // MARK: - Helpers

    private func makeSongID(_ name: String) -> SongID {
        SongID(artist: "Artist", title: name)
    }

    private func makeSong(_ name: String, duration: Double = 180, audioFilePath: String? = nil) -> Song {
        let path = audioFilePath ?? "/audio/\(name).mp3"
        return Song(id: makeSongID(name), artist: "Artist", title: name, duration: duration, audioFilePath: path)
    }

    private func makeSongNoAudio(_ name: String, duration: Double = 180) -> Song {
        Song(id: makeSongID(name), artist: "Artist", title: name, duration: duration, audioFilePath: nil)
    }

    private func makeSongsState(_ songs: [Song]) -> SongsSubState {
        SongsSubState(displayedSongs: songs)
    }

    private func apply(
        _ action: PreviewAction,
        to state: inout PreviewSubState,
        songs: SongsSubState = SongsSubState(displayedSongs: [])
    ) -> Effect<AppAction> {
        previewReducer(state: &state, action: action, songs: songs)
    }

    // MARK: - play

    func testPlaySetsSongStateAndReturnsEffect() {
        let song = makeSong("TestSong", duration: 200)
        var state = PreviewSubState()
        let songs = makeSongsState([song])

        let effect = apply(.play(song.id), to: &state, songs: songs)

        XCTAssertEqual(state.currentSongId, song.id)
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.duration, 200)
        XCTAssertEqual(state.audioFilePath, "/audio/TestSong.mp3")
        XCTAssertEqual(state.currentPosition, 0)

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for play")
        }
    }

    func testPlayWithNoAudioFilePathReturnsNoneAndLeavesStateUnchanged() {
        let song = makeSongNoAudio("NoFile")
        var state = PreviewSubState()
        let songs = makeSongsState([song])

        let effect = apply(.play(song.id), to: &state, songs: songs)

        XCTAssertNil(state.currentSongId)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.duration, 0)
        XCTAssertNil(state.audioFilePath)

        if case .none = effect.operation {
            // expected
        } else {
            XCTFail("Expected .none effect when audioFilePath is nil")
        }
    }

    func testPlayWithPreviewStartOffsetSetsCurrentPosition() {
        let song = makeSong("OffsetSong", duration: 100)
        var state = PreviewSubState(previewStartOffset: 0.25)
        let songs = makeSongsState([song])

        let effect = apply(.play(song.id), to: &state, songs: songs)

        XCTAssertEqual(state.currentPosition, 25, accuracy: 0.001)
        XCTAssertTrue(state.isPlaying)

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for play with offset")
        }
    }

    func testPlayNewSongWhileAnotherIsPlayingReplacesCurrentSong() {
        let songA = makeSong("SongA", duration: 120)
        let songB = makeSong("SongB", duration: 240)
        var state = PreviewSubState(
            currentSongId: songA.id,
            isPlaying: true,
            currentPosition: 60,
            duration: 120,
            audioFilePath: "/audio/SongA.mp3"
        )
        let songs = makeSongsState([songA, songB])

        let effect = apply(.play(songB.id), to: &state, songs: songs)

        XCTAssertEqual(state.currentSongId, songB.id)
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.duration, 240)
        XCTAssertEqual(state.audioFilePath, "/audio/SongB.mp3")
        XCTAssertEqual(state.currentPosition, 0)

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for play replacement")
        }
    }

    // MARK: - pause

    func testPauseSetsIsPlayingFalse() {
        var state = PreviewSubState(
            currentSongId: makeSongID("Song"),
            isPlaying: true,
            currentPosition: 30,
            duration: 180
        )

        let effect = apply(.pause, to: &state)

        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.currentPosition, 30)
        XCTAssertEqual(state.currentSongId, makeSongID("Song"))

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for pause")
        }
    }

    // MARK: - resume

    func testResumeSetsIsPlayingTrue() {
        var state = PreviewSubState(
            currentSongId: makeSongID("Song"),
            isPlaying: false,
            currentPosition: 30,
            duration: 180
        )

        let effect = apply(.resume, to: &state)

        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.currentPosition, 30)

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for resume")
        }
    }

    // MARK: - stop

    func testStopResetsAllState() {
        var state = PreviewSubState(
            currentSongId: makeSongID("Song"),
            isPlaying: true,
            currentPosition: 90,
            duration: 180,
            previewStartOffset: 0.5,
            audioFilePath: "/audio/Song.mp3"
        )

        let effect = apply(.stop, to: &state)

        XCTAssertNil(state.currentSongId)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.currentPosition, 0)
        XCTAssertEqual(state.duration, 0)
        XCTAssertEqual(state.previewStartOffset, 0.5, "previewStartOffset should be preserved")
        XCTAssertNil(state.audioFilePath)

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for stop")
        }
    }

    // MARK: - seekTo

    func testSeekToUpdatesCurrentPosition() {
        var state = PreviewSubState(
            currentSongId: makeSongID("Song"),
            isPlaying: true,
            currentPosition: 10,
            duration: 180
        )

        let effect = apply(.seekTo(45.0), to: &state)

        XCTAssertEqual(state.currentPosition, 45.0)
        XCTAssertTrue(state.isPlaying)

        if case .none = effect.operation {
            XCTFail("Expected non-none effect for seekTo")
        }
    }

    // MARK: - setPreviewStart

    func testSetPreviewStartUpdatesOffset() {
        var state = PreviewSubState()

        let effect = apply(.setPreviewStart(0.4), to: &state)

        XCTAssertEqual(state.previewStartOffset, 0.4, accuracy: 0.001)

        if case .none = effect.operation {
            // expected
        } else {
            XCTFail("Expected .none effect for setPreviewStart")
        }
    }

    func testSetPreviewStartClampsToZeroOne() {
        var state = PreviewSubState()

        _ = apply(.setPreviewStart(-0.5), to: &state)
        XCTAssertEqual(state.previewStartOffset, 0.0)

        _ = apply(.setPreviewStart(1.5), to: &state)
        XCTAssertEqual(state.previewStartOffset, 1.0)
    }

    // MARK: - positionUpdated

    func testPositionUpdatedUpdatesPositionAndDuration() {
        var state = PreviewSubState(
            currentSongId: makeSongID("Song"),
            isPlaying: true,
            currentPosition: 10,
            duration: 180
        )

        let effect = apply(.positionUpdated(position: 55.0, duration: 200.0), to: &state)

        XCTAssertEqual(state.currentPosition, 55.0)
        XCTAssertEqual(state.duration, 200.0)
        XCTAssertTrue(state.isPlaying)

        if case .none = effect.operation {
            // expected
        } else {
            XCTFail("Expected .none effect for positionUpdated")
        }
    }

    // MARK: - playbackFinished

    func testPlaybackFinishedSetsIsPlayingFalseAndKeepsSongId() {
        let songId = makeSongID("Song")
        var state = PreviewSubState(
            currentSongId: songId,
            isPlaying: true,
            currentPosition: 180,
            duration: 180,
            audioFilePath: "/audio/Song.mp3"
        )

        let effect = apply(.playbackFinished, to: &state)

        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.currentSongId, songId)
        XCTAssertEqual(state.audioFilePath, "/audio/Song.mp3")

        if case .none = effect.operation {
            // expected
        } else {
            XCTFail("Expected .none effect for playbackFinished")
        }
    }
}
