import XCTest
@testable import SwiftVJCore

@MainActor
final class LauncherReducerTests: XCTestCase {
    private actor ActionCollector {
        private var actions: [AppAction] = []
        func append(_ action: AppAction) { actions.append(action) }
        func snapshot() -> [AppAction] { actions }
    }

    private actor MockLauncherHandler: LauncherEffectHandling {
        let analyzedTargets: [LaunchTarget]
        let launchResult: (launched: Bool, error: String?)
        let launchReport: LauncherLaunchReport

        init(
            analyzedTargets: [LaunchTarget] = [],
            launchResult: (launched: Bool, error: String?) = (true, nil),
            launchReport: LauncherLaunchReport = LauncherLaunchReport()
        ) {
            self.analyzedTargets = analyzedTargets
            self.launchResult = launchResult
            self.launchReport = launchReport
        }

        func analyzeDroppedItems(_ urls: [URL]) async -> [LaunchTarget] {
            analyzedTargets
        }

        func launchTarget(_ target: LaunchTarget) async -> (launched: Bool, error: String?) {
            launchResult
        }

        func launchTargetsIfNeeded(_ targets: [LaunchTarget]) async -> LauncherLaunchReport {
            launchReport
        }

        func terminateTarget(_ target: LaunchTarget) async -> (terminated: Bool, error: String?) {
            (true, nil)
        }

        func terminateAll(_ targets: [LaunchTarget]) async -> LauncherTerminateReport {
            LauncherTerminateReport()
        }

        func showTerminal(targetID: String) async {}
    }

