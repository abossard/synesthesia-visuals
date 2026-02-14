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
}
