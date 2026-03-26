import SwiftVJCore

/// Test fixtures for OS2L protocol messages.
/// Each fixture pairs raw JSON with the expected parsed result.
enum OS2LFixtures {
    struct Fixture {
        let json: String
        let expected: OS2LEvent
        let label: String
    }

    static let allEvents: [Fixture] = [
        Fixture(json: #"{"evt":"btn","name":"strobe","state":"on"}"#,
                expected: .button(name: "strobe", state: .on),
                label: "button strobe on"),
        Fixture(json: #"{"evt":"btn","name":"blackout","state":"off"}"#,
                expected: .button(name: "blackout", state: .off),
                label: "button blackout off"),
        Fixture(json: #"{"evt":"cmd","id":1,"param":75}"#,
                expected: .command(id: 1, param: 75),
                label: "command id:1 param:75"),
        Fixture(json: #"{"evt":"cmd","id":42,"param":0}"#,
                expected: .command(id: 42, param: 0),
                label: "command id:42 param:0"),
        Fixture(json: #"{"evt":"beat"}"#,
                expected: .beat,
                label: "beat"),
    ]

    static let buttonEvents: [Fixture] = allEvents.filter {
        if case .button = $0.expected { return true }
        return false
    }

    /// Multi-line payload (simulates VDJ sending rapid events)
    static var multiLinePayload: String {
        allEvents.map(\.json).joined(separator: "\n") + "\n"
    }

    /// Split payload for TCP reassembly test — breaks mid-JSON
    static var splitPayloads: [String] {
        let full = multiLinePayload
        let midpoint = full.index(full.startIndex, offsetBy: full.count / 2)
        return [String(full[..<midpoint]), String(full[midpoint...])]
    }
}
