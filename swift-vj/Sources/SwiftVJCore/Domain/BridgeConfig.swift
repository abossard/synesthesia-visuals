// BridgeConfig.swift - Pure data model for the OSC/OS2L bridge system
// Following Grokking Simplicity: this is data — immutable, Codable structs with no logic

import Foundation

/// Full configuration for the OSC ↔ OS2L ↔ LedFX bridge pipeline.
public struct OSCBridgeConfig: Codable, Sendable, Equatable {
    public var ports: PortConfig
    public var os2lToLedFX: [LedFXMappingConfig]

    public init(
        ports: PortConfig = .init(),
        os2lToLedFX: [LedFXMappingConfig] = []
    ) {
        self.ports = ports
        self.os2lToLedFX = os2lToLedFX
    }

    // MARK: - Port Configuration

    public struct PortConfig: Codable, Sendable, Equatable {
        public var os2lListen: UInt16
        public var os2lForward: UInt16
        public var oscVdjIn: UInt16
        public var ledFXAPI: String

        public init(
            os2lListen: UInt16 = 9997,
            os2lForward: UInt16 = 9996,
            oscVdjIn: UInt16 = 9010,
            ledFXAPI: String = "http://127.0.0.1:8888"
        ) {
            self.os2lListen = os2lListen
            self.os2lForward = os2lForward
            self.oscVdjIn = oscVdjIn
            self.ledFXAPI = ledFXAPI
        }
    }

    // MARK: - OS2L → LedFX Mapping (mirrors LedFXMapping)

    /// Codable configuration for an OS2L-to-LedFX mapping.
    /// Uses `targetName` instead of `playlistName` for clarity.
    public struct LedFXMappingConfig: Codable, Sendable, Equatable {
        public var os2lButtonName: String
        public var targetName: String
        public var isScene: Bool

        public init(
            os2lButtonName: String,
            targetName: String,
            isScene: Bool = false
        ) {
            self.os2lButtonName = os2lButtonName
            self.targetName = targetName
            self.isScene = isScene
        }

        /// Convert to the runtime `LedFXMapping` used by the bridge actor.
        public func toMapping() -> LedFXMapping {
            LedFXMapping(
                os2lButtonName: os2lButtonName,
                playlistName: targetName,
                isScene: isScene
            )
        }
    }

    // MARK: - Default Configuration

    public static let `default` = OSCBridgeConfig(
        ports: PortConfig(),
        os2lToLedFX: [
            LedFXMappingConfig(os2lButtonName: "blackout", targetName: "off", isScene: true),
            LedFXMappingConfig(os2lButtonName: "*", targetName: "$1", isScene: false),
        ]
    )
}
