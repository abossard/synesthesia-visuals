import XCTest
@testable import SwiftVJCore

final class LaunchpadFSMTests: XCTestCase {
    func testSelectorPressSendsOscAndSetsActive() {
        var state = ControllerState()
        let padId = ButtonId(x: 0, y: 0)
        let behavior = PadBehavior(
            padId: padId,
            mode: .selector,
            group: .scenes,
            idleColor: LP.greenDim,
            activeColor: LP.green,
            label: "Scene",
            oscAction: OscCommand(address: "/scenes/select", args: [.string("A")])
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor)

        let result = handlePadPress(state, padId: padId)

        XCTAssertEqual(result.state.activeSelectorByGroup[.scenes] ?? nil, padId)
        assertEffectsContain(result.effects, [
            .sendOsc(address: "/scenes/select", args: [.string("A")]),
            .setLed(padId: padId, color: LP.green, blink: true)
        ])
    }

    func testTogglePressOnThenOff() {
        var state = ControllerState()
        let padId = ButtonId(x: 1, y: 0)
        let behavior = PadBehavior(
            padId: padId,
            mode: .toggle,
            idleColor: LP.redDim,
            activeColor: LP.red,
            label: "Toggle",
            oscOn: OscCommand(address: "/controls/meta/invert", args: [.float(1.0)]),
            oscOff: OscCommand(address: "/controls/meta/invert", args: [.float(0.0)])
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor)

        let onResult = handlePadPress(state, padId: padId)
        assertEffectsContain(onResult.effects, [
            .sendOsc(address: "/controls/meta/invert", args: [.float(1.0)]),
            .setLed(padId: padId, color: LP.red, blink: false)
        ])

        let offResult = handlePadPress(onResult.state, padId: padId)
        assertEffectsContain(offResult.effects, [
            .sendOsc(address: "/controls/meta/invert", args: [.float(0.0)]),
            .setLed(padId: padId, color: LP.redDim, blink: false)
        ])
    }

    func testPushPressAndRelease() {
        var state = ControllerState()
        let padId = ButtonId(x: 2, y: 0)
        let behavior = PadBehavior(
            padId: padId,
            mode: .push,
            idleColor: LP.blueDim,
            activeColor: LP.blue,
            label: "Push",
            oscAction: OscCommand(address: "/controls/meta/alpha", args: [])
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor)

        let pressResult = handlePadPress(state, padId: padId)
        assertEffectsContain(pressResult.effects, [
            .sendOsc(address: "/controls/meta/alpha", args: [.float(1.0)]),
            .setLed(padId: padId, color: LP.blue, blink: false)
        ])

        let releaseResult = handlePadRelease(pressResult.state, padId: padId)
        assertEffectsContain(releaseResult.effects, [
            .sendOsc(address: "/controls/meta/alpha", args: [.float(0.0)]),
            .setLed(padId: padId, color: LP.blueDim, blink: false)
        ])
    }

