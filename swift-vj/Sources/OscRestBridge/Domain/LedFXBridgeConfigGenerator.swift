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
        case playlistsUnavailable
        case noVirtuals

        public var errorDescription: String? {
            switch self {
            case .playlistsUnavailable:
                return "Playlists are required to generate a config"
            case .noVirtuals:
                return "No virtuals available to build slots"
            }
        }
    }

    public static func generate(input: Input) throws -> BridgeConfig {
        guard !input.playlists.isEmpty else { throw GeneratorError.playlistsUnavailable }
        guard !input.virtuals.isEmpty else { throw GeneratorError.noVirtuals }

        let slots = buildSlots(from: input.virtuals)
        let scenes = buildScenes(playlists: input.playlists, scenes: input.scenes)
        let oneshots = buildDefaultOneshots()
        let params = buildDefaultParams()

        let server = ServerConfig(
            osc_listen: OSCListenConfig(host: "0.0.0.0", port: 9000),
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
            oneshots: oneshots,
            params: params
        )
    }

    private static func buildSlots(from virtuals: [String: LedFXVirtual]) -> [String: SlotConfig] {
        let ordered = virtuals.values.sorted { $0.id < $1.id }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { index, virtual in
            let name = virtual.config?.name ?? virtual.id
            let targets = SlotTargets(virtual_ids: [virtual.id])
            let blackout = BlackoutConfig(scene: "blackout", restore_previous_scene: true)
            return ("\(index)", SlotConfig(name: name, targets: targets, blackout: blackout))
        })
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

        if result["blackout"] == nil {
            result["blackout"] = SceneConfig(
                id: "blackout",
                on_activate: SceneAction(request: activateSceneRequest(idOverride: "blackout")),
                on_deactivate: SceneDeactivateAction(enabled: true, request: deactivateSceneRequest(idOverride: "blackout"))
            )
        }

        return result
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

        return [
            "brightness": ParamConfig(input: input, scale: brightnessScale, request: brightnessRequest)
        ]
    }
}