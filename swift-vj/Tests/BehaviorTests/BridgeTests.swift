// BridgeTests.swift - Pure function tests for the OSC/OS2L/LedFX bridge pipeline
// Tests calculations only — no network, no actors, no external dependencies

import XCTest
@testable import SwiftVJCore

final class BridgeTests: XCTestCase {

    // MARK: - parseOS2LEvent

    func test_parseOS2LEvent_buttonOn() {
        let json = #"{"evt":"btn","name":"strobe","state":"on"}"#
        let event = parseOS2LEvent(from: json)
        XCTAssertEqual(event, .button(name: "strobe", state: .on))
    }

    func test_parseOS2LEvent_buttonOff() {
        let json = #"{"evt":"btn","name":"strobe","state":"off"}"#
        let event = parseOS2LEvent(from: json)
        XCTAssertEqual(event, .button(name: "strobe", state: .off))
    }

    func test_parseOS2LEvent_command() {
        let json = #"{"evt":"cmd","id":1,"param":50}"#
        let event = parseOS2LEvent(from: json)
        XCTAssertEqual(event, .command(id: 1, param: 50))
    }

    func test_parseOS2LEvent_beat() {
        let json = #"{"evt":"beat"}"#
        let event = parseOS2LEvent(from: json)
        XCTAssertEqual(event, .beat)
    }

    func test_parseOS2LEvent_unknownEventType() {
        let json = #"{"evt":"custom"}"#
        let event = parseOS2LEvent(from: json)
        XCTAssertEqual(event, .unknown(raw: json))
    }

    func test_parseOS2LEvent_invalidJSON() {
        let raw = "not json"
        let event = parseOS2LEvent(from: raw)
        XCTAssertEqual(event, .unknown(raw: raw))
    }

    func test_parseOS2LEvent_emptyString() {
        let event = parseOS2LEvent(from: "")
        XCTAssertEqual(event, .unknown(raw: ""))
    }

    func test_parseOS2LEvent_buttonWithInvalidState() {
        let json = #"{"evt":"btn","name":"strobe","state":"toggle"}"#
        let event = parseOS2LEvent(from: json)
        XCTAssertEqual(event, .unknown(raw: json))
    }

    // MARK: - extractOS2LLines

    func test_extractOS2LLines_singleCompleteLine() {
        let result = extractOS2LLines(from: "json\n")
        XCTAssertEqual(result.lines, ["json"])
        XCTAssertEqual(result.remainder, "")
    }

    func test_extractOS2LLines_multipleLines() {
        let result = extractOS2LLines(from: "json1\njson2\n")
        XCTAssertEqual(result.lines, ["json1", "json2"])
        XCTAssertEqual(result.remainder, "")
    }

    func test_extractOS2LLines_partialLine() {
        let result = extractOS2LLines(from: "partial")
        XCTAssertEqual(result.lines, [])
        XCTAssertEqual(result.remainder, "partial")
    }

    func test_extractOS2LLines_mixedCompleteAndPartial() {
        let result = extractOS2LLines(from: "complete\npartial")
        XCTAssertEqual(result.lines, ["complete"])
        XCTAssertEqual(result.remainder, "partial")
    }

    func test_extractOS2LLines_emptyBuffer() {
        let result = extractOS2LLines(from: "")
        XCTAssertEqual(result.lines, [])
        XCTAssertEqual(result.remainder, "")
    }

    func test_extractOS2LLines_multipleCompleteWithPartialRemainder() {
        let result = extractOS2LLines(from: "a\nb\nc")
        XCTAssertEqual(result.lines, ["a", "b"])
        XCTAssertEqual(result.remainder, "c")
    }

    // MARK: - BridgeConfig defaults

    func test_defaultConfig_hasExpectedPorts() {
        let config = OSCBridgeConfig.default
        XCTAssertEqual(config.ports.os2lListen, 9997)
        XCTAssertEqual(config.ports.os2lForward, 9996)
        XCTAssertEqual(config.ports.oscVdjIn, 9010)
        XCTAssertEqual(config.ports.ledFXAPI, "http://127.0.0.1:8888")
    }

