// KaraokeEngineTests.swift - End-to-end black box tests for karaoke functionality
// Following Grokking Simplicity: test behavior, not implementation

import XCTest
@testable import SwiftVJApp
@testable import SwiftVJCore

@MainActor
final class KaraokeEngineTests: XCTestCase {

    // MARK: - Test Data

    private func makeLyrics() -> [LyricLine] {
        [
            LyricLine(timeSec: 0.0, text: "First line"),
            LyricLine(timeSec: 2.0, text: "Second line"),
            LyricLine(timeSec: 4.0, text: "Third line"),
            LyricLine(timeSec: 6.0, text: "Fourth line"),
            LyricLine(timeSec: 8.0, text: "Fifth line")
        ]
    }

    // MARK: - Loading Lyrics

    func testLoadLyrics_engineReady() {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // After loading, engine is ready but no line is active yet until position update
        XCTAssertEqual(engine.displayState.totalLines, 5)
    }

    func testLoadEmptyLyrics_showsNoContent() {
        let engine = KaraokeEngine()
        engine.loadLyrics([])

        XCTAssertFalse(engine.displayState.hasLyrics)
        XCTAssertNil(engine.displayState.currentLine)
    }

    // MARK: - Position Updates Activate Lines

    func testUpdatePosition_activatesFirstLine() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // At position 0.5, should activate first line (timeSec 0.0)
        engine.updatePosition(0.5)

        // Give transition time to complete
        await waitForTransition()

