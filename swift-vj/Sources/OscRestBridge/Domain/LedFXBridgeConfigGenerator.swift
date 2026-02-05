// LedFXBridgeConfigGenerator.swift - Pure generator for LedFX bridge configs
// Following Grokking Simplicity: calculations only, no side effects

import Foundation
import SwiftVJCore

public enum LedFXBridgeConfigGenerator {

    public struct Input: Sendable, Equatable {
        public let baseURL: String
        public let playlists: [String: LedFXPlaylist]
        public let scenes: [String: LedFXScene]
        public let virtuals: [String: LedFXVirtual]
        public let effects: [String: LedFXEffectEntry]

        public init(
            baseURL: String,
            playlists: [String: LedFXPlaylist],
            scenes: [String: LedFXScene],
            virtuals: [String: LedFXVirtual],
            effects: [String: LedFXEffectEntry]
        ) {
            self.baseURL = baseURL
            self.playlists = playlists
            self.scenes = scenes
            self.virtuals = virtuals
            self.effects = effects
        }
    }

    public enum GeneratorError: Error, LocalizedError {
        case noVirtuals

        public var errorDescription: String? {
            switch self {
            case .noVirtuals:
                return "No virtuals available to build slots"
            }
        }
    }

    public static func generate(input: Input, oscListenPort: UInt16 = OSCHub.defaultReceivePort) throws -> BridgeConfig {
        guard !input.virtuals.isEmpty else { throw GeneratorError.noVirtuals }

        let slots = buildSlots(from: input.virtuals)
        let scenes = buildScenes(playlists: input.playlists, scenes: input.scenes)
        let playlists = buildPlaylists(playlists: input.playlists)
        let playlistControls = buildPlaylistControls()
        let oneshots = buildDefaultOneshots()
        let params = buildDefaultParams()

        let server = ServerConfig(
            osc_listen: OSCListenConfig(host: "0.0.0.0", port: oscListenPort),
            http: HTTPConfig(
                base_url: input.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                timeout_ms: 1500,
                default_headers: ["Content-Type": "application/json"]
            )
        )

        return BridgeConfig(
            version: 1,
            server: server,
            slots: slots,
            scenes: scenes,
            playlists: playlists,
            playlist_controls: playlistControls,
            oneshots: oneshots,
            params: params
        )
    }

    public static func generateFallback(
        baseURL: String,
        virtualIds: [String],
        oscListenPort: UInt16 = OSCHub.defaultReceivePort
    ) -> BridgeConfig {
        let normalizedIds = virtualIds.isEmpty ? ["virtual-1"] : virtualIds
        let slots = buildSlotsFromVirtualIds(normalizedIds)

        let server = ServerConfig(
            osc_listen: OSCListenConfig(host: "0.0.0.0", port: oscListenPort),
            http: HTTPConfig(
                base_url: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                timeout_ms: 1500,
                default_headers: ["Content-Type": "application/json"]
            )
        )

        return BridgeConfig(
            version: 1,
            server: server,
            slots: slots,
            scenes: [:],
            playlists: [:],
            playlist_controls: buildPlaylistControls(),
            oneshots: buildDefaultOneshots(),
            params: buildDefaultParams()
        )
    }

    private static func buildSlots(from virtuals: [String: LedFXVirtual]) -> [String: SlotConfig] {
        let ordered = virtuals.values.sorted { $0.id < $1.id }
        var slots = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { index, virtual in
            let name = virtual.config?.name ?? virtual.id
            let targets = SlotTargets(virtual_ids: [virtual.id])
            let blackout = BlackoutConfig(scene: "blackout", restore_previous_scene: true)
            return ("\(index)", SlotConfig(name: name, targets: targets, blackout: blackout))
        })

        let allIds = ordered.map { $0.id }
        if !allIds.isEmpty {
            let blackout = BlackoutConfig(scene: "blackout", restore_previous_scene: true)
            slots["all"] = SlotConfig(
                name: "All",
                targets: SlotTargets(virtual_ids: allIds),
                blackout: blackout
            )
        }

