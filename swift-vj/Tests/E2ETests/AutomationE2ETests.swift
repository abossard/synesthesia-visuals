import XCTest
@testable import SwiftVJCore
@testable import SongRepository

@MainActor
final class AutomationE2ETests: XCTestCase {
    private func configureAutomationBridge(
        hub: OSCHub,
        store: Store<SwiftVJCore.AppState, AppAction>
    ) {
        hub.outgoingMessageHandler = { target, address, args, source in
            Task { @MainActor in
                guard source != "automation-replay" else { return }
                guard let track = store.state.playback.currentTrack else { return }
                guard let oscTarget = AutomationOSCTarget(rawValue: target.lowercased()) else { return }
                let songID = SongID(artist: track.artist, title: track.title)
                let position = store.state.playback.position
                let automationArgs = args.map(Self.automationOSCValue(from:))
                store.send(.automation(.recordOSC(
                    songID: songID,
                    position: position,
                    target: oscTarget,
                    address: address,
                    args: automationArgs,
                    source: source
                )))
            }
        }
    }

    private static func automationOSCValue(from arg: OscArg) -> AutomationOSCValue {
        switch arg {
        case .int(let value):
            return .int(value)
        case .float(let value):
            return .float(Double(value))
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        }
    }

    func testOutgoingOSCBridgeRecordsOnlyMatchingPrefixes() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }

        let store = Store(initialState: SwiftVJCore.AppState(), reducer: appReducer)
        configureAutomationBridge(hub: hub, store: store)

        let track = Track(artist: "Artist", title: "Prefix Song")
        store.send(.playback(.trackChanged(track)))
        store.send(.playback(.positionUpdated(position: 12.0, isPlaying: true)))
        store.send(.automation(.setEnabled(true)))
        store.send(.automation(.setAutoRecordEnabled(true)))
        store.send(.automation(.setAutoRecordPrefixes(["/ledfx/"])))

        try hub.sendToSynesthesia("/not/recorded", values: [Float32(0.5)], source: "launchpad")
        try hub.sendToSynesthesia("/ledfx/recorded", values: [Float32(0.7)], source: "launchpad")
        try await Task.sleep(for: .milliseconds(120))

        let songID = SongID(artist: "Artist", title: "Prefix Song")
        let cues = store.state.automation.timelineBySongId[songID.rawValue]?.cues ?? []
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.value, "/ledfx/recorded")
        XCTAssertEqual(cues.first?.oscTarget, .synesthesia)
    }

    func testOutgoingOSCBridgeAppliesRateAndDeltaGuards() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }

        let store = Store(initialState: SwiftVJCore.AppState(), reducer: appReducer)
        configureAutomationBridge(hub: hub, store: store)

        let track = Track(artist: "Artist", title: "Rate Delta Song")
        store.send(.playback(.trackChanged(track)))
        store.send(.automation(.setEnabled(true)))
        store.send(.automation(.setAutoRecordEnabled(true)))
        store.send(.automation(.setAutoRecordPrefixes(["/ledfx/"])))

        store.send(.playback(.positionUpdated(position: 1.00, isPlaying: true)))
        try hub.sendToMagic("/ledfx/fader", values: [Float32(0.50)], source: "ui")
        try await Task.sleep(for: .milliseconds(25))

        store.send(.playback(.positionUpdated(position: 1.05, isPlaying: true)))
        try hub.sendToMagic("/ledfx/fader", values: [Float32(0.80)], source: "ui")
        try await Task.sleep(for: .milliseconds(25))

        store.send(.playback(.positionUpdated(position: 1.20, isPlaying: true)))
        try hub.sendToMagic("/ledfx/fader", values: [Float32(0.505)], source: "ui")
        try await Task.sleep(for: .milliseconds(25))

        store.send(.playback(.positionUpdated(position: 1.35, isPlaying: true)))
        try hub.sendToMagic("/ledfx/fader", values: [Float32(0.52)], source: "ui")

        try await Task.sleep(for: .milliseconds(120))

        let songID = SongID(artist: "Artist", title: "Rate Delta Song")
        let cues = store.state.automation.timelineBySongId[songID.rawValue]?.cues ?? []
        XCTAssertEqual(cues.count, 2)
        guard cues.count == 2 else { return }
        XCTAssertEqual(cues[0].timeSec, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[1].timeSec, 1.35, accuracy: 0.001)
        guard case .float(let firstValue)? = cues[0].args.first else {
            XCTFail("Expected first cue numeric value")
            return
        }
        guard case .float(let secondValue)? = cues[1].args.first else {
            XCTFail("Expected second cue numeric value")
            return
        }
        XCTAssertEqual(firstValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(secondValue, 0.52, accuracy: 0.001)
    }
}
