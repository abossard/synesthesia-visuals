// RenderReducerTests.swift - Tests for render reducer
// Pure function tests for render state transitions

import XCTest
@testable import SwiftVJCore

@MainActor
final class RenderReducerTests: XCTestCase {
    private actor ActionCollector {
        private var actions: [AppAction] = []
        func append(_ action: AppAction) { actions.append(action) }
        func snapshot() -> [AppAction] { actions }
    }

    private actor OutputToggleCollector {
        private(set) var calls: [(RenderOutput, Bool)] = []
        func record(_ output: RenderOutput, enabled: Bool) { calls.append((output, enabled)) }
        func snapshot() -> [(RenderOutput, Bool)] { calls }
    }

    // Helper to avoid overlapping access issues when calling reducers
    private func applyRenderReducer(_ action: RenderAction, to appState: inout AppState) {
        var renderState = appState.render
        _ = renderReducer(state: &renderState, action: action, appState: &appState)
        appState.render = renderState
    }

    private func applyRenderReducerReturningEffect(_ action: RenderAction, to appState: inout AppState) -> Effect<AppAction> {
        var renderState = appState.render
        let effect = renderReducer(state: &renderState, action: action, appState: &appState)
        appState.render = renderState
        return effect
    }

    private func collectActions(from effect: Effect<AppAction>) async -> [AppAction] {
        switch effect.operation {
        case .none:
            return []
        case .run(_, let operation, _):
            let collector = ActionCollector()
            let send = Send<AppAction> { action in
                await collector.append(action)
            }
            await operation(send)
            return await collector.snapshot()
        case .merge(let effects):
            var all: [AppAction] = []
            for nested in effects {
                all.append(contentsOf: await collectActions(from: nested))
            }
            return all
        case .concatenate(let effects):
            var all: [AppAction] = []
            for nested in effects {
                all.append(contentsOf: await collectActions(from: nested))
            }
            return all
        }
    }

    // MARK: - Select Shader

    func testSetEnabledUpdatesStateAndPersists() async {
        var appState = AppState()

        let effect = applyRenderReducerReturningEffect(.setEnabled(false), to: &appState)
        XCTAssertFalse(appState.render.isEnabled)

        let emitted = await collectActions(from: effect)
        XCTAssertEqual(emitted.count, 1)
        guard case .persistState = emitted[0] else {
            XCTFail("Expected persistState action after renderer toggle")
            return
        }
    }

