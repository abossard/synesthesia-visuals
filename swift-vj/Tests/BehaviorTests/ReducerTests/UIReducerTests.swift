// UIReducerTests.swift - Tests for UI reducer
// Pure function tests for UI state transitions

import XCTest
@testable import SwiftVJCore

final class UIReducerTests: XCTestCase {

    // MARK: - Log

    func testLogAddsEntry() {
        var state = UISubState()

        let action = UIAction.log("Test message", .info)
        _ = uiReducer(state: &state, action: action)

        XCTAssertEqual(state.logEntries.count, 1)
        XCTAssertEqual(state.logEntries.first?.message, "Test message")
        XCTAssertEqual(state.logEntries.first?.level, .info)
    }

    func testLogWithDifferentLevels() {
        var state = UISubState()

        _ = uiReducer(state: &state, action: .log("Debug", .debug))
        _ = uiReducer(state: &state, action: .log("Warning", .warning))
        _ = uiReducer(state: &state, action: .log("Error", .error))

        XCTAssertEqual(state.logEntries.count, 3)
        XCTAssertEqual(state.logEntries[0].level, .debug)
        XCTAssertEqual(state.logEntries[1].level, .warning)
        XCTAssertEqual(state.logEntries[2].level, .error)
    }

    func testLogTrimsOldEntries() {
        var state = UISubState()

        // Add more than max entries
        for i in 0..<(UISubState.maxLogEntries + 100) {
            _ = uiReducer(state: &state, action: .log("Message \(i)", .info))
        }

        XCTAssertEqual(state.logEntries.count, UISubState.maxLogEntries)
        // Oldest entries should be removed
        XCTAssertFalse(state.logEntries.contains { $0.message == "Message 0" })
    }

    // MARK: - Clear Logs

    func testClearLogsRemovesAllEntries() {
        var state = UISubState()
        state.logEntries = [
            LogEntryState(message: "Entry 1", level: .info),
            LogEntryState(message: "Entry 2", level: .info),
            LogEntryState(message: "Entry 3", level: .info)
        ]

        _ = uiReducer(state: &state, action: .clearLogs)

        XCTAssertTrue(state.logEntries.isEmpty)
    }

    // MARK: - OSC Message Received

    func testOSCMessageReceivedWhenEnabled() {
        var state = UISubState()
        state.oscDebugEnabled = true

        let action = UIAction.oscMessageReceived(address: "/test/address", args: ["value1", "value2"])
        _ = uiReducer(state: &state, action: action)

        XCTAssertEqual(state.oscMessages.count, 1)
        XCTAssertNotNil(state.oscMessages["/test/address"])
        XCTAssertEqual(state.oscMessages["/test/address"]?.args, ["value1", "value2"])
        XCTAssertEqual(state.oscMessageCount, 1)
    }

    func testOSCMessageReceivedWhenDisabled() {
        var state = UISubState()
        state.oscDebugEnabled = false

        let action = UIAction.oscMessageReceived(address: "/test/address", args: ["value"])
        _ = uiReducer(state: &state, action: action)

        XCTAssertTrue(state.oscMessages.isEmpty)
        XCTAssertEqual(state.oscMessageCount, 0)
    }

    func testOSCMessageReceivedWithFilter() {
        var state = UISubState()
        state.oscDebugEnabled = true
        state.oscFilter = "audio"

        // This should be recorded (matches filter)
        _ = uiReducer(state: &state, action: .oscMessageReceived(address: "/audio/level", args: ["0.5"]))
        // This should be filtered out
        _ = uiReducer(state: &state, action: .oscMessageReceived(address: "/deck/1/play", args: ["1"]))

        XCTAssertEqual(state.oscMessages.count, 1)
        XCTAssertNotNil(state.oscMessages["/audio/level"])
        XCTAssertNil(state.oscMessages["/deck/1/play"])
    }

    func testOSCMessageReceivedReplacesExisting() {
        var state = UISubState()
        state.oscDebugEnabled = true

        _ = uiReducer(state: &state, action: .oscMessageReceived(address: "/test", args: ["old"]))
        _ = uiReducer(state: &state, action: .oscMessageReceived(address: "/test", args: ["new"]))

        XCTAssertEqual(state.oscMessages.count, 1)
        XCTAssertEqual(state.oscMessages["/test"]?.args, ["new"])
        XCTAssertEqual(state.oscMessageCount, 2)
    }

    // MARK: - Clear OSC Messages

    func testClearOSCMessagesRemovesAll() {
        var state = UISubState()
        state.oscDebugEnabled = true
        state.oscMessages = [
            "/addr1": OSCLogEntryState(address: "/addr1", args: ["a"]),
            "/addr2": OSCLogEntryState(address: "/addr2", args: ["b"])
        ]
        state.oscMessageCount = 100

        _ = uiReducer(state: &state, action: .clearOscMessages)

        XCTAssertTrue(state.oscMessages.isEmpty)
        XCTAssertEqual(state.oscMessageCount, 0)
    }

    // MARK: - Set OSC Debug Enabled

    func testSetOSCDebugEnabledUpdatesState() {
        var state = UISubState()
        state.oscDebugEnabled = false

        _ = uiReducer(state: &state, action: .setOscDebugEnabled(true))
        XCTAssertTrue(state.oscDebugEnabled)

        _ = uiReducer(state: &state, action: .setOscDebugEnabled(false))
        XCTAssertFalse(state.oscDebugEnabled)
    }

    // MARK: - Set OSC Filter

    func testSetOSCFilterUpdatesState() {
        var state = UISubState()

        _ = uiReducer(state: &state, action: .setOscFilter("audio"))
        XCTAssertEqual(state.oscFilter, "audio")

        _ = uiReducer(state: &state, action: .setOscFilter(""))
        XCTAssertEqual(state.oscFilter, "")
    }
}
