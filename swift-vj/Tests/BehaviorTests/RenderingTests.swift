// Rendering Tests - Pure function tests for visual rendering
// Tests audio processing and display state calculations

import XCTest
@testable import SwiftVJCore

final class RenderingTests: XCTestCase {

    // MARK: - Audio State Tests

    func test_audioState_silentIsInactive() {
        let state = AudioState.silent

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.level, 0)
        XCTAssertEqual(state.speed, 0.02)  // Floor speed
    }

    func test_audioState_levelAboveThresholdIsActive() {
        let state = AudioState(level: 0.5)

        XCTAssertTrue(state.isActive)
    }

    func test_audioState_averageLevelCalculation() {
        let state = AudioState(bass: 0.8, lowMid: 0.6, mid: 0.4, highs: 0.2)

        XCTAssertEqual(state.averageLevel, 0.5, accuracy: 0.001)
    }

    // MARK: - Synthetic Mouse Tests

    func test_syntheticMouse_centeredWithNoEnergy() {
        let mouse = calcSyntheticMouse(
            time: 0,
            energySlow: 0,
            bass: 0,
            mid: 0,
            beatPhase: 0
        )

        // At time=0, sin(0)=0, so should be near center
        XCTAssertEqual(mouse.x, 0.5, accuracy: 0.2)
        XCTAssertEqual(mouse.y, 0.5, accuracy: 0.2)
    }

    func test_syntheticMouse_expandsWithEnergy() {
        let lowEnergy = calcSyntheticMouse(
            time: Float.pi / 2,  // sin = 1
            energySlow: 0,
            bass: 0,
            mid: 0,
            beatPhase: 0
        )

        let highEnergy = calcSyntheticMouse(
            time: Float.pi / 2,
            energySlow: 1.0,
            bass: 0,
            mid: 0,
            beatPhase: 0
        )

        // Higher energy should move further from center
        let lowDistance = abs(lowEnergy.x - 0.5)
        let highDistance = abs(highEnergy.x - 0.5)

        XCTAssertGreaterThan(highDistance, lowDistance)
    }

    func test_syntheticMouse_staysInBounds() {
        // Test extreme values
        for time in stride(from: 0, through: Float.pi * 4, by: 0.1) {
            let mouse = calcSyntheticMouse(
                time: Float(time),
                energySlow: 1.0,
                bass: 1.0,
                mid: 1.0,
                beatPhase: 1.0
            )

            XCTAssertGreaterThanOrEqual(mouse.x, 0)
            XCTAssertLessThanOrEqual(mouse.x, 1)
            XCTAssertGreaterThanOrEqual(mouse.y, 0)
            XCTAssertLessThanOrEqual(mouse.y, 1)
        }
    }

    // MARK: - Lyrics Display State Tests

    func test_lyricsState_prevCurrentNextLines() {
        let lines = [
            LyricLine(timeSec: 0, text: "Line 0"),
            LyricLine(timeSec: 5, text: "Line 1"),
            LyricLine(timeSec: 10, text: "Line 2"),
        ]
        let state = LyricsDisplayState(lines: lines, activeIndex: 1)

        XCTAssertEqual(state.prevLine, "Line 0")
        XCTAssertEqual(state.currentLine, "Line 1")
        XCTAssertEqual(state.nextLine, "Line 2")
    }

    func test_lyricsState_firstLineHasNoPrev() {
        let lines = [
            LyricLine(timeSec: 0, text: "First"),
            LyricLine(timeSec: 5, text: "Second"),
        ]
        let state = LyricsDisplayState(lines: lines, activeIndex: 0)

        XCTAssertNil(state.prevLine)
        XCTAssertEqual(state.currentLine, "First")
        XCTAssertEqual(state.nextLine, "Second")
    }

    func test_lyricsState_lastLineHasNoNext() {
        let lines = [
            LyricLine(timeSec: 0, text: "First"),
            LyricLine(timeSec: 5, text: "Last"),
        ]
        let state = LyricsDisplayState(lines: lines, activeIndex: 1)

        XCTAssertEqual(state.prevLine, "First")
        XCTAssertEqual(state.currentLine, "Last")
        XCTAssertNil(state.nextLine)
    }

    func test_lyricsState_negativeIndexHasNoLines() {
        let lines = [LyricLine(timeSec: 0, text: "Test")]
        let state = LyricsDisplayState(lines: lines, activeIndex: -1)

        XCTAssertNil(state.prevLine)
        XCTAssertNil(state.currentLine)
        XCTAssertNil(state.nextLine)
    }

    // MARK: - Song Info Display State Tests

    func test_songInfoState_fadeEnvelopeTiming() {
        // Test fade in phase
        let fadeInOpacity = SongInfoDisplayState.opacityForTime(0.25)
        XCTAssertEqual(fadeInOpacity, 127.5, accuracy: 1)  // 50% of fade in

        // Test hold phase
        let holdOpacity = SongInfoDisplayState.opacityForTime(2.0)
        XCTAssertEqual(holdOpacity, 255)

        // Test fade out phase
        let fadeOutOpacity = SongInfoDisplayState.opacityForTime(6.0)
        XCTAssertLessThan(fadeOutOpacity, 255)
        XCTAssertGreaterThan(fadeOutOpacity, 0)

        // Test complete
        let completeOpacity = SongInfoDisplayState.opacityForTime(10.0)
        XCTAssertEqual(completeOpacity, 0)
    }

    func test_songInfoState_advancedUpdatesCorrectly() {
        let initial = SongInfoDisplayState.forTrack(artist: "Test", title: "Song")

        let after1s = initial.advanced(by: 1.0)
        XCTAssertEqual(after1s.displayTime, 1.0)
        XCTAssertTrue(after1s.active)
        XCTAssertEqual(after1s.opacity, 255, accuracy: 1)  // Should be in hold phase

        let after10s = initial.advanced(by: 10.0)
        XCTAssertFalse(after10s.active)
        XCTAssertEqual(after10s.opacity, 0, accuracy: 1)
    }

    // MARK: - Image Aspect Ratio Tests

    func test_aspectRatio_containWiderImage() {
        let dims = calcAspectRatioDimensions(
            imageWidth: 1920,
            imageHeight: 1080,
            bufferWidth: 1280,
            bufferHeight: 720,
            cover: false
        )

        // Image has same aspect ratio as buffer, should fill exactly
        XCTAssertEqual(dims.x, 0, accuracy: 1)
        XCTAssertEqual(dims.y, 0, accuracy: 1)
        XCTAssertEqual(dims.width, 1280, accuracy: 1)
        XCTAssertEqual(dims.height, 720, accuracy: 1)
    }

    func test_aspectRatio_containTallerImage() {
        let dims = calcAspectRatioDimensions(
            imageWidth: 1000,
            imageHeight: 1500,  // Taller than buffer
            bufferWidth: 1280,
            bufferHeight: 720,
            cover: false
        )

        // Should fit height, have horizontal letterboxing
        XCTAssertEqual(dims.height, 720, accuracy: 1)
        XCTAssertLessThan(dims.width, 1280)
        XCTAssertGreaterThan(dims.x, 0)  // Horizontal offset
    }

    func test_aspectRatio_coverWiderImage() {
        let dims = calcAspectRatioDimensions(
            imageWidth: 1920,
            imageHeight: 800,  // Wider than buffer
            bufferWidth: 1280,
            bufferHeight: 720,
            cover: true
        )

        // Should fill height, overflow width
        XCTAssertEqual(dims.height, 720, accuracy: 1)
        XCTAssertGreaterThan(dims.width, 1280)
        XCTAssertLessThan(dims.x, 0)  // Negative offset (cropped)
    }

    // MARK: - Easing Function Tests

    func test_easeInOutQuad_startsAtZero() {
        XCTAssertEqual(easeInOutQuad(0), 0, accuracy: 0.001)
    }

    func test_easeInOutQuad_endsAtOne() {
        XCTAssertEqual(easeInOutQuad(1), 1, accuracy: 0.001)
    }

    func test_easeInOutQuad_middleIsHalf() {
        XCTAssertEqual(easeInOutQuad(0.5), 0.5, accuracy: 0.001)
    }

    func test_easeInOutQuad_startsSlowly() {
        // Early values should be below linear
        let early = easeInOutQuad(0.25)
        XCTAssertLessThan(early, 0.25)
    }

    func test_easeInOutQuad_endsSlowly() {
        // Late values should be above linear
        let late = easeInOutQuad(0.75)
        XCTAssertGreaterThan(late, 0.75)
    }

    // MARK: - Helper Function Tests

    func test_lerp_interpolatesCorrectly() {
        XCTAssertEqual(lerp(0, 100, 0), 0)
        XCTAssertEqual(lerp(0, 100, 1), 100)
        XCTAssertEqual(lerp(0, 100, 0.5), 50)
        XCTAssertEqual(lerp(10, 20, 0.25), 12.5)
    }

    func test_clamp_constrainsValue() {
        XCTAssertEqual(clamp(5, 0, 10), 5)   // Within range
        XCTAssertEqual(clamp(-5, 0, 10), 0)  // Below min
        XCTAssertEqual(clamp(15, 0, 10), 10) // Above max
    }
}
