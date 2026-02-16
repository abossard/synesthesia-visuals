// StoreTests.swift - Tests for the Store class
// Tests state management and effect execution

import XCTest
@testable import SwiftVJCore

// Simple test reducer for isolated testing
enum TestAction: Sendable {
    case increment
    case decrement
    case setValue(Int)
    case asyncIncrement
    case triggerEffect
}

struct TestState: Equatable, Sendable {
    var count: Int = 0
    var effectTriggered: Bool = false
}

func testReducer(state: inout TestState, action: TestAction) -> Effect<TestAction> {
    switch action {
    case .increment:
        state.count += 1
        return .none

    case .decrement:
        state.count -= 1
        return .none

    case .setValue(let value):
        state.count = value
        return .none

    case .asyncIncrement:
        return .run { send in
            await send(.increment)
        }

    case .triggerEffect:
        state.effectTriggered = true
        return .merge(
            .send(.increment),
            .send(.increment)
        )
    }
}

@MainActor
final class StoreTests: XCTestCase {

    // MARK: - Basic State Updates

    func testInitialState() {
        let store = Store(initialState: TestState(), reducer: testReducer)

        XCTAssertEqual(store.state.count, 0)
        XCTAssertFalse(store.state.effectTriggered)
    }

    func testSendActionUpdatesState() {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send(.increment)

        XCTAssertEqual(store.state.count, 1)
    }

    func testMultipleActionsUpdateState() {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send(.increment)
        store.send(.increment)
        store.send(.decrement)

        XCTAssertEqual(store.state.count, 1)
    }

    func testSendMultipleActions() {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send([.increment, .increment, .increment])

        XCTAssertEqual(store.state.count, 3)
    }

    func testSetValueAction() {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send(.setValue(42))

        XCTAssertEqual(store.state.count, 42)
    }

    // MARK: - Effect Execution

    func testAsyncEffectExecutes() async throws {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send(.asyncIncrement)

        // Wait for effect to complete
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.state.count, 1)
    }

    func testMergedEffectsExecute() async throws {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send(.triggerEffect)

        // Wait for effects to complete
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(store.state.effectTriggered)
        XCTAssertEqual(store.state.count, 2) // Two increments from merged effects
    }

    // MARK: - Cancellation

    func testCancelAllEffects() {
        let store = Store(initialState: TestState(), reducer: testReducer)

        store.send(.asyncIncrement)
        store.cancelAllEffects()

        // Effect should be cancelled, count stays at 0
        XCTAssertEqual(store.state.count, 0)
    }
}

// MARK: - Effect Tests

final class EffectTests: XCTestCase {

    func testEffectNone() {
        let effect: Effect<TestAction> = .none

        if case .none = effect.operation {
            // Expected
        } else {
            XCTFail("Expected .none operation")
        }
    }

    func testEffectRun() {
        let effect: Effect<TestAction> = .run { _ in }

        if case .run = effect.operation {
            // Expected
        } else {
            XCTFail("Expected .run operation")
        }
    }

    func testEffectMerge() {
        let effect: Effect<TestAction> = .merge(
            .send(.increment),
            .send(.decrement)
        )

        if case .merge(let effects) = effect.operation {
            XCTAssertEqual(effects.count, 2)
        } else {
            XCTFail("Expected .merge operation")
        }
    }

    func testEffectMergeFiltersNone() {
        let effect: Effect<TestAction> = .merge(
            .none,
            .send(.increment),
            .none,
            .send(.decrement),
            .none
        )

        if case .merge(let effects) = effect.operation {
            XCTAssertEqual(effects.count, 2)
        } else {
            XCTFail("Expected .merge operation with filtered .none")
        }
    }

    func testEffectMergeReturnsNoneForAllNone() {
        let effect: Effect<TestAction> = .merge(
            .none,
            .none,
            .none
        )

        if case .none = effect.operation {
            // Expected - all .none should result in .none
        } else {
            XCTFail("Expected .none for merge of all .none")
        }
    }

    func testEffectMergeReturnsSingleForOneEffect() {
        let effect: Effect<TestAction> = .merge(
            .none,
            .send(.increment),
            .none
        )

        // Should unwrap to single effect
        if case .run = effect.operation {
            // Expected - single effect unwrapped
        } else {
            XCTFail("Expected .run for single non-none effect")
        }
    }

    func testEffectConcatenate() {
        let effect: Effect<TestAction> = .concatenate(
            .send(.increment),
            .send(.decrement)
        )

        if case .concatenate(let effects) = effect.operation {
            XCTAssertEqual(effects.count, 2)
        } else {
            XCTFail("Expected .concatenate operation")
        }
    }

    func testEffectFireAndForget() {
        let effect: Effect<TestAction> = .fireAndForget {}

        if case .run = effect.operation {
            // Expected
        } else {
            XCTFail("Expected .run operation for fireAndForget")
        }
    }

    func testEffectSend() {
        let effect: Effect<TestAction> = .send(.increment)

        if case .run = effect.operation {
            // Expected
        } else {
            XCTFail("Expected .run operation for send")
        }
    }

