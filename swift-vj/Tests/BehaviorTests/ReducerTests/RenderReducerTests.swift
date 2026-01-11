// RenderReducerTests.swift - Tests for render reducer
// Pure function tests for render state transitions

import XCTest
@testable import SwiftVJCore

final class RenderReducerTests: XCTestCase {

    // MARK: - Select Shader

    func testSelectShaderUpdatesState() {
        var appState = AppState()

        let action = RenderAction.selectShader("rainbow")
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.selectedShader, "rainbow")
    }

    func testSelectShaderLogsMessage() {
        var appState = AppState()

        let action = RenderAction.selectShader("plasma")
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("plasma") })
    }

    // MARK: - Shader Selected

    func testShaderSelectedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.shaderSelected("waves")
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.selectedShader, "waves")
    }

    // MARK: - Select Phase

    func testSelectPhaseUpdatesState() {
        var appState = AppState()

        let action = RenderAction.selectPhase(.peak)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.currentPhase, .peak)
    }

    func testSelectPhaseNilUpdatesState() {
        var appState = AppState()
        appState.render.currentPhase = .buildup

        let action = RenderAction.selectPhase(nil)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertNil(appState.render.currentPhase)
    }

    func testSelectPhaseLogsMessage() {
        var appState = AppState()

        let action = RenderAction.selectPhase(.disco)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("Disco") })
    }

    // MARK: - Phase Detected

    func testPhaseDetectedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.phaseDetected(.release)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.detectedSongPhase, .release)
    }

    // MARK: - Image Navigation

    func testSetImageIndexUpdatesState() {
        var appState = AppState()
        appState.render.imageCount = 10

        let action = RenderAction.setImageIndex(5)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.imageIndex, 5)
    }

    func testNextImageWrapsAround() {
        var appState = AppState()
        appState.render.imageIndex = 9
        appState.render.imageCount = 10

        let action = RenderAction.nextImage
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.imageIndex, 0)
    }

    func testNextImageIncrements() {
        var appState = AppState()
        appState.render.imageIndex = 3
        appState.render.imageCount = 10

        let action = RenderAction.nextImage
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.imageIndex, 4)
    }

    func testPrevImageWrapsAround() {
        var appState = AppState()
        appState.render.imageIndex = 0
        appState.render.imageCount = 10

        let action = RenderAction.prevImage
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.imageIndex, 9)
    }

    func testPrevImageDecrements() {
        var appState = AppState()
        appState.render.imageIndex = 5
        appState.render.imageCount = 10

        let action = RenderAction.prevImage
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.imageIndex, 4)
    }

    // MARK: - Images Loaded

    func testImagesLoadedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.imagesLoaded(count: 25, folderPath: "/path/to/images")
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.imageCount, 25)
        XCTAssertEqual(appState.render.imageIndex, 0)
    }

    func testImagesLoadedLogsMessage() {
        var appState = AppState()

        let action = RenderAction.imagesLoaded(count: 15, folderPath: "/some/folder/images")
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("15") })
    }

    // MARK: - Shader Count Updated

    func testShaderCountUpdatedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.shaderCountUpdated(42)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertEqual(appState.render.shaderCount, 42)
    }

    func testShaderCountUpdatedLogsMessage() {
        var appState = AppState()

        let action = RenderAction.shaderCountUpdated(100)
        _ = renderReducer(state: &appState.render, action: action, appState: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("100") })
    }

    // MARK: - Effective Phase

    func testEffectivePhaseReturnsManualPhase() {
        var state = RenderSubState()
        state.currentPhase = .peak
        state.detectedSongPhase = .disco

        XCTAssertEqual(state.effectivePhase, .peak)
    }

    func testEffectivePhaseReturnsDetectedWhenNoManual() {
        var state = RenderSubState()
        state.currentPhase = nil
        state.detectedSongPhase = .buildup

        XCTAssertEqual(state.effectivePhase, .buildup)
    }

    func testEffectivePhaseReturnsNilWhenBothNil() {
        let state = RenderSubState()

        XCTAssertNil(state.effectivePhase)
    }
}
