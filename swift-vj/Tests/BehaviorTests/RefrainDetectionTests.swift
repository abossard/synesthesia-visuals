// Refrain Detection Tests - Pure function tests
// Tests the observable behavior of refrain/keyword detection

import XCTest
@testable import SwiftVJCore

final class RefrainDetectionTests: XCTestCase {

    // MARK: - Refrain Detection

    func test_detectRefrains_marksRepeatedLines() {
        // Given: Lines with repetition
        let lines = [
            LyricLine(timeSec: 0, text: "Unique line one"),
            LyricLine(timeSec: 5, text: "This is the chorus"),
            LyricLine(timeSec: 10, text: "Unique line two"),
            LyricLine(timeSec: 15, text: "This is the chorus"),  // Repeated
        ]

        // When: Detecting refrains
        let result = detectRefrains(lines)

        // Then: Repeated lines are marked as refrain
        XCTAssertEqual(result.count, 4)
        XCTAssertFalse(result[0].isRefrain, "Unique line should not be refrain")
        XCTAssertTrue(result[1].isRefrain, "First chorus occurrence should be refrain")
        XCTAssertFalse(result[2].isRefrain, "Unique line should not be refrain")
        XCTAssertTrue(result[3].isRefrain, "Second chorus occurrence should be refrain")
    }

    func test_detectRefrains_ignoresCaseAndPunctuation() {
        // Given: Lines that are same when normalized
        let lines = [
            LyricLine(timeSec: 0, text: "Hello World!"),
            LyricLine(timeSec: 5, text: "hello world"),
            LyricLine(timeSec: 10, text: "HELLO, WORLD"),
        ]

        // When: Detecting refrains
        let result = detectRefrains(lines)

        // Then: All are marked as refrain (same when normalized)
        XCTAssertTrue(result.allSatisfy { $0.isRefrain })
    }

    func test_detectRefrains_requiresAtLeastTwoOccurrences() {
        // Given: All unique lines
        let lines = [
            LyricLine(timeSec: 0, text: "Line one"),
            LyricLine(timeSec: 5, text: "Line two"),
            LyricLine(timeSec: 10, text: "Line three"),
        ]

        // When: Detecting refrains
        let result = detectRefrains(lines)

        // Then: None are marked as refrain
        XCTAssertTrue(result.allSatisfy { !$0.isRefrain })
    }

    func test_detectRefrains_returnsEmptyForEmptyInput() {
        XCTAssertEqual(detectRefrains([]).count, 0)
    }

    // MARK: - Keyword Extraction

    func test_extractKeywords_filtersStopWords() {
        // Given: Text with common stop words
        let text = "I am going to the store and buying some things"

        // When: Extracting keywords
        let keywords = extractKeywords(text)

        // Then: Only meaningful words remain
        XCTAssertFalse(keywords.contains("THE"))
        XCTAssertFalse(keywords.contains("AND"))
        XCTAssertFalse(keywords.contains("GOING"))  // "going" is also a stop word variant
        XCTAssertTrue(keywords.contains("STORE") || keywords.contains("BUYING") || keywords.contains("THINGS"))
    }

    func test_extractKeywords_limitsToMaxWords() {
        let text = "apple banana cherry date elderberry fig grape"

        // Default max is 3
        let keywords = extractKeywords(text)
        let wordCount = keywords.split(separator: " ").count

        XCTAssertLessThanOrEqual(wordCount, 3)
    }

    func test_extractKeywords_respectsCustomMaxWords() {
        let text = "apple banana cherry date elderberry"

        let keywords = extractKeywords(text, maxWords: 5)
        let wordCount = keywords.split(separator: " ").count

        XCTAssertEqual(wordCount, 5)
    }

    func test_extractKeywords_filtersShortWords() {
        let text = "I am a DJ in LA"

        let keywords = extractKeywords(text)

        // Words <= 2 chars should be filtered
        XCTAssertFalse(keywords.contains("AM"))
        XCTAssertFalse(keywords.contains("LA"))
        XCTAssertFalse(keywords.contains("DJ"))  // Only 2 chars
    }

    func test_extractKeywords_returnsUppercase() {
        let text = "beautiful sunset ocean"

        let keywords = extractKeywords(text)

        XCTAssertEqual(keywords, keywords.uppercased())
    }

    // MARK: - Active Line Detection

    func test_getActiveLineIndex_findsCorrectLine() {
        let lines = [
            LyricLine(timeSec: 0, text: "Line 0"),
            LyricLine(timeSec: 5, text: "Line 1"),
            LyricLine(timeSec: 10, text: "Line 2"),
            LyricLine(timeSec: 15, text: "Line 3"),
        ]

        // Before first line
        XCTAssertEqual(getActiveLineIndex(lines, position: -1), -1)

        // At or after each line
        XCTAssertEqual(getActiveLineIndex(lines, position: 0), 0)
        XCTAssertEqual(getActiveLineIndex(lines, position: 4.9), 0)
        XCTAssertEqual(getActiveLineIndex(lines, position: 5.0), 1)
        XCTAssertEqual(getActiveLineIndex(lines, position: 7.5), 1)
        XCTAssertEqual(getActiveLineIndex(lines, position: 10.0), 2)
        XCTAssertEqual(getActiveLineIndex(lines, position: 100.0), 3)
    }

    func test_getActiveLineIndex_returnsMinusOneForEmptyArray() {
        XCTAssertEqual(getActiveLineIndex([], position: 5.0), -1)
    }

    // MARK: - Integration: Full Analysis Pipeline

    func test_analyzeLyrics_setsRefrainAndKeywords() {
        let lines = [
            LyricLine(timeSec: 0, text: "Dancing in the moonlight"),
            LyricLine(timeSec: 5, text: "Everybody feeling warm and bright"),
            LyricLine(timeSec: 10, text: "Dancing in the moonlight"),  // Repeat
        ]

        let analyzed = analyzeLyrics(lines)

        // Check refrain detection
        XCTAssertTrue(analyzed[0].isRefrain)
        XCTAssertFalse(analyzed[1].isRefrain)
        XCTAssertTrue(analyzed[2].isRefrain)

        // Check keywords were extracted
        XCTAssertFalse(analyzed[0].keywords.isEmpty)
        XCTAssertTrue(analyzed[0].keywords.contains("DANCING") || analyzed[0].keywords.contains("MOONLIGHT"))
    }
}