    func testEffectMap() {
        enum ParentAction: Sendable {
            case child(TestAction)
        }

        let childEffect: Effect<TestAction> = .send(.increment)
        let parentEffect: Effect<ParentAction> = childEffect.map { .child($0) }

        if case .run = parentEffect.operation {
            // Expected
        } else {
            XCTFail("Expected .run operation after map")
        }
    }

    func testEffectDelay() {
        let effect: Effect<TestAction> = .delay(.milliseconds(100), action: .increment)

        if case .run = effect.operation {
            // Expected
        } else {
            XCTFail("Expected .run operation for delay")
        }
    }
}

// MARK: - AppState Tests

final class AppStateTests: XCTestCase {

    func testInitialState() {
        let state = AppState()

        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.playback.currentTrack)
        XCTAssertEqual(state.playback.position, 0)
        XCTAssertFalse(state.playback.isPlaying)
        XCTAssertEqual(state.playback.source, "vdj")
    }

    func testPlaybackSubStateEquality() {
        let state1 = PlaybackSubState(currentTrack: nil, position: 10, isPlaying: true)
        let state2 = PlaybackSubState(currentTrack: nil, position: 10, isPlaying: true)
        let state3 = PlaybackSubState(currentTrack: nil, position: 20, isPlaying: true)

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testPipelineSubStateUpdateStep() {
        var state = PipelineSubState()

        state.updateStep("lyrics", status: "running")
        XCTAssertEqual(state.steps.first { $0.name == "lyrics" }?.status, "running")

        state.updateStep("lyrics", status: "done", details: ["50 lines"])
        XCTAssertEqual(state.steps.first { $0.name == "lyrics" }?.status, "done")
        XCTAssertEqual(state.steps.first { $0.name == "lyrics" }?.details, ["50 lines"])
    }

    func testPipelineSubStateResetSteps() {
        var state = PipelineSubState()
        state.updateStep("lyrics", status: "done")
        state.updateStep("ai", status: "done")

        state.resetSteps()

        XCTAssertTrue(state.steps.allSatisfy { $0.status == "pending" })
    }

    func testRenderSubStateEffectivePhase() {
        var state = RenderSubState()

        // No phases set
        XCTAssertNil(state.effectivePhase)

        // Only detected
        state.detectedSongPhase = .disco
        XCTAssertEqual(state.effectivePhase, .disco)

        // Manual overrides detected
        state.currentPhase = .peak
        XCTAssertEqual(state.effectivePhase, .peak)
    }

    func testUISubStateAddLog() {
        var state = UISubState()

        state.addLog("Test message", level: .info)

        XCTAssertEqual(state.logEntries.count, 1)
        XCTAssertEqual(state.logEntries.first?.message, "Test message")
    }

    func testUISubStateRecordOSC() {
        var state = UISubState()
        state.oscDebugEnabled = true

        state.recordOSC("/test/address", args: ["value"])

        XCTAssertEqual(state.oscMessages.count, 1)
        XCTAssertNotNil(state.oscMessages["/test/address"])
    }

    func testPersistedState() {
        var appState = AppState()
        appState.render.isEnabled = false
        appState.render.outputs = RenderOutputsState(
            shader: true,
            mask: false,
            lyrics: true,
            refrain: false,
            songInfo: true,
            image: false
        )
        appState.render.selectedShader = "rainbow"
        appState.render.selectedMaskShader = "BWgrid"
        appState.render.shaderControlsByShader = [
            "rainbow": ShaderWorkspaceControls(bin0: 0.22, bin1: 0.31, bin2: 0.44, zoom: 1.15)
        ]
        appState.render.currentPhase = .peak
        appState.playback.source = "spotify"

        let persisted = PersistedState(from: appState)

        XCTAssertEqual(persisted.renderEnabled, false)
        XCTAssertEqual(persisted.renderOutputs.mask, false)
        XCTAssertEqual(persisted.renderOutputs.refrain, false)
        XCTAssertEqual(persisted.renderOutputs.image, false)
        XCTAssertEqual(persisted.shaderControlsByShader["rainbow"]?.bin0, 0.22)
        XCTAssertEqual(persisted.shaderControlsByShader["rainbow"]?.zoom, 1.15)
        XCTAssertEqual(persisted.selectedShader, "rainbow")
        XCTAssertEqual(persisted.selectedMaskShader, "BWgrid")
        XCTAssertEqual(persisted.currentPhase, "peak")
        XCTAssertEqual(persisted.playbackSource, "spotify")

        var newState = AppState()
        persisted.apply(to: &newState)

        XCTAssertEqual(newState.render.isEnabled, false)
        XCTAssertEqual(newState.render.outputs.mask, false)
        XCTAssertEqual(newState.render.outputs.refrain, false)
        XCTAssertEqual(newState.render.outputs.image, false)
        XCTAssertEqual(newState.render.shaderControlsByShader["rainbow"]?.bin1, 0.31)
        XCTAssertEqual(newState.render.shaderControlsByShader["rainbow"]?.bin2, 0.44)
        XCTAssertEqual(newState.render.selectedShader, "rainbow")
        XCTAssertEqual(newState.render.selectedMaskShader, "BWgrid")
        XCTAssertEqual(newState.render.currentPhase, .peak)
        XCTAssertEqual(newState.playback.source, "spotify")
    }
}
