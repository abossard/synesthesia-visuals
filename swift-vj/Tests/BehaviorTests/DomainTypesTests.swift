// Domain Types Tests - Test value semantics and computed properties
// These are behavior tests, not implementation tests

import XCTest
@testable import SwiftVJCore

final class DomainTypesTests: XCTestCase {

    // MARK: - Track

    func test_track_keyIsConsistent() {
        let track = Track(artist: "Queen", title: "Bohemian Rhapsody")

        XCTAssertEqual(track.key, "Queen::Bohemian Rhapsody")
    }

    func test_track_displayNameFormatted() {
        let track = Track(artist: "Queen", title: "Bohemian Rhapsody")

        XCTAssertEqual(track.displayName, "Queen - Bohemian Rhapsody")
    }

    // MARK: - PlaybackState

    func test_playbackState_progressCalculation() {
        let track = Track(artist: "Test", title: "Test", duration: 200)
        let state = PlaybackState(track: track, position: 100)

        XCTAssertEqual(state.progress, 0.5, accuracy: 0.001)
    }

    func test_playbackState_progressZeroWithoutTrack() {
        let state = PlaybackState(track: nil, position: 100)

        XCTAssertEqual(state.progress, 0)
    }

    func test_playbackState_progressClampedToOne() {
        let track = Track(artist: "Test", title: "Test", duration: 100)
        let state = PlaybackState(track: track, position: 200)  // Past end

        XCTAssertEqual(state.progress, 1.0)
    }

    func test_playbackState_withPositionCreatesNewState() {
        let track = Track(artist: "Test", title: "Test")
        let state = PlaybackState(track: track, position: 10)

        let updated = state.withPosition(20)

        XCTAssertEqual(state.position, 10, "Original should be unchanged")
        XCTAssertEqual(updated.position, 20, "New state should have updated position")
    }

    func test_playbackState_withTrackResetsPosition() {
        let track1 = Track(artist: "Artist1", title: "Song1")
        let track2 = Track(artist: "Artist2", title: "Song2")
        let state = PlaybackState(track: track1, position: 100)

        let updated = state.withTrack(track2)

        XCTAssertEqual(updated.track?.artist, "Artist2")
        XCTAssertEqual(updated.position, 0, "Position should reset on track change")
    }

    // MARK: - SongCategories

    func test_songCategories_getTopSortsByScore() {
        let categories = SongCategories(scores: [
            "happy": 0.3,
            "energetic": 0.8,
            "dark": 0.1,
            "calm": 0.5
        ])

        let top3 = categories.getTop(3)

        XCTAssertEqual(top3.count, 3)
        XCTAssertEqual(top3[0].name, "energetic")
        XCTAssertEqual(top3[1].name, "calm")
        XCTAssertEqual(top3[2].name, "happy")
    }

    func test_songCategories_primaryMoodFromHighestScore() {
        let categories = SongCategories(scores: [
            "happy": 0.3,
            "dark": 0.9,
        ])

        XCTAssertEqual(categories.primaryMood, "dark")
    }

    func test_songCategories_scoreForCategory() {
        let categories = SongCategories(scores: ["happy": 0.75])

        XCTAssertEqual(categories.score(for: "happy"), 0.75)
        XCTAssertEqual(categories.score(for: "nonexistent"), 0)
    }

    // MARK: - LyricLine Immutability

    func test_lyricLine_withRefrainCreatesNewInstance() {
        let line = LyricLine(timeSec: 5, text: "Hello", isRefrain: false)

        let updated = line.withRefrain(true)

        XCTAssertFalse(line.isRefrain, "Original unchanged")
        XCTAssertTrue(updated.isRefrain, "New instance has updated value")
        XCTAssertEqual(line.text, updated.text, "Other fields preserved")
    }

    func test_lyricLine_withKeywordsCreatesNewInstance() {
        let line = LyricLine(timeSec: 5, text: "Hello World")

        let updated = line.withKeywords("HELLO WORLD")

        XCTAssertEqual(line.keywords, "")
        XCTAssertEqual(updated.keywords, "HELLO WORLD")
    }

    // MARK: - Energy/Valence Calculations

    func test_calculateEnergy_highForEnergeticCategories() {
        let scores: [String: Double] = [
            "energetic": 0.9,
            "aggressive": 0.7,
            "calm": 0.1
        ]

        let energy = calculateEnergy(from: scores)

        XCTAssertGreaterThan(energy, 0.7)
    }

    func test_calculateEnergy_lowForCalmCategories() {
        let scores: [String: Double] = [
            "calm": 0.9,
            "peaceful": 0.8,
            "sad": 0.7,
            "energetic": 0.1
        ]

        let energy = calculateEnergy(from: scores)

        XCTAssertLessThan(energy, 0.3)
    }

    func test_calculateEnergy_neutralWhenEmpty() {
        let energy = calculateEnergy(from: [:])

        XCTAssertEqual(energy, 0.5)
    }

    func test_calculateValence_positiveForHappyCategories() {
        let scores: [String: Double] = [
            "happy": 0.9,
            "uplifting": 0.8,
            "dark": 0.1
        ]

        let valence = calculateValence(from: scores)

        XCTAssertGreaterThan(valence, 0)
    }

    func test_calculateValence_negativeForDarkCategories() {
        let scores: [String: Double] = [
            "dark": 0.9,
            "sad": 0.8,
            "death": 0.7,
            "happy": 0.1
        ]

        let valence = calculateValence(from: scores)

        XCTAssertLessThan(valence, 0)
    }

    // MARK: - Cache Filename

    func test_sanitizeCacheFilename_removesSpecialChars() {
        let filename = sanitizeCacheFilename(artist: "AC/DC", title: "Back in Black!")

        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains("!"))
        XCTAssertTrue(filename.contains("acdc"))
        XCTAssertTrue(filename.contains("back"))
    }

    func test_sanitizeCacheFilename_lowercasesAndJoins() {
        let filename = sanitizeCacheFilename(artist: "The Beatles", title: "Hey Jude")

        XCTAssertEqual(filename, filename.lowercased())
        XCTAssertTrue(filename.contains("beatles"))
        XCTAssertTrue(filename.contains("jude"))
    }
}
