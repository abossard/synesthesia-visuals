// LaunchpadEffectsImpl.swift - Launchpad controller effects
// Effects for MIDI controller interaction

import Foundation

/// Dependencies needed by Launchpad effects
public struct LaunchpadEnvironment: Sendable {
    public let launchpadModule: LaunchpadModule

    public init(launchpadModule: LaunchpadModule) {
        self.launchpadModule = launchpadModule
    }
}

/// Effects for Launchpad controller
public enum LaunchpadEffectsImpl {

    /// Start Launchpad module and subscribe to events
    public static func start(
        launchpadModule: LaunchpadModule,
        onConnectionChange: @escaping @Sendable (Bool, String?) -> Void,
        onStateChange: @escaping @Sendable (ControllerState) -> Void
    ) -> Effect<LaunchpadAction> {
        .run(cancellationId: EffectCancellationId.launchpad) { send in
            // Wire up callbacks
            launchpadModule.onConnectionChange = { connected, deviceName in
                onConnectionChange(connected, deviceName)
                Task {
                    if connected, let name = deviceName {
                        await send(.connected(name))
                    } else {
                        await send(.disconnected)
                    }
                }
            }

            launchpadModule.onStateChange = { state in
                onStateChange(state)
                Task {
                    await send(.stateUpdated(ControllerStateSnapshot(from: state)))
                }
            }

            // Start the module
            launchpadModule.start()

            // Get initial status
            let status = launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))

            // Keep effect alive
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Stop Launchpad module
    public static func stop(
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .fireAndForget {
            launchpadModule.stop()
        }
    }

    /// Handle button press
    public static func handleButtonPress(
        x: Int,
        y: Int,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .run { send in
            let buttonId = ButtonId(x: x, y: y)
            launchpadModule.handleButtonPress(buttonId)

            // Get updated state
            let status = launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))
        }
    }

    /// Handle button release
    public static func handleButtonRelease(
        x: Int,
        y: Int,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .run { send in
            let buttonId = ButtonId(x: x, y: y)
            launchpadModule.handleButtonRelease(buttonId)

            // Get updated state
            let status = launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))
        }
    }

    /// Change bank
    public static func changeBank(
        _ bank: Int,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .run { send in
            launchpadModule.setBank(bank)
            await send(.bankChanged(bank))

            let status = launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))
        }
    }

    /// Enter learn mode
    public static func enterLearnMode(
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .fireAndForget {
            launchpadModule.enterLearnMode()
        }
    }

    /// Exit learn mode
    public static func exitLearnMode(
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .fireAndForget {
            launchpadModule.exitLearnMode()
        }
    }

    /// Update BPM for beat sync
    public static func updateBPM(
        _ bpm: Float,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .fireAndForget {
            launchpadModule.updateBpm(bpm)
        }
    }
}
