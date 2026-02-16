import XCTest
@testable import SwiftVJCore

final class LaunchpadReducerTests: XCTestCase {
    private func applyLaunchpadReducer(_ action: LaunchpadAction, to appState: inout AppState) {
        var launchpadState = appState.launchpad
        _ = launchpadReducer(state: &launchpadState, action: action, appState: &appState)
        appState.launchpad = launchpadState
    }

    func testStateUpdatedStoresControllerStateAsSingleSourceOfTruth() {
        var appState = AppState()
        var controllerState = ControllerState()
        controllerState.activeBank = 4
        controllerState.activeScene = "SceneA"
        controllerState.activePreset = "PresetA"

        applyLaunchpadReducer(.stateUpdated(controllerState), to: &appState)

        XCTAssertEqual(appState.launchpad.currentBank, 4)
        XCTAssertEqual(appState.launchpad.controllerState?.activeBank, 4)
        XCTAssertEqual(appState.launchpad.controllerState?.activeScene, "SceneA")
        XCTAssertEqual(appState.launchpad.controllerState?.activePreset, "PresetA")
        XCTAssertEqual(appState.launchpad.controllerRevision, 1)
    }

    func testStressStateUpdatedRevisionMonotonicUnderRapidBankSwitching() {
        var appState = AppState()
        let iterations = 3_000

        for idx in 0..<iterations {
            var controllerState = ControllerState()
            controllerState.activeBank = idx % 8
            controllerState.activeScene = "scene-\(idx)"
            controllerState.activePreset = "preset-\(idx)"
            applyLaunchpadReducer(.stateUpdated(controllerState), to: &appState)
        }

        XCTAssertEqual(appState.launchpad.controllerRevision, UInt64(iterations))
        XCTAssertEqual(appState.launchpad.currentBank, (iterations - 1) % 8)
        XCTAssertEqual(appState.launchpad.controllerState?.activeScene, "scene-\(iterations - 1)")
        XCTAssertEqual(appState.launchpad.controllerState?.activePreset, "preset-\(iterations - 1)")
    }
}
