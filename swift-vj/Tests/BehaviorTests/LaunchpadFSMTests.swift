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
