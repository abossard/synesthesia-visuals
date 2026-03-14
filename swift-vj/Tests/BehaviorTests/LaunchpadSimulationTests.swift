import XCTest
@testable import SwiftVJCore

final class LaunchpadSimulationTests: XCTestCase {
    private final class CommandRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var commands: [OscCommand] = []

        func append(_ command: OscCommand) {
            lock.lock()
            commands.append(command)
            lock.unlock()
        }

        func snapshot() -> [OscCommand] {
            lock.lock()
            defer { lock.unlock() }
            return commands
        }
    }

    private final class ActionRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var actions: [AppAction] = []

        func append(_ action: AppAction) {
            lock.lock()
            actions.append(action)
            lock.unlock()
        }

        func snapshot() -> [AppAction] {
            lock.lock()
            defer { lock.unlock() }
            return actions
        }
    }

    private func eventually(
        timeoutMs: Int = 2000,
        stepMs: Int = 20,
        _ predicate: () async -> Bool
    ) async -> Bool {
        let iterations = max(1, timeoutMs / stepMs)
        for _ in 0..<iterations {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(stepMs))
        }
        return await predicate()
    }

    private func makeTempConfigPath() throws -> (directory: URL, path: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("launchpad-config.json"))
    }

    private func dynamicAddresses(module: LaunchpadModule, bank: Int) async -> Set<String> {
        let pads = await module.getFullState().bankPads[bank] ?? [:]
        return Set(pads.values.compactMap { behavior in
            behavior.oscAction?.address ?? behavior.oscOn?.address ?? behavior.oscOff?.address
        })
    }

    func testVirtualSimulationLearnRecordAndReplaySceneWithLedFX() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }

        let commandRecorder = CommandRecorder()
        let actionRecorder = ActionRecorder()
        let module = LaunchpadModule(
            oscSender: { command in
                commandRecorder.append(command)
            },
            configPath: paths.path
        )
        module.dispatch = { action in
            actionRecorder.append(action)
        }
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(7))
        let switchedToBank7 = await eventually { await module.getFullState().activeBank == 7 }
        XCTAssertTrue(switchedToBank7)

        await module.handleVirtualPadPress(LaunchpadButton.learn)
        let targetPad = ButtonId(x: 1, y: 1)
        await module.handleVirtualPadPress(targetPad)
        let enteredConfig = await eventually {
            let state = await module.getFullState()
            return state.learnState.phase == .config && state.learnState.selectedPad == targetPad
        }
        XCTAssertTrue(enteredConfig)

        await module.receiveOscEvent(OscEvent(address: "/scenes/Example", args: [.string("Example")]))
        await module.receiveOscEvent(OscEvent(address: "/ledfx/scene/strobe/0", args: [.float(1.0)]))
        let capturedOSC = await eventually {
            await module.getFullState().learnState.capturedOsc.count >= 2
        }
        XCTAssertTrue(capturedOSC)

        await module.handleVirtualPadPress(LaunchpadButton.save)
        let savedConfig = await eventually {
            let state = await module.getFullState()
            return state.learnState.phase == .idle && state.bankPads[7]?[targetPad] != nil
        }
        XCTAssertTrue(savedConfig)

        let saved = await module.getFullState().bankPads[7]?[targetPad]
        XCTAssertEqual(saved?.oscAction?.address, "/scenes/Example")
        XCTAssertEqual(saved?.additionalOsc.map(\.address), ["/ledfx/scene/strobe/0"])

        await module.handleVirtualPadPress(targetPad)
        let replaySentExpectedOSC = await eventually {
            let addresses = commandRecorder.snapshot().map(\.address)
            return addresses.contains("/scenes/Example") && addresses.contains("/ledfx/scene/strobe/0")
        }
        XCTAssertTrue(replaySentExpectedOSC)

        let actions = actionRecorder.snapshot()
        XCTAssertTrue(actions.contains {
            guard case .launchpad(.stateUpdated(let state)) = $0 else { return false }
            return state.activeBank == 7
        })
    }

    func testVirtualSimulationDoesNotRecordWithoutLearnMode() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }

        let module = LaunchpadModule(configPath: paths.path)
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(7))
        let switchedToBank7 = await eventually { await module.getFullState().activeBank == 7 }
        XCTAssertTrue(switchedToBank7)

        let targetPad = ButtonId(x: 2, y: 1)
        await module.receiveOscEvent(OscEvent(address: "/scenes/Example", args: [.string("Example")]))
        await module.receiveOscEvent(OscEvent(address: "/ledfx/scene/strobe/0", args: [.float(1.0)]))
        await module.handleVirtualPadPress(targetPad)

        let remainedIdleWithoutRecording = await eventually {
            let state = await module.getFullState()
            return state.learnState.phase == .idle && state.bankPads[7]?[targetPad] == nil
        }
        XCTAssertTrue(remainedIdleWithoutRecording)
    }

    func testVirtualSimulationReportsConnectedStatusWithoutHardware() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }

        let module = LaunchpadModule(configPath: paths.path)
        _ = await module.start()
        defer { Task { await module.stop() } }

        let hasTwinStatus = await eventually {
            let status = await module.getStatus()
            return status.isConnected && status.deviceName != nil
        }
        XCTAssertTrue(hasTwinStatus)
    }

    func testDynamicParamsBankClearsOnSceneChangeAndTracksActiveScene() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        await DynamicControlStore.shared.clear()

        let module = LaunchpadModule(configPath: paths.path)
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(6))
        let switchedToBank6 = await eventually { await module.getFullState().activeBank == 6 }
        XCTAssertTrue(switchedToBank6)

        await module.receiveOscEvent(OscEvent(address: "/scenes/first"))
        await module.receiveOscEvent(OscEvent(address: "/controls/first/radiusring", args: [.float(0.42)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/meta/brightness", args: [.float(0.5)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/other/should_not_bind", args: [.float(0.9)]))

        let firstSceneLoaded = await eventually {
            let sceneAddresses = await self.dynamicAddresses(module: module, bank: 6)
            let metaAddresses = await self.dynamicAddresses(module: module, bank: 5)
            return sceneAddresses.contains("/controls/first/radiusring")
                && !sceneAddresses.contains("/controls/meta/brightness")
                && !sceneAddresses.contains("/controls/other/should_not_bind")
                && metaAddresses.contains("/controls/meta/brightness")
        }
        XCTAssertTrue(firstSceneLoaded)

        await module.receiveOscEvent(OscEvent(address: "/scenes/second"))
        let firstSceneCleared = await eventually {
            let addresses = await self.dynamicAddresses(module: module, bank: 6)
            return !addresses.contains("/controls/first/radiusring")
        }
        XCTAssertTrue(firstSceneCleared)

        await module.receiveOscEvent(OscEvent(address: "/controls/second/aberration", args: [.float(0.7)]))
        let secondSceneLoaded = await eventually {
            let sceneAddresses = await self.dynamicAddresses(module: module, bank: 6)
            let metaAddresses = await self.dynamicAddresses(module: module, bank: 5)
            return sceneAddresses.contains("/controls/second/aberration")
                && !sceneAddresses.contains("/controls/first/radiusring")
                && metaAddresses.contains("/controls/meta/brightness")
        }
        XCTAssertTrue(secondSceneLoaded)
    }

    func testDynamicParamsBankInfersToggleAndEnumStepper() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        await DynamicControlStore.shared.clear()

        let module = LaunchpadModule(configPath: paths.path)
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(6))
        let switchedToBank6 = await eventually { await module.getFullState().activeBank == 6 }
        XCTAssertTrue(switchedToBank6)

        await module.receiveOscEvent(OscEvent(address: "/scenes/compoundiris"))
        await module.receiveOscEvent(OscEvent(address: "/controls/compoundiris/invert", args: [.float(0.0)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/meta/playbackmode", args: [.float(1.0)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/meta/playbackmode/numoptions", args: [.int(4)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/meta/playbackmode/label", args: [.string("shuffle")]))

        let inferred = await eventually {
            let scenePads = await module.getFullState().bankPads[6] ?? [:]
            let metaPads = await module.getFullState().bankPads[5] ?? [:]
            let invert = scenePads.values.first { behavior in
                behavior.oscOn?.address == "/controls/compoundiris/invert"
            }
            let playback = metaPads.values.first { behavior in
                behavior.oscAction?.address == "/controls/meta/playbackmode"
            }
            return invert?.mode == .toggle
                && playback?.mode == .increment
                && playback?.enumOptionCount == 4
                && abs((playback?.step ?? 0) - (1.0 / 3.0)) < 0.0001
                && playback?.maxValue == 1.0
        }
        XCTAssertTrue(inferred)
    }

    func testDynamicMetaEnumControlCyclesForwardAndShiftBackward() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        await DynamicControlStore.shared.clear()

        let commandRecorder = CommandRecorder()
        let module = LaunchpadModule(
            oscSender: { command in
                commandRecorder.append(command)
            },
            configPath: paths.path
        )
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(5))
        let switchedToBank5 = await eventually { await module.getFullState().activeBank == 5 }
        XCTAssertTrue(switchedToBank5)

        await module.receiveOscEvent(OscEvent(address: "/controls/meta/playbackmode", args: [.float(0.0)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/meta/playbackmode/numoptions", args: [.int(4)]))

        let hasPlaybackPad = await eventually {
            let metaPads = await module.getFullState().bankPads[5] ?? [:]
            return metaPads.values.contains { $0.oscAction?.address == "/controls/meta/playbackmode" }
        }
        XCTAssertTrue(hasPlaybackPad)

        guard let playbackPad = await module.getFullState().bankPads[5]?.first(where: { _, behavior in
            behavior.oscAction?.address == "/controls/meta/playbackmode"
        })?.key else {
            XCTFail("Expected dynamic playbackmode pad in meta bank")
            return
        }

        let countBeforeForward = commandRecorder.snapshot().count
        await module.handleVirtualPadPress(playbackPad)
        let sentForward = await eventually {
            let commands = commandRecorder.snapshot()
            guard commands.count > countBeforeForward,
                  let command = commands.last,
                  command.address == "/controls/meta/playbackmode",
                  let arg = command.args.first else { return false }
            guard case .float(let value) = arg else { return false }
            return abs(value - (1.0 / 3.0)) < 0.0001
        }
        XCTAssertTrue(sentForward)

        await module.handleVirtualPadPress(LaunchpadButton.shift)
        let countBeforeBackward = commandRecorder.snapshot().count
        await module.handleVirtualPadPress(playbackPad)
        await module.handleVirtualPadRelease(LaunchpadButton.shift)
        let sentBackward = await eventually {
            let commands = commandRecorder.snapshot()
            guard commands.count > countBeforeBackward,
                  let command = commands.last,
                  command.address == "/controls/meta/playbackmode",
                  let arg = command.args.first else { return false }
            guard case .float(let value) = arg else { return false }
            return abs(value - 0.0) < 0.0001
        }
        XCTAssertTrue(sentBackward)
    }

    func testDynamicParamsBankGroupsVectorXYControlsAndNudgesFromSideRow() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        await DynamicControlStore.shared.clear()

        let commandRecorder = CommandRecorder()
        let module = LaunchpadModule(
            oscSender: { command in
                commandRecorder.append(command)
            },
            configPath: paths.path
        )
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(6))
        let switchedToBank6 = await eventually { await module.getFullState().activeBank == 6 }
        XCTAssertTrue(switchedToBank6)

        await module.receiveOscEvent(OscEvent(address: "/scenes/platonicsolids"))
        await module.receiveOscEvent(OscEvent(address: "/controls/platonicsolids/camxy/x", args: [.float(0.5)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/platonicsolids/camxy/y", args: [.float(0.5)]))

        let foundVectorPad = await eventually {
            let pads = await module.getFullState().bankPads[6] ?? [:]
            return pads.values.contains { behavior in
                behavior.mode == .vector2 &&
                    behavior.vector2Addresses == [
                        "/controls/platonicsolids/camxy/x",
                        "/controls/platonicsolids/camxy/y",
                    ]
            }
        }
        XCTAssertTrue(foundVectorPad)

        guard let vectorPad = await module.getFullState().bankPads[6]?.first(where: { _, behavior in
            behavior.mode == .vector2 &&
                behavior.vector2Addresses == [
                    "/controls/platonicsolids/camxy/x",
                    "/controls/platonicsolids/camxy/y",
                ]
        })?.key else {
            XCTFail("Expected vector2 pad for platonicsolids camxy")
            return
        }

        await module.handleVirtualPadPress(vectorPad)
        let beforeNudge = commandRecorder.snapshot().count
        await module.handleVirtualPadPress(ButtonId(x: 8, y: 3)) // right

        let sentXNudge = await eventually {
            let commands = commandRecorder.snapshot()
            guard commands.count > beforeNudge,
                  let command = commands.last,
                  command.address == "/controls/platonicsolids/camxy/x",
                  let arg = command.args.first else { return false }
            guard case .float(let value) = arg else { return false }
            return abs(value - 0.6) < 0.0001
        }
        XCTAssertTrue(sentXNudge)
    }

    func testDynamicParamsBankGroupsRGBControlsIntoColorCyclePad() async throws {
        let paths = try makeTempConfigPath()
        defer { try? FileManager.default.removeItem(at: paths.directory) }
        await DynamicControlStore.shared.clear()

        let commandRecorder = CommandRecorder()
        let module = LaunchpadModule(
            oscSender: { command in
                commandRecorder.append(command)
            },
            configPath: paths.path
        )
        _ = await module.start()
        defer { Task { await module.stop() } }

        await module.handleVirtualPadPress(LaunchpadButton.bank(6))
        let switchedToBank6 = await eventually { await module.getFullState().activeBank == 6 }
        XCTAssertTrue(switchedToBank6)

        await module.receiveOscEvent(OscEvent(address: "/scenes/pop"))
        await module.receiveOscEvent(OscEvent(address: "/controls/pop/color1/r", args: [.float(0.3)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/pop/color1/g", args: [.float(0.6)]))
        await module.receiveOscEvent(OscEvent(address: "/controls/pop/color1/b", args: [.float(0.8)]))

        let foundColorPad = await eventually {
            let pads = await module.getFullState().bankPads[6] ?? [:]
            return pads.values.contains { behavior in
                behavior.mode == .colorCycle &&
                    behavior.colorCycleAddresses == [
                        "/controls/pop/color1/r",
                        "/controls/pop/color1/g",
                        "/controls/pop/color1/b",
                    ]
            }
        }
        XCTAssertTrue(foundColorPad)

        guard let colorPad = await module.getFullState().bankPads[6]?.first(where: { _, behavior in
            behavior.mode == .colorCycle &&
                behavior.colorCycleAddresses == [
                    "/controls/pop/color1/r",
                    "/controls/pop/color1/g",
                    "/controls/pop/color1/b",
                ]
        })?.key else {
            XCTFail("Expected color cycle pad for pop/color1")
            return
        }

        let preCount = commandRecorder.snapshot().count
        await module.handleVirtualPadPress(colorPad)
        let sentRGBCommands = await eventually {
            let commands = commandRecorder.snapshot()
            guard commands.count >= preCount + 3 else { return false }
            let recent = Array(commands.suffix(from: preCount))
            let addresses = Set(recent.map(\.address))
            return addresses.contains("/controls/pop/color1/r")
                && addresses.contains("/controls/pop/color1/g")
                && addresses.contains("/controls/pop/color1/b")
        }
        XCTAssertTrue(sentRGBCommands)
    }
}