    func testSetOutputEnabledUpdatesStatePersistsAndDispatchesEffect() async {
        var appState = AppState()
        let collector = OutputToggleCollector()
        EffectEnvironment.shared.setRenderOutputEnabled = { output, enabled in
            await collector.record(output, enabled: enabled)
        }
        defer { EffectEnvironment.shared.reset() }

        let effect = applyRenderReducerReturningEffect(
            .setOutputEnabled(output: .lyrics, enabled: false),
            to: &appState
        )
        XCTAssertFalse(appState.render.outputs.lyrics)

        let emitted = await collectActions(from: effect)
        XCTAssertEqual(emitted.count, 1)
        guard case .persistState = emitted[0] else {
            XCTFail("Expected persistState action after output toggle")
            return
        }

        let calls = await collector.snapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, .lyrics)
        XCTAssertEqual(calls.first?.1, false)
    }

    func testSetOutputEnabledNoStateChangeStillDispatchesEffectWithoutPersist() async {
        var appState = AppState()
        appState.render.outputs.lyrics = true
        let collector = OutputToggleCollector()
        EffectEnvironment.shared.setRenderOutputEnabled = { output, enabled in
            await collector.record(output, enabled: enabled)
        }
        defer { EffectEnvironment.shared.reset() }

        let effect = applyRenderReducerReturningEffect(
            .setOutputEnabled(output: .lyrics, enabled: true),
            to: &appState
        )

        let emitted = await collectActions(from: effect)
        XCTAssertTrue(emitted.isEmpty)

        let calls = await collector.snapshot()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, .lyrics)
        XCTAssertEqual(calls.first?.1, true)
    }

    func testSelectShaderUpdatesState() {
        var appState = AppState()

        let action = RenderAction.selectShader("rainbow")
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.selectedShader, "rainbow")
    }

    func testSelectShaderLogsMessage() {
        var appState = AppState()

        let action = RenderAction.selectShader("plasma")
        applyRenderReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("plasma") })
    }

    // MARK: - Shader Selected

    func testShaderSelectedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.shaderSelected("waves")
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.selectedShader, "waves")
    }

    func testSelectMaskShaderUpdatesState() {
        var appState = AppState()

        let action = RenderAction.selectMaskShader("BWswirl")
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.selectedMaskShader, "BWswirl")
    }

    func testMaskShaderSelectedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.maskShaderSelected("BWgrid")
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.selectedMaskShader, "BWgrid")
    }

    // MARK: - Shader Navigation Effects

    func testSelectNextShaderDispatchesExpectedAction() async {
        EffectEnvironment.shared.availableShaderNames = { ["a", "b", "c"] }
        defer { EffectEnvironment.shared.reset() }

        let emitted = await collectActions(from: RenderEffects.selectNextShader(current: "b"))
        XCTAssertEqual(emitted.count, 1)

        guard case let .render(.selectShader(name)) = emitted[0] else {
            XCTFail("Expected render.selectShader action")
            return
        }
        XCTAssertEqual(name, "c")
    }

    func testSelectPreviousMaskShaderDispatchesExpectedAction() async {
        EffectEnvironment.shared.availableMaskShaderNames = { ["m0", "m1", "m2"] }
        defer { EffectEnvironment.shared.reset() }

        let emitted = await collectActions(from: RenderEffects.selectPreviousMaskShader(current: "m0"))
        XCTAssertEqual(emitted.count, 1)

        guard case let .render(.selectMaskShader(name)) = emitted[0] else {
            XCTFail("Expected render.selectMaskShader action")
            return
        }
        XCTAssertEqual(name, "m2")
    }

    func testRapidNavigationStressMaintainsValidSelections() async throws {
        let shaderNames = (0..<8).map { "shader_\($0)" }
        let maskNames = (0..<4).map { "mask_\($0)" }

        EffectEnvironment.shared.availableShaderNames = { shaderNames }
        EffectEnvironment.shared.availableMaskShaderNames = { maskNames }
        EffectEnvironment.shared.loadShader = { _ in }
        EffectEnvironment.shared.loadMaskShader = { _ in }
        defer { EffectEnvironment.shared.reset() }

        let store = Store(initialState: AppState(), reducer: appReducer)
        store.send(.render(.selectShader(shaderNames[0])))
        store.send(.render(.selectMaskShader(maskNames[0])))

        for i in 0..<400 {
            store.send(.render(i.isMultiple(of: 2) ? .selectNextShader : .selectPreviousShader))
            store.send(.render(i.isMultiple(of: 3) ? .selectNextMaskShader : .selectPreviousMaskShader))
        }

        try await Task.sleep(for: .milliseconds(300))

        let selectedMain = store.state.render.selectedShader ?? ""
        let selectedMask = store.state.render.selectedMaskShader ?? ""
        XCTAssertTrue(shaderNames.contains(selectedMain), "Selected main shader must stay within available set")
        XCTAssertTrue(maskNames.contains(selectedMask), "Selected mask shader must stay within available set")
    }

    func testRapidRendererToggleStressMaintainsFinalState() async throws {
        EffectEnvironment.shared.setRenderEnabled = { _ in }
        defer { EffectEnvironment.shared.reset() }

        let store = Store(initialState: AppState(), reducer: appReducer)
        for i in 0..<400 {
            let enabled = i.isMultiple(of: 2)
            store.send(.render(.setEnabled(enabled)))
        }

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(store.state.render.isEnabled, "Final renderer state should reflect the last toggle action")
    }

    // MARK: - Select Phase

    func testSelectPhaseUpdatesState() {
        var appState = AppState()

        let action = RenderAction.selectPhase(.peak)
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.currentPhase, .peak)
    }

    func testSelectPhaseNilUpdatesState() {
        var appState = AppState()
        appState.render.currentPhase = .buildup

        let action = RenderAction.selectPhase(nil)
        applyRenderReducer(action, to: &appState)

        XCTAssertNil(appState.render.currentPhase)
    }

    func testSelectPhaseLogsMessage() {
        var appState = AppState()

        let action = RenderAction.selectPhase(.disco)
        applyRenderReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("Disco") })
    }

    // MARK: - Phase Detected

    func testPhaseDetectedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.phaseDetected(.release)
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.detectedSongPhase, .release)
    }

    // MARK: - Image Navigation

    func testSetImageIndexUpdatesState() {
        var appState = AppState()
        appState.render.imageCount = 10

        let action = RenderAction.setImageIndex(5)
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.imageIndex, 5)
    }

    func testNextImageWrapsAround() {
        var appState = AppState()
        appState.render.imageIndex = 9
        appState.render.imageCount = 10

        let action = RenderAction.nextImage
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.imageIndex, 0)
    }

    func testNextImageIncrements() {
        var appState = AppState()
        appState.render.imageIndex = 3
        appState.render.imageCount = 10

        let action = RenderAction.nextImage
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.imageIndex, 4)
    }

    func testPrevImageWrapsAround() {
        var appState = AppState()
        appState.render.imageIndex = 0
        appState.render.imageCount = 10

        let action = RenderAction.prevImage
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.imageIndex, 9)
    }

    func testPrevImageDecrements() {
        var appState = AppState()
        appState.render.imageIndex = 5
        appState.render.imageCount = 10

        let action = RenderAction.prevImage
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.imageIndex, 4)
    }

    // MARK: - Images Loaded

    func testImagesLoadedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.imagesLoaded(count: 25, folderPath: "/path/to/images")
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.imageCount, 25)
        XCTAssertEqual(appState.render.imageIndex, 0)
    }

    func testImagesLoadedLogsMessage() {
        var appState = AppState()

        let action = RenderAction.imagesLoaded(count: 15, folderPath: "/some/folder/images")
        applyRenderReducer(action, to: &appState)

        XCTAssertTrue(appState.ui.logEntries.contains { $0.message.contains("15") })
    }

    // MARK: - Shader Count Updated

    func testShaderCountUpdatedUpdatesState() {
        var appState = AppState()

        let action = RenderAction.shaderCountUpdated(42)
        applyRenderReducer(action, to: &appState)

        XCTAssertEqual(appState.render.shaderCount, 42)
    }

    func testShaderCountUpdatedLogsMessage() {
        var appState = AppState()

        let action = RenderAction.shaderCountUpdated(100)
        applyRenderReducer(action, to: &appState)

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