        XCTAssertEqual(engine.displayState.currentLine, "First line")
        XCTAssertEqual(engine.displayState.nextLine, "Second line")
    }

    func testUpdatePosition_selectsCorrectLine() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // Position at 3.0 seconds should show "Second line" (timeSec: 2.0)
        engine.updatePosition(3.0)
        await waitForTransition()

        XCTAssertEqual(engine.displayState.currentLine, "Second line")
    }

    func testUpdatePosition_handlesExactTimecode() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // Exactly at timecode should show that line
        engine.updatePosition(4.0)
        await waitForTransition()

        XCTAssertEqual(engine.displayState.currentLine, "Third line")
    }

    func testUpdatePosition_progressesThroughSong() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // Start at beginning
        engine.updatePosition(0.5)
        await waitForTransition()
        XCTAssertEqual(engine.displayState.currentLine, "First line")

        // Move to second line
        engine.updatePosition(3.0)
        await waitForTransition()
        XCTAssertEqual(engine.displayState.currentLine, "Second line")

        // Move to fourth line
        engine.updatePosition(7.0)
        await waitForTransition()
        XCTAssertEqual(engine.displayState.currentLine, "Fourth line")
    }

    // MARK: - Manual Navigation

    func testNextLine_advancesToNextLyric() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // Start at first line
        engine.updatePosition(0.5)
        await waitForTransition()

        engine.nextLine()
        await waitForTransition()

        XCTAssertEqual(engine.displayState.currentLine, "Second line")
    }

    func testPreviousLine_goesBackToPreviousLyric() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // Start at third line
        engine.updatePosition(5.0)
        await waitForTransition()

        engine.previousLine()

        // Previous is instant (no transition)
        XCTAssertEqual(engine.displayState.currentLine, "Second line")
    }

    func testNextLine_stopsAtEnd() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        engine.updatePosition(0.5)
        await waitForTransition()

        // Try to go past the end
        for _ in 0..<10 {
            engine.nextLine()
            await waitForTransition()
        }

        XCTAssertEqual(engine.displayState.currentLine, "Fifth line")
    }

    func testPreviousLine_stopsAtBeginning() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        engine.updatePosition(5.0)
        await waitForTransition()

        // Go back multiple times
        for _ in 0..<10 {
            engine.previousLine()
        }

        XCTAssertEqual(engine.displayState.currentLine, "First line")
    }

    // MARK: - Display State Integrity

    func testDisplayState_prevNextCurrentConsistency() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        // Move to middle
        engine.updatePosition(5.0)
        await waitForTransition()

        XCTAssertEqual(engine.displayState.prevLine, "Second line")
        XCTAssertEqual(engine.displayState.currentLine, "Third line")
        XCTAssertEqual(engine.displayState.nextLine, "Fourth line")
    }

    func testDisplayState_atFirstLine_noPrevLine() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        engine.updatePosition(0.5)
        await waitForTransition()

        XCTAssertNil(engine.displayState.prevLine)
        XCTAssertNotNil(engine.displayState.currentLine)
        XCTAssertNotNil(engine.displayState.nextLine)
    }

    func testDisplayState_atLastLine_noNextLine() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())

        engine.updatePosition(10.0)
        await waitForTransition()

        XCTAssertNotNil(engine.displayState.prevLine)
        XCTAssertEqual(engine.displayState.currentLine, "Fifth line")
        XCTAssertNil(engine.displayState.nextLine)
    }

    // MARK: - Configuration Presets

    func testConfigurationPresets_haveDistinctValues() {
        let defaultConfig = KaraokeConfiguration.default
        let compactConfig = KaraokeConfiguration.compact
        let dramaticConfig = KaraokeConfiguration.dramatic

        // Compact should have smaller fonts
        XCTAssertLessThan(compactConfig.currentFontSize, defaultConfig.currentFontSize)

        // Dramatic should have larger fonts
        XCTAssertGreaterThan(dramaticConfig.currentFontSize, defaultConfig.currentFontSize)
    }

    func testConfigurationPreset_appliedToEngine() {
        let engine = KaraokeEngine()

        engine.configuration = .dramatic

        XCTAssertEqual(engine.configuration.currentFontSize, KaraokeConfiguration.dramatic.currentFontSize)
        XCTAssertEqual(engine.configuration.transitionDuration, KaraokeConfiguration.dramatic.transitionDuration)
    }

    // MARK: - Reset

    func testReset_clearsAllState() async {
        let engine = KaraokeEngine()
        engine.loadLyrics(makeLyrics())
        engine.updatePosition(5.0)
        await waitForTransition()

        engine.reset()

        XCTAssertFalse(engine.displayState.hasLyrics)
        XCTAssertNil(engine.displayState.currentLine)
    }

    // MARK: - Test Lyrics Loading

    func testLoadTestLyrics_loadsMultipleLines() {
        let engine = KaraokeEngine()

        engine.loadTestLyrics()

        XCTAssertTrue(engine.displayState.hasLyrics)
        XCTAssertGreaterThan(engine.displayState.totalLines, 0)
        // loadTestLyrics sets currentIndex to 2, so current line should be set
        XCTAssertNotNil(engine.displayState.currentLine)
    }

    // MARK: - Helpers

    private func waitForTransition() async {
        // Wait for transition animation to complete (max 0.8 seconds for dramatic preset)
        try? await Task.sleep(nanoseconds: 800_000_000)
    }
}

// MARK: - Display State Tests

@MainActor
final class KaraokeDisplayStateTests: XCTestCase {

    func testEmptyState_hasCorrectDefaults() {
        let state = KaraokeDisplayState.empty

        XCTAssertNil(state.currentLine)
        XCTAssertNil(state.nextLine)
        XCTAssertNil(state.prevLine)
        XCTAssertFalse(state.hasLyrics)
        XCTAssertEqual(state.transitionProgress, 0)
        XCTAssertFalse(state.isTransitioning)
    }

    func testCreateState_withValidIndex() {
        let lines = ["First", "Second", "Third"]
        let state = KaraokeDisplayState.create(lines: lines, activeIndex: 1)

        XCTAssertEqual(state.prevLine, "First")
        XCTAssertEqual(state.currentLine, "Second")
        XCTAssertEqual(state.nextLine, "Third")
        XCTAssertEqual(state.totalLines, 3)
        XCTAssertEqual(state.activeIndex, 1)
    }

    func testCreateState_atFirstIndex() {
        let lines = ["First", "Second", "Third"]
        let state = KaraokeDisplayState.create(lines: lines, activeIndex: 0)

        XCTAssertNil(state.prevLine)
        XCTAssertEqual(state.currentLine, "First")
        XCTAssertEqual(state.nextLine, "Second")
    }

