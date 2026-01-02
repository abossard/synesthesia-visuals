// Settings Tests - Test persistence behavior
// Following TDD: test observable behaviors, not implementation details

import XCTest
@testable import SwiftVJCore

final class SettingsTests: XCTestCase {

    var tempDirectory: URL!
    var tempSettingsFile: URL!

    override func setUp() async throws {
        // Create a temp directory for isolated test settings
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        tempSettingsFile = tempDirectory.appendingPathComponent("test_settings.json")
    }

    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Default Values

    func test_settings_defaultsWhenNoFile() async {
        // Given: No settings file exists
        let settings = Settings(filePath: tempSettingsFile)

        // Then: Defaults are returned
        let offset = await settings.timingOffsetMs
        XCTAssertEqual(offset, 0, "Default timing offset should be 0")

        let source = await settings.playbackSource
        XCTAssertEqual(source, "", "Default playback source should be empty")
    }

    // MARK: - Timing Offset

    func test_settings_timingOffsetPersists() async {
        // Given: Settings with custom timing offset
        let settings = Settings(filePath: tempSettingsFile)
        await settings.setTimingOffset(500)

        // When: Creating new settings instance from same file
        let reloaded = Settings(filePath: tempSettingsFile)
        let offset = await reloaded.timingOffsetMs

        // Then: Value persists
        XCTAssertEqual(offset, 500)
    }

    func test_settings_adjustTimingByDelta() async {
        // Given: Settings with initial offset
        let settings = Settings(filePath: tempSettingsFile)
        await settings.setTimingOffset(100)

        // When: Adjusting by delta
        let newOffset = await settings.adjustTiming(by: 200)

        // Then: Offset is adjusted
        XCTAssertEqual(newOffset, 300)

        // And can be read back
        let stored = await settings.timingOffsetMs
        XCTAssertEqual(stored, 300)
    }

    func test_settings_timingOffsetSec() async {
        // Given: Settings with millisecond offset
        let settings = Settings(filePath: tempSettingsFile)
        await settings.setTimingOffset(1500)

        // When: Reading as seconds
        let offsetSec = await settings.timingOffsetSec

        // Then: Converted correctly
        XCTAssertEqual(offsetSec, 1.5, accuracy: 0.001)
    }

    // MARK: - Playback Source

    func test_settings_playbackSourcePersists() async {
        // Given: Settings with playback source
        let settings = Settings(filePath: tempSettingsFile)
        await settings.setPlaybackSource("vdj_osc")

        // When: Creating new instance
        let reloaded = Settings(filePath: tempSettingsFile)
        let source = await reloaded.playbackSource

        // Then: Value persists
        XCTAssertEqual(source, "vdj_osc")
    }

    // MARK: - Startup Preferences

    func test_settings_startSynesthesiaPersists() async {
        // Given: Settings with startup preference
        let settings = Settings(filePath: tempSettingsFile)
        await settings.setStartSynesthesia(true)

        // When: Creating new instance
        let reloaded = Settings(filePath: tempSettingsFile)
        let start = await reloaded.startSynesthesia

        // Then: Value persists
        XCTAssertTrue(start)
    }

    // MARK: - Poll Interval

    func test_settings_playbackPollIntervalClamped() async {
        // Given: Default settings
        let settings = Settings(filePath: tempSettingsFile)

        // When: Reading poll interval
        let interval = await settings.playbackPollIntervalMs

        // Then: Within valid range (1000-10000)
        XCTAssertGreaterThanOrEqual(interval, 1000)
        XCTAssertLessThanOrEqual(interval, 10000)
    }
}
