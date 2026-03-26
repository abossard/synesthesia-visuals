// OS2LToLedFXBridge.swift - Maps OS2L button events to LedFX playlist/scene actions
// Deep module: hides mapping logic behind a simple handleOS2LEvent() call

import Foundation

// MARK: - Mapping Configuration (Data)

public struct LedFXMapping: Sendable, Equatable {
    public let os2lButtonName: String   // "*" for wildcard
    public let playlistName: String     // "$1" for passthrough (uses button name as-is)
    public let isScene: Bool            // false=playlist, true=scene

    public init(os2lButtonName: String, playlistName: String, isScene: Bool = false) {
        self.os2lButtonName = os2lButtonName
        self.playlistName = playlistName
        self.isScene = isScene
    }
}

// MARK: - Bridge Actor

public actor OS2LToLedFXBridge {
    private let client: LedFXClient
    private var mappings: [LedFXMapping] = [
        LedFXMapping(os2lButtonName: "blackout", playlistName: "off", isScene: true),
        LedFXMapping(os2lButtonName: "*", playlistName: "$1"),
    ]

    public init(ledFXBaseURL: String = "http://127.0.0.1:8888") {
        self.client = LedFXClient(baseURL: ledFXBaseURL)
    }

    public init(client: LedFXClient) {
        self.client = client
    }

    public func setMappings(_ mappings: [LedFXMapping]) {
        self.mappings = mappings
    }

    /// Handle an OS2L event. Only .button events with state .on trigger actions.
    public func handleOS2LEvent(_ event: OS2LEvent) async {
        guard case let .button(name, state) = event, state == .on else { return }

        guard let resolved = resolveMapping(buttonName: name) else { return }

        do {
            if resolved.isScene {
                try await client.activateScene(id: resolved.targetName)
            } else {
                try await client.startPlaylist(id: resolved.targetName)
            }
        } catch {
            // Log and swallow — bridge is fire-and-forget during live performance
            print("[OS2LToLedFXBridge] Failed to activate \(resolved.isScene ? "scene" : "playlist") '\(resolved.targetName)': \(error.localizedDescription)")
        }
    }
}

// MARK: - Pure Mapping Resolution (Calculation)

struct ResolvedMapping: Equatable {
    let targetName: String
    let isScene: Bool
}

/// Resolve a button name against an ordered list of mappings.
/// First exact match wins; wildcard "*" matches anything.
/// "$1" in playlistName is replaced with the button name.
func resolveMapping(buttonName: String, mappings: [LedFXMapping]) -> ResolvedMapping? {
    for mapping in mappings {
        let matches = mapping.os2lButtonName == buttonName || mapping.os2lButtonName == "*"
        guard matches else { continue }

        let targetName = mapping.playlistName == "$1" ? buttonName : mapping.playlistName
        return ResolvedMapping(targetName: targetName, isScene: mapping.isScene)
    }
    return nil
}

private extension OS2LToLedFXBridge {
    func resolveMapping(buttonName: String) -> ResolvedMapping? {
        SwiftVJCore.resolveMapping(buttonName: buttonName, mappings: mappings)
    }
}