    func testCreateState_atLastIndex() {
        let lines = ["First", "Second", "Third"]
        let state = KaraokeDisplayState.create(lines: lines, activeIndex: 2)

        XCTAssertEqual(state.prevLine, "Second")
        XCTAssertEqual(state.currentLine, "Third")
        XCTAssertNil(state.nextLine)
    }

    func testCreateState_withNegativeIndex_showsNoCurrentLine() {
        let lines = ["First", "Second", "Third"]
        let state = KaraokeDisplayState.create(lines: lines, activeIndex: -1)

        XCTAssertNil(state.currentLine)
        XCTAssertEqual(state.nextLine, "First")
        XCTAssertEqual(state.totalLines, 3)
    }

    func testInterpolatedValues_atZeroProgress() {
        let state = KaraokeDisplayState(
            prevLine: "Prev",
            currentLine: "Current",
            nextLine: "Next",
            upcomingNextLine: "Upcoming",
            activeIndex: 1,
            totalLines: 4,
            transitionProgress: 0,
            isTransitioning: true
        )
        let config = KaraokeConfiguration.default

        // At progress 0, current line should be at its normal position
        let currentY = state.currentLineY(config: config)
        XCTAssertEqual(currentY, config.currentLineYAbsolute, accuracy: 1.0)
    }

    func testInterpolatedValues_atFullProgress() {
        let state = KaraokeDisplayState(
            prevLine: "Prev",
            currentLine: "Current",
            nextLine: "Next",
            upcomingNextLine: "Upcoming",
            activeIndex: 1,
            totalLines: 4,
            transitionProgress: 1.0,
            isTransitioning: true
        )
        let config = KaraokeConfiguration.default

        // At progress 1, current line should have moved to exit position
        let currentY = state.currentLineY(config: config)
        XCTAssertEqual(currentY, config.prevLineYAbsolute, accuracy: 1.0)
    }

    func testProgressText_formatsCorrectly() {
        let state = KaraokeDisplayState(
            prevLine: "Prev",
            currentLine: "Current",
            nextLine: "Next",
            upcomingNextLine: nil,
            activeIndex: 2,
            totalLines: 5,
            transitionProgress: 0,
            isTransitioning: false
        )

        XCTAssertEqual(state.progressText, "3 / 5")
    }
}

// MARK: - Configuration Tests

final class KaraokeConfigurationTests: XCTestCase {

    func testDefaultConfiguration_hasReasonableValues() {
        let config = KaraokeConfiguration.default

        XCTAssertGreaterThan(config.currentFontSize, 0)
        XCTAssertGreaterThan(config.nextFontSize, 0)
        XCTAssertGreaterThan(config.transitionDuration, 0)
        XCTAssertGreaterThanOrEqual(config.currentLineOpacity, 0)
        XCTAssertLessThanOrEqual(config.currentLineOpacity, 1)
        XCTAssertGreaterThanOrEqual(config.nextLineOpacity, 0)
        XCTAssertLessThanOrEqual(config.nextLineOpacity, 1)
    }

    func testConfiguration_absoluteYPositions() {
        let config = KaraokeConfiguration.default

        // Positions should be ordered: prev < current < next (top to bottom)
        XCTAssertLessThan(config.prevLineYAbsolute, config.currentLineYAbsolute)
        XCTAssertLessThan(config.currentLineYAbsolute, config.nextLineYAbsolute)
    }

    func testConfiguration_encodingDecoding() throws {
        let original = KaraokeConfiguration.dramatic

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KaraokeConfiguration.self, from: encoded)

        XCTAssertEqual(decoded.currentFontSize, original.currentFontSize)
        XCTAssertEqual(decoded.transitionDuration, original.transitionDuration)
        XCTAssertEqual(decoded.animationMode, original.animationMode)
    }

    func testAllPresets_areValid() {
        let presets: [KaraokeConfiguration] = [.default, .compact, .dramatic, .subtle, .clean]

        for preset in presets {
            XCTAssertGreaterThan(preset.currentFontSize, 0, "Font size should be positive")
            XCTAssertGreaterThan(preset.canvasWidth, 0, "Canvas width should be positive")
            XCTAssertGreaterThan(preset.canvasHeight, 0, "Canvas height should be positive")
        }
    }
}
