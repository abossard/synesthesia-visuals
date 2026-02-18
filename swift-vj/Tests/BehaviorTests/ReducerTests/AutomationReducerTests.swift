import XCTest
@testable import SwiftVJCore
import SongRepository

@MainActor
final class AutomationReducerTests: XCTestCase {
    private actor ActionCollector {
        private var actions: [AppAction] = []
        func append(_ action: AppAction) { actions.append(action) }
        func snapshot() -> [AppAction] { actions }
    }

    private func applyAutomationReducer(
        _ action: AutomationAction,
        to appState: inout AppState
    ) -> Effect<AppAction> {
        var automationState = appState.automation
        let effect = automationReducer(state: &automationState, action: action, appState: &appState)
        appState.automation = automationState
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

    func testRecordLedFXActionAddsCueWhenAutoRecordEnabled() async {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Song")
        appState.automation.isEnabled = true
        appState.automation.autoRecordEnabled = true

        let effect = applyAutomationReducer(
            .recordLedFXAction(
                songID: songID,
                position: 12.5,
                action: .activatePlaylist("peak-set")
            ),
            to: &appState
        )

        let cues = appState.automation.timelineBySongId[songID.rawValue]?.cues ?? []
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.actionType, .ledfxActivatePlaylist)
        XCTAssertEqual(cues.first?.value, "peak-set")

        let emitted = await collectActions(from: effect)
        XCTAssertEqual(emitted.count, 1)
        guard case .persistState = emitted[0] else {
            XCTFail("Expected persistState after auto-recorded cue")
            return
        }
    }

    func testPlaybackTickFiresCueOnlyOnceAcrossBoundary() async {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Song")
        appState.automation.isEnabled = true
        appState.automation.playbackSongId = songID
        appState.automation.timelineBySongId[songID.rawValue] = SongAutomationTimeline(
            cues: [
                AutomationCue(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    timeSec: 5.0,
                    actionType: .ledfxActivateScene,
                    value: "drop"
                )
            ],
            valueLanes: []
        )

        let first = applyAutomationReducer(.playbackTick(position: 4.9, isPlaying: true), to: &appState)
        let firstActions = await collectActions(from: first)
        XCTAssertTrue(firstActions.isEmpty)

        let second = applyAutomationReducer(.playbackTick(position: 5.1, isPlaying: true), to: &appState)
        let secondActions = await collectActions(from: second)
        XCTAssertEqual(secondActions.count, 1)
        guard case .ledfx(.activateScene(let sceneID)) = secondActions[0] else {
            XCTFail("Expected ledfx.activateScene cue execution")
            return
        }
        XCTAssertEqual(sceneID, "drop")

        let third = applyAutomationReducer(.playbackTick(position: 5.8, isPlaying: true), to: &appState)
        let thirdActions = await collectActions(from: third)
        XCTAssertTrue(thirdActions.isEmpty)
    }

    func testPlaybackTickInterpolatesBrightnessLane() async {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Song")
        appState.automation.isEnabled = true
        appState.automation.playbackSongId = songID
        appState.automation.timelineBySongId[songID.rawValue] = SongAutomationTimeline(
            cues: [],
            valueLanes: [
                AutomationValueLane(
                    id: "ledfx-brightness:main",
                    displayName: "Brightness main",
                    targetType: .ledfxVirtualBrightness,
                    target: "main",
                    points: [
                        AutomationValuePoint(timeSec: 0, value: 0),
                        AutomationValuePoint(timeSec: 10, value: 1)
                    ]
                )
            ]
        )

        _ = applyAutomationReducer(.playbackTick(position: 0, isPlaying: true), to: &appState)
        let effect = applyAutomationReducer(.playbackTick(position: 5, isPlaying: true), to: &appState)
        let emitted = await collectActions(from: effect)

        XCTAssertEqual(emitted.count, 1)
        guard case .ledfx(.setVirtualBrightness(let id, let brightness)) = emitted[0] else {
            XCTFail("Expected brightness command")
            return
        }
        XCTAssertEqual(id, "main")
        XCTAssertEqual(brightness, 0.5, accuracy: 0.001)
    }

    func testRecordOSCIgnoresAddressOutsideConfiguredPrefixes() async {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Song")
        appState.automation.isEnabled = true
        appState.automation.autoRecordEnabled = true
        appState.automation.autoRecordPrefixes = ["/ledfx/"]

        let effect = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 3.0,
                target: .synesthesia,
                address: "/not-recorded/value",
                args: [.float(0.5)],
                source: "launchpad"
            ),
            to: &appState
        )

        let cues = appState.automation.timelineBySongId[songID.rawValue]?.cues ?? []
        XCTAssertTrue(cues.isEmpty)
        let emitted = await collectActions(from: effect)
        XCTAssertTrue(emitted.isEmpty)
    }

    func testRecordOSCRespectsSamplingRateLimit() {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Song")
        appState.automation.isEnabled = true
        appState.automation.autoRecordEnabled = true
        appState.automation.autoRecordPrefixes = ["/ledfx/"]
        appState.automation.autoRecordMaxHz = 10

        _ = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 1.0,
                target: .synesthesia,
                address: "/ledfx/brightness",
                args: [.float(0.2)],
                source: "launchpad"
            ),
            to: &appState
        )
        _ = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 1.05,
                target: .synesthesia,
                address: "/ledfx/brightness",
                args: [.float(0.8)],
                source: "launchpad"
            ),
            to: &appState
        )
        _ = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 1.11,
                target: .synesthesia,
                address: "/ledfx/brightness",
                args: [.float(0.8)],
                source: "launchpad"
            ),
            to: &appState
        )

        let cues = appState.automation.timelineBySongId[songID.rawValue]?.cues ?? []
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].timeSec, 1.0, accuracy: 0.0001)
        XCTAssertEqual(cues[1].timeSec, 1.11, accuracy: 0.0001)
    }

    func testRecordOSCDropsTinyNumericDelta() {
        var appState = AppState()
        let songID = SongID(artist: "Artist", title: "Song")
        appState.automation.isEnabled = true
        appState.automation.autoRecordEnabled = true
        appState.automation.autoRecordPrefixes = ["/ledfx/"]
        appState.automation.autoRecordMaxHz = 10
        appState.automation.autoRecordMinDelta = 0.01

        _ = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 2.0,
                target: .magic,
                address: "/ledfx/fader",
                args: [.float(0.50)],
                source: "ui"
            ),
            to: &appState
        )
        _ = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 2.2,
                target: .magic,
                address: "/ledfx/fader",
                args: [.float(0.505)],
                source: "ui"
            ),
            to: &appState
        )
        _ = applyAutomationReducer(
            .recordOSC(
                songID: songID,
                position: 2.4,
                target: .magic,
                address: "/ledfx/fader",
                args: [.float(0.52)],
                source: "ui"
            ),
            to: &appState
        )

        let cues = appState.automation.timelineBySongId[songID.rawValue]?.cues ?? []
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].args, [.float(0.50)])
        XCTAssertEqual(cues[1].args, [.float(0.52)])
    }
}