        return slots
    }

    private static func buildSlotsFromVirtualIds(_ virtualIds: [String]) -> [String: SlotConfig] {
        var slots = Dictionary(uniqueKeysWithValues: virtualIds.enumerated().map { index, virtualId in
            let name = "Virtual \(index + 1)"
            let targets = SlotTargets(virtual_ids: [virtualId])
            let blackout = BlackoutConfig(scene: "blackout", restore_previous_scene: true)
            return ("\(index)", SlotConfig(name: name, targets: targets, blackout: blackout))
        })

        if !virtualIds.isEmpty {
            let blackout = BlackoutConfig(scene: "blackout", restore_previous_scene: true)
            slots["all"] = SlotConfig(
                name: "All",
                targets: SlotTargets(virtual_ids: virtualIds),
                blackout: blackout
            )
        }

        return slots
    }

    private static func buildScenes(
        playlists: [String: LedFXPlaylist],
        scenes: [String: LedFXScene]
    ) -> [String: SceneConfig] {
        let playlistSceneIds = playlists.values.flatMap { $0.items.map { $0.sceneId } }
        let rawSceneIds = Set(playlistSceneIds.isEmpty ? Array(scenes.keys) : playlistSceneIds)
        let sceneIds = rawSceneIds.isEmpty ? ["blackout"] : Array(rawSceneIds).sorted()

        var result: [String: SceneConfig] = [:]
        for sceneId in sceneIds {
            result[sceneId] = SceneConfig(
                id: sceneId,
                on_activate: SceneAction(request: activateSceneRequest()),
                on_deactivate: SceneDeactivateAction(enabled: true, request: deactivateSceneRequest())
            )
        }

        let globalBlackoutActivate = RequestTemplate(
            method: "PUT",
            path: "/api/effects",
            body: AnyCodable([
                "action": "apply_global",
                "brightness": 0.0,
                "background_brightness": 0.0
            ])
        )

        let globalBlackoutDeactivate = RequestTemplate(
            method: "PUT",
            path: "/api/effects",
            body: AnyCodable([
                "action": "apply_global",
                "brightness": 1.0,
                "background_brightness": 1.0
            ])
        )

        result["blackout"] = SceneConfig(
            id: "blackout",
            on_activate: SceneAction(request: globalBlackoutActivate),
            on_deactivate: SceneDeactivateAction(enabled: true, request: globalBlackoutDeactivate)
        )

        return result
    }

    private static func buildPlaylists(playlists: [String: LedFXPlaylist]) -> [String: PlaylistConfig] {
        let ordered = playlists.values.sorted { $0.id < $1.id }
        return Dictionary(uniqueKeysWithValues: ordered.map { playlist in
            let request = playlistStartRequest()
            return (playlist.id, PlaylistConfig(id: playlist.id, on_start: request))
        })
    }

    private static func playlistStartRequest() -> RequestTemplate {
        let body: [String: Any] = [
            "id": "${playlist.id}",
            "action": "start"
        ]
        return RequestTemplate(method: "PUT", path: "/api/playlists", body: AnyCodable(body))
    }

    private static func buildPlaylistControls() -> [String: PlaylistControlConfig] {
        let actions = ["stop", "pause", "resume", "next", "prev"]
        return Dictionary(uniqueKeysWithValues: actions.map { action in
            let body: [String: Any] = [
                "action": action
            ]
            let request = RequestTemplate(method: "PUT", path: "/api/playlists", body: AnyCodable(body))
            return (action, PlaylistControlConfig(action: action, request: request))
        })
    }

    private static func activateSceneRequest(idOverride: String? = nil) -> RequestTemplate {
        let body: [String: Any] = [
            "id": idOverride ?? "${scene.id}",
            "action": "activate"
        ]
        return RequestTemplate(method: "PUT", path: "/api/scenes", body: AnyCodable(body))
    }

    private static func deactivateSceneRequest(idOverride: String? = nil) -> RequestTemplate {
        let body: [String: Any] = [
            "id": idOverride ?? "${scene.id}",
            "action": "deactivate"
        ]
        return RequestTemplate(method: "PUT", path: "/api/scenes", body: AnyCodable(body))
    }

    private static func buildDefaultOneshots() -> [String: OneshotConfig] {
        let whiteflash = RequestTemplate(
            method: "PUT",
            path: "/api/virtuals_tools/${slot.targets.virtual_ids[0]}",
            body: AnyCodable([
                "tool": "oneshot",
                "color": "#FFFFFF",
                "ramp": 0,
                "hold": 40,
                "fade": 0,
                "brightness": 1.0
            ])
        )

        let redhit = RequestTemplate(
            method: "PUT",
            path: "/api/virtuals_tools/${slot.targets.virtual_ids[0]}",
            body: AnyCodable([
                "tool": "oneshot",
                "color": "#FF0000",
                "ramp": 0,
                "hold": 60,
                "fade": 100,
                "brightness": 0.8
            ])
        )

        return [
            "whiteflash": OneshotConfig(request: whiteflash),
            "redhit": OneshotConfig(request: redhit)
        ]
    }

    private static func buildDefaultParams() -> [String: ParamConfig] {
        let input = ParamInput(accepted: ["midi_0_127", "normalized_0_1"], default_mode: "midi_0_127")

        let brightnessScale = ParamScale(
            type: "linear",
            in_min: 0,
            in_max: 127,
            out_min: 0.0,
            out_max: 1.0
        )

        let brightnessRequest = ParamRequest(
            method: "PUT",
            path: "/api/virtuals/${slot.targets.virtual_ids[0]}",
            body_template: AnyCodable([
                "config": ["brightness": 0.5]
            ]),
            patch_ops: [
                PatchOp(op: "set", pointer: "/config/brightness", value: AnyCodable("${param.scaled}"))
            ]
        )

        let globalBrightnessRequest = ParamRequest(
            method: "PUT",
            path: "/api/effects",
            body_template: AnyCodable([
                "action": "apply_global",
                "brightness": 0.5,
                "background_brightness": 0.5
            ]),
            patch_ops: [
                PatchOp(op: "set", pointer: "/brightness", value: AnyCodable("${param.scaled}")),
                PatchOp(op: "set", pointer: "/background_brightness", value: AnyCodable("${param.scaled}"))
            ]
        )

        return [
            "brightness": ParamConfig(input: input, scale: brightnessScale, request: brightnessRequest),
            "global_brightness": ParamConfig(input: input, scale: brightnessScale, request: globalBrightnessRequest)
        ]
    }
}
