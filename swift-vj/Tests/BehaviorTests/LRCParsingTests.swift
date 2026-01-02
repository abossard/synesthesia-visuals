// LRC Parsing Tests - Pure function tests (no external dependencies)
// Following TDD: test observable behaviors, not implementation details

import XCTest
@testable import SwiftVJCore

final class LRCParsingTests: XCTestCase {

    // MARK: - Basic Parsing

    func test_parseLRC_extractsTimingsCorrectly() {
        // Given: LRC text with standard timestamps
        let lrc = """
        [00:05.12]Hello world
        [00:10.00]Goodbye world
        """

        // When: Parsing the LRC
        let lines = parseLRC(lrc)

        // Then: Correct number of lines with accurate timings
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].timeSec, 5.12, accuracy: 0.01)
        XCTAssertEqual(lines[0].text, "Hello world")
        XCTAssertEqual(lines[1].timeSec, 10.0, accuracy: 0.01)
        XCTAssertEqual(lines[1].text, "Goodbye world")
    }

    func test_parseLRC_handlesMillisecondsFormat() {
        // Given: LRC with 3-digit milliseconds (xxx format)
        let lrc = "[01:23.456]Milliseconds format"

        // When: Parsing
        let lines = parseLRC(lrc)

        // Then: Correct time calculation (1*60 + 23 + 0.456)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timeSec, 83.456, accuracy: 0.001)
    }

    func test_parseLRC_handlesCentisecondsFormat() {
        // Given: LRC with 2-digit centiseconds (xx format)
        let lrc = "[01:23.45]Centiseconds format"

        // When: Parsing
        let lines = parseLRC(lrc)

        // Then: Correct time calculation (1*60 + 23 + 0.45)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].timeSec, 83.45, accuracy: 0.01)
    }

    func test_parseLRC_skipsEmptyLines() {
        // Given: LRC with empty text lines
        let lrc = """
        [00:05.00]First line
        [00:10.00]
        [00:15.00]
        [00:20.00]Third line
        """

        // When: Parsing
        let lines = parseLRC(lrc)

        // Then: Only non-empty lines are included
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "First line")
        XCTAssertEqual(lines[1].text, "Third line")
    }

    func test_parseLRC_skipsMetadataLines() {
        // Given: LRC with metadata tags
        let lrc = """
        [ti:Song Title]
        [ar:Artist Name]
        [00:05.00]Actual lyric line
        """

        // When: Parsing
        let lines = parseLRC(lrc)

        // Then: Only lyric lines are included (metadata has non-numeric timestamps)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "Actual lyric line")
    }

    func test_parseLRC_returnsEmptyArrayForEmptyInput() {
        XCTAssertEqual(parseLRC("").count, 0)
        XCTAssertEqual(parseLRC("   ").count, 0)
        XCTAssertEqual(parseLRC("\n\n").count, 0)
    }

    func test_parseLRC_returnsSortedByTime() {
        // Given: LRC with out-of-order timestamps
        let lrc = """
        [00:20.00]Third
        [00:05.00]First
        [00:10.00]Second
        """

        // When: Parsing
        let lines = parseLRC(lrc)

        // Then: Lines are sorted by time
        XCTAssertEqual(lines.map { $0.text }, ["First", "Second", "Third"])
    }

    // MARK: - Real-world LRC Examples

    func test_parseLRC_handlesBohemianRhapsodyFormat() {
        // Real LRC format from LRCLIB
        let lrc = """
        [00:00.50]Is this the real life?
        [00:04.51]Is this just fantasy?
        [00:08.05]Caught in a landslide
        [00:11.82]No escape from reality
        """

        let lines = parseLRC(lrc)

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].text, "Is this the real life?")
        XCTAssertEqual(lines[3].timeSec, 11.82, accuracy: 0.01)
    }
}
