// RequestBuilder.swift - Pure functions for building HTTP requests
// Following Grokking Simplicity: pure calculations

import Foundation

public enum RequestBuilder {
    
    public enum BuildError: Error, LocalizedError {
        case unknownScene(String)
        case unknownPlaylist(String)
        case unknownPlaylistControl(String)
        case unknownOneshot(String)
        case unknownParam(String)
        case unknownSlot(String)
        case invalidJSON(String)
        case templateError(String)
        
        public var errorDescription: String? {
            switch self {
            case .unknownScene(let name): return "Unknown scene: \(name)"
            case .unknownPlaylist(let name): return "Unknown playlist: \(name)"
            case .unknownPlaylistControl(let name): return "Unknown playlist control: \(name)"
            case .unknownOneshot(let name): return "Unknown oneshot: \(name)"
            case .unknownParam(let name): return "Unknown param: \(name)"
            case .unknownSlot(let slot): return "Unknown slot: \(slot)"
            case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
            case .templateError(let msg): return "Template error: \(msg)"
            }
        }
    }
    
    // MARK: - Build Requests
    
    /// Build HTTP request plans from a parsed OSC route
    public static func build(
        route: ParsedOSCRoute,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        switch route {
        case .scene(let slot, let sceneName):
            return try buildSceneRequests(slot: slot, sceneName: sceneName, value: value, config: config)

        case .playlist(let slot, let playlistId):
            return try buildPlaylistRequests(slot: slot, playlistId: playlistId, value: value, config: config)

        case .playlistControl(let slot, let action):
            return try buildPlaylistControlRequests(slot: slot, action: action, value: value, config: config)
            
        case .oneshot(let slot, let oneshotName):
            return try buildOneshotRequests(slot: slot, oneshotName: oneshotName, value: value, config: config)
            
        case .blackout(let slot):
            return try buildBlackoutRequests(slot: slot, value: value, config: config)
            
        case .param(let slot, let paramName):
            return try buildParamRequests(slot: slot, paramName: paramName, value: value, config: config)
        }
    }
    
    // MARK: - Scene Requests
    
    private static func buildSceneRequests(
        slot: String,
        sceneName: String,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        guard let slotConfig = config.slots[slot] else {
            throw BuildError.unknownSlot(slot)
        }
        
        guard let sceneConfig = config.scenes[sceneName] else {
            throw BuildError.unknownScene(sceneName)
        }
        
        if value > 0 {
            // Activate
            let context = TemplateEngine.TemplateContext(
                sceneId: sceneConfig.id,
                slotName: slotConfig.name,
                slotVirtualIds: slotConfig.targets.virtual_ids
            )
            return try [buildRequest(template: sceneConfig.on_activate.request, context: context, config: config)]
        } else {
            // Deactivate (only if enabled)
            guard let deactivate = sceneConfig.on_deactivate, deactivate.enabled else {
                return []
            }
            let context = TemplateEngine.TemplateContext(
                sceneId: sceneConfig.id,
                slotName: slotConfig.name,
                slotVirtualIds: slotConfig.targets.virtual_ids
            )
            return try [buildRequest(template: deactivate.request, context: context, config: config)]
        }
    }
    
    // MARK: - Oneshot Requests
    
    private static func buildOneshotRequests(
        slot: String,
        oneshotName: String,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        guard value > 0 else { return [] }  // Only trigger on > 0
        
        guard let slotConfig = config.slots[slot] else {
            throw BuildError.unknownSlot(slot)
        }
        
        guard let oneshotConfig = config.oneshots[oneshotName] else {
            throw BuildError.unknownOneshot(oneshotName)
        }

        let targetIds = slotConfig.targets.virtual_ids
        if targetIds.isEmpty {
            let context = TemplateEngine.TemplateContext(
                slotName: slotConfig.name,
                slotVirtualIds: slotConfig.targets.virtual_ids
            )
            return try [buildRequest(template: oneshotConfig.request, context: context, config: config)]
        }

        return try targetIds.map { targetId in
            let context = TemplateEngine.TemplateContext(
                slotName: slotConfig.name,
                slotVirtualIds: [targetId]
            )
            return try buildRequest(template: oneshotConfig.request, context: context, config: config)
        }
    }

    // MARK: - Playlist Requests

    private static func buildPlaylistRequests(
        slot: String,
        playlistId: String,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        guard value > 0 else { return [] } // Only trigger on > 0

        guard let slotConfig = config.slots[slot] else {
            throw BuildError.unknownSlot(slot)
        }

        guard let playlistConfig = config.playlists[playlistId] else {
            throw BuildError.unknownPlaylist(playlistId)
        }

        let context = TemplateEngine.TemplateContext(
            playlistId: playlistConfig.id,
            slotName: slotConfig.name,
            slotVirtualIds: slotConfig.targets.virtual_ids
        )

        return try [buildRequest(template: playlistConfig.on_start, context: context, config: config)]
    }