    private func applyLauncherReducer(_ action: LauncherAction, to appState: inout AppState) -> Effect<AppAction> {
        var launcherState = appState.launcher
        let effect = launcherReducer(state: &launcherState, action: action, appState: &appState)
        appState.launcher = launcherState
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

    func testAddCommandTargetRequestedAddsTargetAndPersists() async {
        var appState = AppState()

        let effect = applyLauncherReducer(
            .addCommandTargetRequested(
                commandLine: "uv run ledfx",
                workingDirectory: "~/Desktop/projects/ledfx"
            ),
            to: &appState
        )

        XCTAssertEqual(appState.launcher.targets.count, 1)
        XCTAssertEqual(appState.launcher.targets[0].kind, .command)
        XCTAssertEqual(appState.launcher.targets[0].commandLine, "uv run ledfx")
        XCTAssertEqual(appState.launcher.targets[0].workingDirectory, "~/Desktop/projects/ledfx")

        let actions = await collectActions(from: effect)
        XCTAssertTrue(actions.contains { action in
            if case .persistState = action { return true }
            return false
        })
    }

    func testAddAppTargetsRequestedUsesEffectEnvironmentHandler() async {
        let analyzed = [
            LaunchTarget.appTarget(
                id: "app.bundle.com.spotify.client",
                displayName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                appPath: "/Applications/Spotify.app"
            )
        ]
        EffectEnvironment.shared.launcherHandler = MockLauncherHandler(analyzedTargets: analyzed)
        defer { EffectEnvironment.shared.reset() }

        var appState = AppState()
        let effect = applyLauncherReducer(
            .addAppTargetsRequested([URL(fileURLWithPath: "/Applications/Spotify.app")]),
            to: &appState
        )

        let actions = await collectActions(from: effect)
        XCTAssertEqual(actions.count, 1)
        guard case .launcher(.appTargetsAnalyzed(let targets)) = actions[0] else {
            XCTFail("Expected launcher.appTargetsAnalyzed action")
            return
        }
        XCTAssertEqual(targets, analyzed)
    }

    func testLaunchMissingRequestedSetsLaunchingAndDispatchesCompletion() async {
        let target = LaunchTarget.commandTarget(
            id: "cmd:1",
            displayName: "ledfx",
            commandLine: "uv run ledfx",
            workingDirectory: "~/Desktop/projects/ledfx"
        )
        let report = LauncherLaunchReport(
            launchedTargetIDs: ["cmd:1"],
            alreadyRunningTargetIDs: [],
            failedTargetErrors: [:],
            runningTargetIDs: ["cmd:1"]
        )
        EffectEnvironment.shared.launcherHandler = MockLauncherHandler(launchReport: report)
        defer { EffectEnvironment.shared.reset() }

        var appState = AppState(launcher: LauncherSubState(targets: [target]))
        let effect = applyLauncherReducer(.launchMissingRequested, to: &appState)

        XCTAssertTrue(appState.launcher.isLaunchingAll)

        let actions = await collectActions(from: effect)
        XCTAssertEqual(actions.count, 1)
        guard case .launcher(.launchAllCompleted(let emitted)) = actions[0] else {
            XCTFail("Expected launcher.launchAllCompleted action")
            return
        }
        XCTAssertEqual(emitted, report)
    }

    func testPersistedStateLoadedTriggersAutoStartWhenConfigured() async {
        var autoStartTarget = LaunchTarget.appTarget(
            id: "app.bundle.com.spotify.client",
            displayName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            appPath: "/Applications/Spotify.app"
        )
        autoStartTarget.autoStart = true

        var state = AppState()
        let persisted = PersistedState(
            renderEnabled: true,
            selectedShader: nil,
            selectedMaskShader: nil,
            currentPhase: nil,
            playbackSource: "vdj",
            launcherTargets: [autoStartTarget]
        )

        let effect = appReducer(state: &state, action: .persistedStateLoaded(persisted))
        let actions = await collectActions(from: effect)

        XCTAssertTrue(actions.contains { action in
            if case .launcher(.launchAutoStartRequested) = action { return true }
            return false
        })
    }

    func testStressRapidAutoStartTogglesKeepTargetSetConsistent() {
        var appState = AppState()
        appState.launcher.targets = (0..<48).map { index in
            LaunchTarget.commandTarget(
                id: "cmd:\(index)",
                displayName: "cmd\(index)",
                commandLine: "echo \(index)",
                workingDirectory: nil
            )
        }

        for i in 0..<4_000 {
            let id = "cmd:\(i % 48)"
            _ = applyLauncherReducer(.setAutoStart(id: id, enabled: i.isMultiple(of: 2)), to: &appState)
        }

        XCTAssertEqual(appState.launcher.targets.count, 48)
        XCTAssertEqual(Set(appState.launcher.targets.map(\.id)).count, 48)
    }

    // MARK: - DJ Rig Preset Tests

    func testStartRigAddsMissingTargetsAndLaunches() async {
        let report = LauncherLaunchReport(
            launchedTargetIDs: ["app.bundle.com.atomixproductions.virtualdj"],
            alreadyRunningTargetIDs: [],
            failedTargetErrors: [:],
            runningTargetIDs: ["app.bundle.com.atomixproductions.virtualdj"]
        )
        EffectEnvironment.shared.launcherHandler = MockLauncherHandler(launchReport: report)
        defer { EffectEnvironment.shared.reset() }

        var appState = AppState()
        appState.launcher.rigPreset = LaunchPreset(
            name: "Test Rig",
            targets: [.virtualDJ, .qlcPlus5]
        )

        XCTAssertTrue(appState.launcher.targets.isEmpty)
        let effect = applyLauncherReducer(.startRig, to: &appState)

        // Rig targets should be added to the target list
        XCTAssertEqual(appState.launcher.targets.count, 2)
        XCTAssertTrue(appState.launcher.isLaunchingAll)

        let actions = await collectActions(from: effect)
        // Should include persistState (for added targets) and launchAllCompleted
        XCTAssertTrue(actions.contains { action in
            if case .persistState = action { return true }
            return false
        })
        XCTAssertTrue(actions.contains { action in
            if case .launcher(.launchAllCompleted) = action { return true }
            return false
        })
    }

    func testStartRigSkipsAlreadyConfiguredTargets() async {
        let report = LauncherLaunchReport()
        EffectEnvironment.shared.launcherHandler = MockLauncherHandler(launchReport: report)
        defer { EffectEnvironment.shared.reset() }

        var appState = AppState()
        appState.launcher.rigPreset = LaunchPreset(name: "Test", targets: [.virtualDJ])
        // Pre-add VirtualDJ target
        appState.launcher.targets = [KnownAppTarget.virtualDJ.launchTarget]

        let initialCount = appState.launcher.targets.count
        _ = applyLauncherReducer(.startRig, to: &appState)

        XCTAssertEqual(appState.launcher.targets.count, initialCount)
        XCTAssertTrue(appState.launcher.isLaunchingAll)
    }

    func testStartRigWithEmptyPresetSetsError() {
        var appState = AppState()
        appState.launcher.rigPreset = LaunchPreset(name: "Empty", targets: [])

        let effect = applyLauncherReducer(.startRig, to: &appState)
        XCTAssertEqual(appState.launcher.lastError, "No targets configured in rig preset.")
        XCTAssertFalse(appState.launcher.isLaunchingAll)

        switch effect.operation {
        case .none: break
        default: XCTFail("Expected no effect for empty rig")
        }
    }

    func testStopRigTerminatesRigTargets() async {
        EffectEnvironment.shared.launcherHandler = MockLauncherHandler()
        defer { EffectEnvironment.shared.reset() }

        var appState = AppState()
        appState.launcher.rigPreset = LaunchPreset(name: "Test", targets: [.virtualDJ, .qlcPlus5])
        appState.launcher.targets = [
            KnownAppTarget.virtualDJ.launchTarget,
            KnownAppTarget.qlcPlus5.launchTarget,
            // Non-rig target should not be terminated
            LaunchTarget.appTarget(
                id: "app.bundle.com.spotify.client",
                displayName: "Spotify",
                bundleIdentifier: "com.spotify.client",
                appPath: "/Applications/Spotify.app"
            ),
        ]

        let effect = applyLauncherReducer(.stopRig, to: &appState)
        let actions = await collectActions(from: effect)

        // Should dispatch terminateAllCompleted (which only covers rig targets)
        XCTAssertTrue(actions.contains { action in
            if case .launcher(.terminateAllCompleted) = action { return true }
            return false
        })
    }

    func testSetRigPresetPersists() async {
        var appState = AppState()
        let newPreset = LaunchPreset(name: "Custom Rig", targets: [.magicMusicVisuals, .ledFX])
        let effect = applyLauncherReducer(.setRigPreset(newPreset), to: &appState)

        XCTAssertEqual(appState.launcher.rigPreset, newPreset)

        let actions = await collectActions(from: effect)
        XCTAssertTrue(actions.contains { action in
            if case .persistState = action { return true }
            return false
        })
    }

    func testDefaultRigPresetContainsExpectedTargets() {
        let preset = LaunchPreset.defaultDJRig
        XCTAssertEqual(preset.name, "DJ Rig")
        XCTAssertEqual(preset.targets, [.virtualDJ, .qlcPlus5, .magicMusicVisuals])
    }

    func testKnownAppTargetAllCasesIncludesNewTargets() {
        let allCases = KnownAppTarget.allCases
        XCTAssertTrue(allCases.contains(.virtualDJ))
        XCTAssertTrue(allCases.contains(.qlcPlus5))
        XCTAssertTrue(allCases.contains(.magicMusicVisuals))
        XCTAssertTrue(allCases.contains(.ledFX))
    }

    func testRigPresetCodableRoundTrip() throws {
        let preset = LaunchPreset(name: "My Rig", targets: [.virtualDJ, .ledFX])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(LaunchPreset.self, from: data)
        XCTAssertEqual(decoded, preset)
    }

    func testPersistedStateDecodesWithoutRigPreset() throws {
        // Simulate old persisted JSON without rigPreset field
        let oldJSON: [String: Any] = [
            "renderEnabled": true,
            "playbackSource": "vdj",
            "launcherTargets": [] as [Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: oldJSON)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded.rigPreset, .defaultDJRig)
    }
}
