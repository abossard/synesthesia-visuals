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
    /// The LaunchpadModule uses a dispatch callback pattern internally
    public static func start(
        launchpadModule: LaunchpadModule,
        dispatch: @escaping @Sendable (AppAction) -> Void
    ) -> Effect<LaunchpadAction> {
        .run(cancellationId: EffectCancellationId.launchpad) { send in
            // Wire up the dispatch callback
            launchpadModule.dispatch = dispatch

            // Start the module
            await launchpadModule.start()

            // Get initial status
            let status = await launchpadModule.getStatus()
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
            await launchpadModule.stop()
        }
    }

    /// Handle button press - let the module handle it via its FSM
    /// Note: The LaunchpadModule handles button presses internally via MIDI callbacks
    public static func handleButtonPress(
        x: Int,
        y: Int,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        // Button presses are handled internally by LaunchpadModule via MIDI callbacks
        // This effect just gets the updated status after
        .run { send in
            let status = await launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))
        }
    }

    /// Handle button release - let the module handle it via its FSM
    public static func handleButtonRelease(
        x: Int,
        y: Int,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        // Button releases are handled internally by LaunchpadModule via MIDI callbacks
        .run { send in
            let status = await launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))
        }
    }

    /// Change bank
    public static func changeBank(
        _ bank: Int,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        .run { send in
            // Bank changes are handled via the top row buttons in LaunchpadModule
            // This effect is for programmatic bank changes
            await send(.bankChanged(bank))

            let status = await launchpadModule.getStatus()
            await send(.statusUpdated(LaunchpadStatusSnapshot(from: status)))
        }
    }

    /// Enter learn mode
    public static func enterLearnMode(
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        // Learn mode is toggled via Scene button press on the LaunchpadModule
        .none
    }

    /// Exit learn mode
    public static func exitLearnMode(
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        // Learn mode is exited via Scene button press on the LaunchpadModule
        .none
    }

    /// Legacy placeholder kept for compatibility while BPM sync is removed.
    public static func updateBPM(
        _ bpm: Float,
        launchpadModule: LaunchpadModule
    ) -> Effect<LaunchpadAction> {
        _ = bpm
        _ = launchpadModule
        return .none
    }
}