    func test_defaultConfig_hasLedFXMappings() {
        let config = OSCBridgeConfig.default
        XCTAssertGreaterThanOrEqual(config.os2lToLedFX.count, 1)
    }

    // MARK: - BridgeConfig round-trip encoding

    func test_configRoundTrip_encodeDecode() throws {
        let original = OSCBridgeConfig.default
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OSCBridgeConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_configRoundTrip_preservesDetails() throws {
        let original = OSCBridgeConfig.default
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OSCBridgeConfig.self, from: data)

        XCTAssertEqual(decoded.os2lToLedFX.count, original.os2lToLedFX.count)
        for (orig, dec) in zip(original.os2lToLedFX, decoded.os2lToLedFX) {
            XCTAssertEqual(dec.os2lButtonName, orig.os2lButtonName)
            XCTAssertEqual(dec.targetName, orig.targetName)
            XCTAssertEqual(dec.isScene, orig.isScene)
        }
    }

    // MARK: - LedFXMappingConfig.toMapping()

    func test_mappingConfigToMapping_convertsCorrectly() {
        let config = OSCBridgeConfig.LedFXMappingConfig(
            os2lButtonName: "blackout",
            targetName: "off",
            isScene: true
        )

        let mapping = config.toMapping()
        XCTAssertEqual(mapping.os2lButtonName, "blackout")
        XCTAssertEqual(mapping.playlistName, "off")
        XCTAssertTrue(mapping.isScene)
    }

    // MARK: - resolveMapping (pure function)

    func test_resolveMapping_exactMatch() {
        let mappings = [
            LedFXMapping(os2lButtonName: "blackout", playlistName: "off", isScene: true),
            LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
        ]

        let resolved = resolveMapping(buttonName: "blackout", mappings: mappings)
        XCTAssertEqual(resolved, ResolvedMapping(targetName: "off", isScene: true))
    }

    func test_resolveMapping_wildcardCapture() {
        let mappings = [
            LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
        ]

        let resolved = resolveMapping(buttonName: "drop", mappings: mappings)
        XCTAssertEqual(resolved, ResolvedMapping(targetName: "drop", isScene: false))
    }

    func test_resolveMapping_exactBeforeWildcard() {
        let mappings = [
            LedFXMapping(os2lButtonName: "blackout", playlistName: "off", isScene: true),
            LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
        ]

        let resolved = resolveMapping(buttonName: "blackout", mappings: mappings)
        XCTAssertEqual(resolved?.targetName, "off")
        XCTAssertTrue(resolved?.isScene ?? false)
    }

    func test_resolveMapping_noMatchReturnsNil() {
        let mappings = [
            LedFXMapping(os2lButtonName: "blackout", playlistName: "off", isScene: true),
        ]

        let resolved = resolveMapping(buttonName: "strobe", mappings: mappings)
        XCTAssertNil(resolved)
    }

    func test_resolveMapping_emptyMappingsReturnsNil() {
        let resolved = resolveMapping(buttonName: "anything", mappings: [])
        XCTAssertNil(resolved)
    }

    func test_resolveMapping_wildcardWithFixedTarget() {
        let mappings = [
            LedFXMapping(os2lButtonName: "*", playlistName: "default-playlist"),
        ]

        let resolved = resolveMapping(buttonName: "strobe", mappings: mappings)
        XCTAssertEqual(resolved?.targetName, "default-playlist")
    }

    // MARK: - Integration: end-to-end data flow (pure functions only)

    func test_endToEnd_os2lParseToLedFXResolve() {
        let json = #"{"evt":"btn","name":"blackout","state":"on"}"#
        let event = parseOS2LEvent(from: json)

        guard case let .button(name, state) = event else {
            XCTFail("Expected button event"); return
        }
        XCTAssertEqual(name, "blackout")
        XCTAssertEqual(state, .on)

        let mappings = [
            LedFXMapping(os2lButtonName: "blackout", playlistName: "off", isScene: true),
            LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
        ]
        let resolved = resolveMapping(buttonName: name, mappings: mappings)

        XCTAssertEqual(resolved, ResolvedMapping(targetName: "off", isScene: true))
    }
}