    private static func buildPlaylistControlRequests(
        slot: String,
        action: String,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        guard value > 0 else { return [] } // Only trigger on > 0

        guard let slotConfig = config.slots[slot] else {
            throw BuildError.unknownSlot(slot)
        }

        guard let controlConfig = config.playlist_controls[action] else {
            throw BuildError.unknownPlaylistControl(action)
        }

        let context = TemplateEngine.TemplateContext(
            playlistAction: controlConfig.action,
            slotName: slotConfig.name,
            slotVirtualIds: slotConfig.targets.virtual_ids
        )

        return try [buildRequest(template: controlConfig.request, context: context, config: config)]
    }
    
    // MARK: - Blackout Requests
    
    private static func buildBlackoutRequests(
        slot: String,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        guard let slotConfig = config.slots[slot] else {
            throw BuildError.unknownSlot(slot)
        }
        
        guard let blackoutConfig = slotConfig.blackout else {
            throw BuildError.unknownSlot("\(slot) (no blackout config)")
        }
        
        guard let blackoutScene = config.scenes[blackoutConfig.scene] else {
            throw BuildError.unknownScene(blackoutConfig.scene)
        }
        
        let context = TemplateEngine.TemplateContext(
            sceneId: blackoutScene.id,
            slotName: slotConfig.name,
            slotVirtualIds: slotConfig.targets.virtual_ids
        )
        
        if value > 0 {
            // Activate blackout scene
            return try [buildRequest(template: blackoutScene.on_activate.request, context: context, config: config)]
        } else {
            // Deactivate blackout scene
            guard let deactivate = blackoutScene.on_deactivate, deactivate.enabled else {
                return []
            }
            return try [buildRequest(template: deactivate.request, context: context, config: config)]
        }
    }
    
    // MARK: - Param Requests
    
    private static func buildParamRequests(
        slot: String,
        paramName: String,
        value: Double,
        config: BridgeConfig
    ) throws -> [HTTPRequestPlan] {
        guard let slotConfig = config.slots[slot] else {
            throw BuildError.unknownSlot(slot)
        }
        
        guard let paramConfig = config.params[paramName] else {
            throw BuildError.unknownParam(paramName)
        }
        
        // Scale the value
        let (scaled, mode) = ParameterScaling.scale(value, config: paramConfig.scale, inputConfig: paramConfig.input)
        
        let targetIds = slotConfig.targets.virtual_ids
        let usesSlotTargets = paramConfig.request.path.contains("${slot.targets.virtual_ids")
        if targetIds.isEmpty || !usesSlotTargets {
            let context = TemplateEngine.TemplateContext(
                slotName: slotConfig.name,
                slotVirtualIds: slotConfig.targets.virtual_ids,
                paramRaw: value,
                paramScaled: scaled,
                paramMode: mode
            )
            return try [buildParamRequest(paramConfig: paramConfig, context: context, config: config)]
        }

        return try targetIds.map { targetId in
            let context = TemplateEngine.TemplateContext(
                slotName: slotConfig.name,
                slotVirtualIds: [targetId],
                paramRaw: value,
                paramScaled: scaled,
                paramMode: mode
            )
            return try buildParamRequest(paramConfig: paramConfig, context: context, config: config)
        }
    }

    private static func buildParamRequest(
        paramConfig: ParamConfig,
        context: TemplateEngine.TemplateContext,
        config: BridgeConfig
    ) throws -> HTTPRequestPlan {
        // Build base body from template
        let baseBody: [String: Any]
        if let template = paramConfig.request.body_template {
            baseBody = template.value as? [String: Any] ?? [:]
        } else {
            baseBody = [:]
        }

        // Apply patches
        var finalBody = baseBody
        if let patches = paramConfig.request.patch_ops {
            finalBody = try JSONPatcher.applyPatches(patches, to: baseBody, context: context)
        }

        // Substitute in final body
        let substituted = TemplateEngine.substituteJSON(finalBody, context: context)
        guard let finalDict = substituted as? [String: Any] else {
            throw BuildError.invalidJSON("Result is not a dictionary")
        }

        // Build request template
        let template = RequestTemplate(
            method: paramConfig.request.method,
            path: paramConfig.request.path,
            body: AnyCodable(finalDict)
        )

        return try buildRequest(template: template, context: context, config: config)
    }
    
    // MARK: - Generic Request Builder
    
    private static func buildRequest(
        template: RequestTemplate,
        context: TemplateEngine.TemplateContext,
        config: BridgeConfig
    ) throws -> HTTPRequestPlan {
        // Build URL
        let interpolatedPath = TemplateEngine.interpolate(template.path, context: context)
        let url = config.server.http.base_url + interpolatedPath
        
        // Build headers
        var headers = config.server.http.default_headers ?? [:]
        if let templateHeaders = template.headers {
            for (key, value) in templateHeaders {
                headers[key] = TemplateEngine.interpolate(value, context: context)
            }
        }
        
        // Build body
        var body: Data? = nil
        if let bodyValue = template.body {
            let substituted = TemplateEngine.substituteJSON(bodyValue.value, context: context)
            let jsonData = try JSONSerialization.data(withJSONObject: substituted, options: [])
            body = jsonData
        }
        
        return HTTPRequestPlan(
            method: template.method,
            url: url,
            headers: headers,
            body: body
        )
    }
}
