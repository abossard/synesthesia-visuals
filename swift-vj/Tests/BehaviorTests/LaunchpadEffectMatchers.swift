import XCTest
@testable import SwiftVJCore

// Test-only helpers for matching LaunchpadEffect without Equatable.

enum LaunchpadEffectMatch {
    case sendOsc(address: String, args: [OscArg]?)
    case setLed(padId: ButtonId, color: LaunchpadColor, blink: Bool?)
    case saveConfig
    case logContains(String)
}

func assertEffectsContain(
    _ effects: [LaunchpadEffect],
    _ expected: [LaunchpadEffectMatch],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for match in expected {
        let found = effects.contains { effect in
            matches(effect, match)
        }
        XCTAssertTrue(found, "Missing effect: \(match)", file: file, line: line)
    }
}

private func matches(_ effect: LaunchpadEffect, _ expected: LaunchpadEffectMatch) -> Bool {
    switch (effect, expected) {
    case (.sendOsc(let cmd), .sendOsc(let address, let args)):
        if cmd.address != address { return false }
        if let args, args != cmd.args { return false }
        return true
    case (.setLed(let padId, let color, let blink), .setLed(let expPadId, let expColor, let expBlink)):
        if padId != expPadId { return false }
        if color != expColor { return false }
        if let expBlink, expBlink != blink { return false }
        return true
    case (.saveConfig, .saveConfig):
        return true
    case (.log(let message, _), .logContains(let fragment)):
        return message.contains(fragment)
    default:
        return false
    }
}