    func testColorCyclePressCyclesForwardAndBackward() {
        var state = ControllerState()
        let padId = ButtonId(x: 3, y: 0)
        let behavior = PadBehavior(
            padId: padId,
            mode: .colorCycle,
            idleColor: LP.white,
            activeColor: LP.white,
            label: "Color 1",
            colorCycleAddresses: [
                "/controls/pop/color1/r",
                "/controls/pop/color1/g",
                "/controls/pop/color1/b",
            ],
            colorCyclePalette: [
                [1.0, 0.0, 0.0],
                [0.0, 1.0, 0.0],
                [0.0, 0.0, 1.0],
            ],
            colorCycleLedColors: [LP.red, LP.green, LP.blue],
            colorCycleIndex: 0
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(isActive: true, currentColor: LP.red, currentValue: 0)

        let forward = handlePadPress(state, padId: padId)
        XCTAssertEqual(forward.state.padRuntime[padId]?.currentValue, 1)
        assertEffectsContain(forward.effects, [
            .sendOsc(address: "/controls/pop/color1/r", args: [.float(0.0)]),
            .sendOsc(address: "/controls/pop/color1/g", args: [.float(1.0)]),
            .sendOsc(address: "/controls/pop/color1/b", args: [.float(0.0)]),
            .setLed(padId: padId, color: LP.green, blink: false),
        ])

        var shiftedState = forward.state
        shiftedState.isShiftHeld = true
        let backward = handlePadPress(shiftedState, padId: padId)
        XCTAssertEqual(backward.state.padRuntime[padId]?.currentValue, 0)
        assertEffectsContain(backward.effects, [
            .sendOsc(address: "/controls/pop/color1/r", args: [.float(1.0)]),
            .sendOsc(address: "/controls/pop/color1/g", args: [.float(0.0)]),
            .sendOsc(address: "/controls/pop/color1/b", args: [.float(0.0)]),
            .setLed(padId: padId, color: LP.red, blink: false),
        ])
    }

    func testEnumIncrementCyclesForwardAndShiftBackwardWithWrap() {
        var state = ControllerState()
        let padId = ButtonId(x: 4, y: 0)
        let behavior = PadBehavior(
            padId: padId,
            mode: .increment,
            idleColor: LP.purpleDim,
            activeColor: LP.purple,
            label: "palette",
            oscAction: OscCommand(address: "/controls/platonicsolids/palette", args: [.float(1.0)]),
            step: 1.0 / 9.0,
            minValue: 0.0,
            maxValue: 1.0,
            enumOptionCount: 10
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor, currentValue: 1.0)

        let forwardWrap = handlePadPress(state, padId: padId)
        XCTAssertEqual(forwardWrap.state.padRuntime[padId]?.currentValue ?? -1.0, 0.0, accuracy: 0.0001)
        assertEffectsContain(forwardWrap.effects, [
            .sendOsc(address: "/controls/platonicsolids/palette", args: [.float(0.0)]),
            .setLed(padId: padId, color: LP.purple, blink: false),
        ])

        var shiftedState = forwardWrap.state
        shiftedState.isShiftHeld = true
        let backwardWrap = handlePadPress(shiftedState, padId: padId)
        XCTAssertEqual(backwardWrap.state.padRuntime[padId]?.currentValue ?? -1.0, 1.0, accuracy: 0.0001)
        assertEffectsContain(backwardWrap.effects, [
            .sendOsc(address: "/controls/platonicsolids/palette", args: [.float(1.0)]),
            .setLed(padId: padId, color: LP.purple, blink: false),
        ])
    }

    func testVector2PadUsesSideButtonsForNudgesAndSecondPressResets() {
        var state = ControllerState()
        let padId = ButtonId(x: 5, y: 0)
        let behavior = PadBehavior(
            padId: padId,
            mode: .vector2,
            idleColor: LP.cyanDim,
            activeColor: LP.cyan,
            label: "camxy",
            step: 0.1,
            minValue: 0.0,
            maxValue: 1.0,
            vector2Addresses: [
                "/controls/platonicsolids/camxy/x",
                "/controls/platonicsolids/camxy/y",
            ],
            vector2Current: [0.5, 0.5],
            vector2Default: [0.5, 0.5]
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(
            currentColor: behavior.idleColor,
            currentValue: 0.5,
            secondaryValue: 0.5
        )

        let selected = handlePadPress(state, padId: padId)
        XCTAssertEqual(selected.state.activeVectorPad, padId)
        assertEffectsContain(selected.effects, [
            .setLed(padId: padId, color: LP.cyan, blink: false),
        ])

        var steppedState = selected.state
        for _ in 0..<5 {
            steppedState = handlePadPress(steppedState, padId: ButtonId(x: 8, y: 3)).state
        }
        XCTAssertEqual(steppedState.padRuntime[padId]?.currentValue ?? -1.0, 1.0, accuracy: 0.0001)

        let up = handlePadPress(steppedState, padId: ButtonId(x: 8, y: 4))
        XCTAssertEqual(up.state.padRuntime[padId]?.secondaryValue ?? -1.0, 0.6, accuracy: 0.0001)
        assertEffectsContain(up.effects, [
            .sendOsc(address: "/controls/platonicsolids/camxy/y", args: [.float(0.6)]),
        ])

        let reset = handlePadPress(up.state, padId: padId)
        XCTAssertEqual(reset.state.padRuntime[padId]?.currentValue ?? -1.0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(reset.state.padRuntime[padId]?.secondaryValue ?? -1.0, 0.5, accuracy: 0.0001)
        assertEffectsContain(reset.effects, [
            .sendOsc(address: "/controls/platonicsolids/camxy/x", args: [.float(0.5)]),
            .sendOsc(address: "/controls/platonicsolids/camxy/y", args: [.float(0.5)]),
        ])
    }

    func testBankSwitchAndPageAdvance() {
        var state = ControllerState()
        state.activeBank = 0
        state.bankPageCount[0] = 3
        state.bankCurrentPage[0] = 0
        state.bankLayout[0] = BankLayoutPolicy(paging: .nextButton(row: 6))

        let bankResult = handlePadPress(state, padId: LaunchpadButton.bank(1))
        XCTAssertEqual(bankResult.state.activeBank, 1)
        assertEffectsContain(bankResult.effects, [
            .setLed(padId: LaunchpadButton.bank(1), color: BankConfig.color(for: 1), blink: false)
        ])

        let pageResult = handlePadPress(state, padId: LaunchpadButton.page)
        XCTAssertEqual(pageResult.state.currentPage, 1)
        assertEffectsContain(pageResult.effects, [
            .setLed(padId: LaunchpadButton.page, color: LP.purple, blink: false)
        ])
    }

    func testPagingRowButtonsSelectPage() {
        var state = ControllerState()
        state.activeBank = 0
        state.bankPageCount[0] = 4
        state.bankCurrentPage[0] = 0
        state.bankLayout[0] = BankLayoutPolicy(paging: .rowButtons(rows: [1, 2, 3, 4]))

        let page2 = handlePadPress(state, padId: ButtonId(x: 8, y: 2))
        XCTAssertEqual(page2.state.currentPage, 1)
        assertEffectsContain(page2.effects, [
            .setLed(padId: ButtonId(x: 8, y: 2), color: LP.purple, blink: false)
        ])

        let page4 = handlePadPress(page2.state, padId: ButtonId(x: 8, y: 4))
        XCTAssertEqual(page4.state.currentPage, 3)
        assertEffectsContain(page4.effects, [
            .setLed(padId: ButtonId(x: 8, y: 4), color: LP.purple, blink: false)
        ])
    }

    func testLearnModeCaptureAndSave() {
        let state = ControllerState()

        let enterResult = handlePadPress(state, padId: LaunchpadButton.learn)
        XCTAssertEqual(enterResult.state.learnState.phase, .waitPad)

        let selectedPad = ButtonId(x: 0, y: 1)
        let selectResult = handlePadPress(enterResult.state, padId: selectedPad)
        XCTAssertEqual(selectResult.state.learnState.phase, .config)
        XCTAssertEqual(selectResult.state.learnState.selectedPad, selectedPad)

        let event = OscEvent(address: "/scenes/Example", args: [.string("Example")])
        let captureResult = captureOscEvent(selectResult.state, event: event)
        XCTAssertEqual(captureResult.state.learnState.capturedOsc.count, 1)

        let saveResult = handlePadPress(captureResult.state, padId: LaunchpadButton.save)
        XCTAssertEqual(saveResult.state.learnState.phase, .idle)
        XCTAssertNotNil(saveResult.state.pads[selectedPad])
        assertEffectsContain(saveResult.effects, [
            .saveConfig,
            .logContains("Saved pad")
        ])
    }

    func testCaptureOscEventIgnoredOutsideConfigPhase() {
        let event = OscEvent(address: "/ledfx/scene/strobe/0", args: [.float(1.0)])

        let idleState = ControllerState()
        let idleResult = captureOscEvent(idleState, event: event)
        XCTAssertEqual(idleResult.state.learnState.phase, .idle)
        XCTAssertTrue(idleResult.state.learnState.capturedOsc.isEmpty)

        let waitPadState = enterLearnMode(ControllerState()).state
        let waitPadResult = captureOscEvent(waitPadState, event: event)
        XCTAssertEqual(waitPadResult.state.learnState.phase, .waitPad)
        XCTAssertTrue(waitPadResult.state.learnState.capturedOsc.isEmpty)
    }

    func testLearnModeCaptureAndSaveLedFXCommand() {
        let state = ControllerState()

        let enterResult = handlePadPress(state, padId: LaunchpadButton.learn)
        let selectedPad = ButtonId(x: 1, y: 1)
        let selectResult = handlePadPress(enterResult.state, padId: selectedPad)

        let ledfxEvent = OscEvent(address: "/ledfx/scene/strobe/0", args: [.float(1.0)])
        let captureResult = captureOscEvent(selectResult.state, event: ledfxEvent)
        XCTAssertEqual(captureResult.state.learnState.capturedOsc.count, 1)

        let saveResult = handlePadPress(captureResult.state, padId: LaunchpadButton.save)
        XCTAssertEqual(saveResult.state.learnState.phase, .idle)
        XCTAssertEqual(saveResult.state.pads[selectedPad]?.oscAction?.address, "/ledfx/scene/strobe/0")
        assertEffectsContain(saveResult.effects, [
            .saveConfig
        ])
    }

    func testLearnModeSaveKeepsLedFXAsAdditionalCommand() {
        let state = ControllerState()

        let enterResult = handlePadPress(state, padId: LaunchpadButton.learn)
        let selectedPad = ButtonId(x: 2, y: 1)
        let selectResult = handlePadPress(enterResult.state, padId: selectedPad)

        let sceneCapture = captureOscEvent(
            selectResult.state,
            event: OscEvent(address: "/scenes/Example", args: [.string("Example")])
        )
        let mixedCapture = captureOscEvent(
            sceneCapture.state,
            event: OscEvent(address: "/ledfx/scene/strobe/0", args: [.float(1.0)])
        )

        let saveResult = handlePadPress(mixedCapture.state, padId: LaunchpadButton.save)
        let behavior = saveResult.state.pads[selectedPad]

        XCTAssertEqual(behavior?.oscAction?.address, "/scenes/Example")
        XCTAssertEqual(behavior?.additionalOsc.map(\.address), ["/ledfx/scene/strobe/0"])
    }

    func testStressInterleavedCaptureDeterministicOrderAndBankIsolation() {
        var state = ControllerState()
        let selectedPad = ButtonId(x: 0, y: 2)
        var expectedSceneAddress = "/scenes/scene-0"

        state = handlePadPress(state, padId: LaunchpadButton.learn).state
        state = handlePadPress(state, padId: selectedPad).state
        XCTAssertEqual(state.learnState.phase, .config)

        let iterations = 1_000
        for idx in 0..<iterations {
            state = handlePadPress(state, padId: LaunchpadButton.bank(idx % BankConfig.count)).state
            expectedSceneAddress = "/scenes/scene-\(idx)"
            state = captureOscEvent(
                state,
                event: OscEvent(address: expectedSceneAddress, args: [.string("scene-\(idx)")])
            ).state
            state = captureOscEvent(
                state,
                event: OscEvent(address: "/controls/meta/alpha", args: [.float(Float(idx % 2))])
            ).state
            state = captureOscEvent(
                state,
                event: OscEvent(
                    address: "/ledfx/param/global_brightness/0",
                    args: [.float(Float(idx) / Float(iterations))]
                )
            ).state
        }

        let finalBank = state.activeBank
        let saveResult = handlePadPress(state, padId: LaunchpadButton.save)
        let finalState = saveResult.state
        let savedBehavior = finalState.bankPads[finalBank]?[selectedPad]

        XCTAssertEqual(savedBehavior?.oscAction?.address, expectedSceneAddress)
        XCTAssertEqual(savedBehavior?.additionalOsc.map(\.address), [
            "/controls/meta/alpha",
            "/ledfx/param/global_brightness/0"
        ])

        for bank in 0..<BankConfig.count where bank != finalBank {
            XCTAssertNil(finalState.bankPads[bank]?[selectedPad], "Expected no saved pad in bank \(bank)")
        }
    }

    func testShiftPressAndRelease() {
        let state = ControllerState()

        let pressResult = handlePadPress(state, padId: LaunchpadButton.shift)
        XCTAssertTrue(pressResult.state.isShiftHeld)
        assertEffectsContain(pressResult.effects, [
            .setLed(padId: LaunchpadButton.shift, color: LP.white, blink: false)
        ])

        let releaseResult = handlePadRelease(pressResult.state, padId: LaunchpadButton.shift)
        XCTAssertFalse(releaseResult.state.isShiftHeld)
        assertEffectsContain(releaseResult.effects, [
            .setLed(padId: LaunchpadButton.shift, color: LP.purpleDim, blink: false)
        ])
    }

    func testMidiMessageMappedToPadPress() {
        let message = MIDIMessage.noteOn(channel: 0, note: 11, velocity: 127)
        guard let padId = message.buttonId else {
            XCTFail("Expected buttonId")
            return
        }

        var state = ControllerState()
        let behavior = PadBehavior(
            padId: padId,
            mode: .oneShot,
            idleColor: LP.yellowDim,
            activeColor: LP.yellow,
            label: "OneShot",
            oscAction: OscCommand(address: "/controls/meta/brightness", args: [.float(0.5)])
        )
        state.pads[padId] = behavior
        state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor)

        let result = handlePadPress(state, padId: padId)
        assertEffectsContain(result.effects, [
            .sendOsc(address: "/controls/meta/brightness", args: [.float(0.5)]),
            .setLed(padId: padId, color: LP.yellow, blink: false)
        ])
    }

    func testStressRapidBankSwitchKeepsFinalBankAndBankPads() {
        var state = ControllerState()
        var padByBank: [Int: ButtonId] = [:]

        for bank in 0..<8 {
            let padId = ButtonId(x: bank % 4, y: bank % 8)
            padByBank[bank] = padId
            let behavior = PadBehavior(
                padId: padId,
                mode: .selector,
                group: .custom,
                idleColor: LP.greenDim,
                activeColor: LP.green,
                label: "B\(bank)",
                oscAction: OscCommand(address: "/scenes/b\(bank)", args: [])
            )
            state.bankPads[bank] = [padId: behavior]
            state.bankPadRuntime[bank] = [padId: PadRuntimeState(currentColor: behavior.idleColor)]
        }

        let iterations = 2_000
        for idx in 0..<iterations {
            let bank = idx % 8
            state = handlePadPress(state, padId: LaunchpadButton.bank(bank)).state
            if let padId = padByBank[bank] {
                state = handlePadPress(state, padId: padId).state
            }
        }

        let expectedFinalBank = (iterations - 1) % 8
        XCTAssertEqual(state.activeBank, expectedFinalBank)
        XCTAssertEqual(state.currentPage, state.bankCurrentPage[expectedFinalBank] ?? 0)

        for bank in 0..<8 {
            let padId = padByBank[bank]
            XCTAssertNotNil(padId)
            XCTAssertNotNil(padId.flatMap { state.bankPads[bank]?[$0] })
            XCTAssertEqual(state.bankPads[bank]?.count, 1, "Bank \(bank) should keep exactly one configured pad")
        }
    }

    func testStressBankScopedSelectorsStayIsolatedAcrossRapidSwitching() {
        var state = ControllerState()
        var padByBank: [Int: ButtonId] = [:]

        for bank in 0..<8 {
            let padId = ButtonId(x: (bank + 1) % 8, y: bank % 8)
            padByBank[bank] = padId
            let behavior = PadBehavior(
                padId: padId,
                mode: .selector,
                group: .custom,
                idleColor: LP.blueDim,
                activeColor: LP.blue,
                label: "S\(bank)",
                oscAction: OscCommand(address: "/presets/p\(bank)", args: [])
            )
            state.bankPads[bank] = [padId: behavior]
            state.bankPadRuntime[bank] = [padId: PadRuntimeState(currentColor: behavior.idleColor)]
        }

        let cycles = 1_000
        for idx in 0..<cycles {
            let bank = idx % 8
            state = handlePadPress(state, padId: LaunchpadButton.bank(bank)).state
            if let padId = padByBank[bank] {
                state = handlePadPress(state, padId: padId).state
            }
        }

        for bank in 0..<8 {
            let expectedPad = padByBank[bank]
            let selected = state.bankActiveSelectorByGroup[bank]?[.custom] ?? nil
            XCTAssertEqual(selected, expectedPad, "Bank \(bank) selector should remain bank-scoped")
        }
    }
}
