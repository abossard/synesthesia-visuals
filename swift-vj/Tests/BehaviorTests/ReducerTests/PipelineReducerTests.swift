// PipelineReducerTests.swift - Tests for pipeline reducer
// Pure function tests for pipeline state transitions

import XCTest
@testable import SwiftVJCore

final class PipelineReducerTests: XCTestCase {

    // Helper to avoid overlapping access issues when calling reducers
    private func applyPipelineReducer(_ action: PipelineAction, to appState: inout AppState) -> Effect<AppAction> {
        var pipelineState = appState.pipeline
        let effect = pipelineReducer(state: &pipelineState, action: action, appState: &appState)
        appState.pipeline = pipelineState
        return effect
    }

    // MARK: - Start Processing

    func testStartProcessingSetsProcessingState() {
        var appState = AppState()
        let track = Track(artist: "Test", title: "Song")

        let action = PipelineAction.startProcessing(track)
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertTrue(appState.pipeline.isProcessing)
        XCTAssertEqual(appState.pipeline.processingTrackKey, track.key)
        XCTAssertNil(appState.pipeline.error)
    }

    func testStartProcessingResetsSteps() {
        var appState = AppState()
        appState.pipeline.steps = [
            PipelineStepState(name: "lyrics", status: "done"),
            PipelineStepState(name: "ai", status: "done")
        ]

        let track = Track(artist: "Test", title: "Song")
        let action = PipelineAction.startProcessing(track)
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertEqual(appState.pipeline.steps.count, 5)
        XCTAssertTrue(appState.pipeline.steps.allSatisfy { $0.status == "pending" })
    }

    func testStartProcessingSkipsIfAlreadyProcessingSameTrack() {
        var appState = AppState()
        let track = Track(artist: "Test", title: "Song")

        // Start processing
        appState.pipeline.isProcessing = true
        appState.pipeline.processingTrackKey = track.key

        // Try to process same track again
        let action = PipelineAction.startProcessing(track)
        let effect = applyPipelineReducer(action, to: &appState)

        // Should return .none (no effect)
        if case .none = effect.operation {
            // Expected
        } else {
            XCTFail("Expected .none effect")
        }
    }

    // MARK: - Step Started

    func testStepStartedUpdatesStepStatus() {
        var appState = AppState()
        appState.pipeline.steps = PipelineStepState.defaultSteps

        let action = PipelineAction.stepStarted("lyrics")
        _ = applyPipelineReducer(action, to: &appState)

        let lyricsStep = appState.pipeline.steps.first { $0.name == "lyrics" }
        XCTAssertEqual(lyricsStep?.status, "running")
    }

    // MARK: - Step Completed

    func testStepCompletedUpdatesStepStatus() {
        var appState = AppState()
        appState.pipeline.steps = PipelineStepState.defaultSteps

        let status = PipelineStepStatus.lyrics(lineCount: 42, refrainCount: 4, keywordCount: 10)
        let action = PipelineAction.stepCompleted("lyrics", status)
        _ = applyPipelineReducer(action, to: &appState)

        let lyricsStep = appState.pipeline.steps.first { $0.name == "lyrics" }
        XCTAssertTrue(lyricsStep?.status.contains("42 lines") ?? false)
    }

    func testStepCompletedWithAILogsKeywords() {
        var appState = AppState()
        appState.pipeline.steps = PipelineStepState.defaultSteps

        let status = PipelineStepStatus.ai(
            mood: "energetic",
            energy: 0.8,
            valence: 0.6,
            keywords: ["dance", "party", "night"],
            themes: ["celebration", "freedom"]
        )
        let action = PipelineAction.stepCompleted("ai", status)
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("dance") })
        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("celebration") })
    }

    // MARK: - Processing Completed

    func testProcessingCompletedUpdatesState() {
        var appState = AppState()
        appState.pipeline.isProcessing = true

        let result = PipelineResult(
            artist: "Test",
            title: "Song",
            success: true,
            lyricsFound: true,
            lyricsLineCount: 50,
            mood: "happy",
            energy: 0.7,
            valence: 0.5,
            shaderMatched: true,
            shaderName: "rainbow",
            imagesFound: true,
            imagesCount: 10,
            totalTimeMs: 1500
        )

        let action = PipelineAction.processingCompleted(result)
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertFalse(appState.pipeline.isProcessing)
        XCTAssertEqual(appState.pipeline.result?.artist, "Test")
        XCTAssertEqual(appState.pipeline.result?.totalTimeMs, 1500)
    }

    func testProcessingCompletedLogsResult() {
        var appState = AppState()

        let result = PipelineResult(
            artist: "Artist",
            title: "Title",
            success: true,
            totalTimeMs: 2000
        )

        let action = PipelineAction.processingCompleted(result)
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("2000ms") })
    }

    // MARK: - Processing Failed

    func testProcessingFailedUpdatesState() {
        var appState = AppState()
        appState.pipeline.isProcessing = true

        let action = PipelineAction.processingFailed("Network error")
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertFalse(appState.pipeline.isProcessing)
        XCTAssertEqual(appState.pipeline.error, "Network error")
    }

    func testProcessingFailedLogsError() {
        var appState = AppState()

        let action = PipelineAction.processingFailed("Timeout")
        _ = applyPipelineReducer(action, to: &appState)

        let errorLog = appState.ui.logEntries.first { $0.level == .error }
        XCTAssertTrue(errorLog?.message.contains("Timeout") ?? false)
    }

    // MARK: - Reset

    func testResetClearsState() {
        var appState = AppState()
        appState.pipeline.isProcessing = true
        appState.pipeline.processingTrackKey = "some::key"
        appState.pipeline.error = "previous error"
        appState.pipeline.expandedStepNames = ["lyrics", "ai"]

        let action = PipelineAction.reset
        _ = applyPipelineReducer(action, to: &appState)

        XCTAssertFalse(appState.pipeline.isProcessing)
        XCTAssertNil(appState.pipeline.processingTrackKey)
        XCTAssertNil(appState.pipeline.error)
        XCTAssertTrue(appState.pipeline.steps.allSatisfy { $0.status == "pending" })
        XCTAssertTrue(appState.pipeline.expandedStepNames.isEmpty)
    }

    // MARK: - Step Expansion

    func testToggleStepExpansionExpandsAndCollapses() {
        var appState = AppState()

        _ = applyPipelineReducer(.toggleStepExpansion("lyrics"), to: &appState)
        XCTAssertTrue(appState.pipeline.expandedStepNames.contains("lyrics"))

        _ = applyPipelineReducer(.toggleStepExpansion("lyrics"), to: &appState)
        XCTAssertFalse(appState.pipeline.expandedStepNames.contains("lyrics"))
    }
}
