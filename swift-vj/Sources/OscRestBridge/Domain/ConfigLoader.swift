// ConfigLoader.swift - YAML config loading with strict validation
// Following Grokking Simplicity: pure function for validation

import Foundation
import Yams

public enum ConfigLoader {
    
    public enum LoadError: Error, LocalizedError {
        case fileNotFound(String)
        case yamlParseError(String)
        case validationFailed([ConfigValidationError])
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let path): return "File not found: \(path)"
            case .yamlParseError(let msg): return "YAML parse error: \(msg)"
            case .validationFailed(let errors):
                return "Validation failed:\n" + errors.map { "  \($0.path): \($0.message)" }.joined(separator: "\n")
            }
        }
    }

    public enum ExportError: Error, LocalizedError {
        case yamlEncodeError(String)

        public var errorDescription: String? {
            switch self {
            case .yamlEncodeError(let msg): return "YAML encode error: \(msg)"
            }
        }
    }
    
    // MARK: - Load from File
    
    public static func load(from url: URL) throws -> BridgeConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.fileNotFound(url.path)
        }
        
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }
    
    public static func load(from data: Data) throws -> BridgeConfig {
        let yamlString = String(data: data, encoding: .utf8) ?? ""
        return try load(from: yamlString)
    }
    
    public static func load(from yaml: String) throws -> BridgeConfig {
        let decoder = YAMLDecoder()
        
        do {
            let config = try decoder.decode(BridgeConfig.self, from: yaml)
            
            // Validate
            let errors = validate(config)
            if !errors.isEmpty {
                throw LoadError.validationFailed(errors)
            }
            
            return config
        } catch let error as DecodingError {
            throw LoadError.yamlParseError(formatDecodingError(error))
        } catch let error as LoadError {
            throw error
        } catch {
            throw LoadError.yamlParseError(error.localizedDescription)
        }
    }

    // MARK: - Export

    public static func export(_ config: BridgeConfig) throws -> String {
        let encoder = YAMLEncoder()
        do {
            return try encoder.encode(config)
        } catch {
            throw ExportError.yamlEncodeError(error.localizedDescription)
        }
    }
    
    // MARK: - Validation
    
    public static func validate(_ config: BridgeConfig) -> [ConfigValidationError] {
        var errors: [ConfigValidationError] = []
        
        // Version check
        if config.version != 1 {
            errors.append(ConfigValidationError(path: "version", message: "Must be 1"))
        }
        
        // Server validation
        if config.server.http.base_url.isEmpty {
            errors.append(ConfigValidationError(path: "server.http.base_url", message: "Cannot be empty"))
        }
        if config.server.http.timeout_ms < 0 {
            errors.append(ConfigValidationError(path: "server.http.timeout_ms", message: "Must be >= 0"))
        }
        
        // Slots validation
        if config.slots.isEmpty {
            errors.append(ConfigValidationError(path: "slots", message: "At least one slot required"))
        }
        for (slotId, slot) in config.slots {
            if slot.name.isEmpty {
                errors.append(ConfigValidationError(path: "slots.\(slotId).name", message: "Cannot be empty"))
            }
            if slot.targets.virtual_ids.isEmpty {
                errors.append(ConfigValidationError(path: "slots.\(slotId).targets.virtual_ids", message: "At least one virtual_id required"))
            }
            
            // Blackout scene must exist
            if let blackout = slot.blackout {
                if !config.scenes.keys.contains(blackout.scene) {
                    errors.append(ConfigValidationError(
                        path: "slots.\(slotId).blackout.scene",
                        message: "Scene '\(blackout.scene)' not found"
                    ))
                }
            }
        }
        
        // Scenes validation
        for (sceneName, scene) in config.scenes {
            if scene.id.isEmpty {
                errors.append(ConfigValidationError(path: "scenes.\(sceneName).id", message: "Cannot be empty"))
            }
            errors.append(contentsOf: validateRequestTemplate(scene.on_activate.request, path: "scenes.\(sceneName).on_activate.request"))
            
            if let deactivate = scene.on_deactivate {
                errors.append(contentsOf: validateRequestTemplate(deactivate.request, path: "scenes.\(sceneName).on_deactivate.request"))
            }
        }

        // Playlists validation
        for (playlistName, playlist) in config.playlists {
            if playlist.id.isEmpty {
                errors.append(ConfigValidationError(path: "playlists.\(playlistName).id", message: "Cannot be empty"))
            }
            errors.append(contentsOf: validateRequestTemplate(playlist.on_start, path: "playlists.\(playlistName).on_start"))
        }

        // Playlist controls validation
        for (controlName, control) in config.playlist_controls {
            if control.action.isEmpty {
                errors.append(ConfigValidationError(path: "playlist_controls.\(controlName).action", message: "Cannot be empty"))
            }
            errors.append(contentsOf: validateRequestTemplate(control.request, path: "playlist_controls.\(controlName).request"))
        }
        
        // Oneshots validation
        for (oneshotName, oneshot) in config.oneshots {
            errors.append(contentsOf: validateRequestTemplate(oneshot.request, path: "oneshots.\(oneshotName).request"))
        }
        
        // Params validation
        for (paramName, param) in config.params {
            // Input validation
            if param.input.accepted.isEmpty {
                errors.append(ConfigValidationError(path: "params.\(paramName).input.accepted", message: "At least one mode required"))
            }
            if !param.input.accepted.contains(param.input.default_mode) {
                errors.append(ConfigValidationError(
                    path: "params.\(paramName).input.default_mode",
                    message: "Must be one of: \(param.input.accepted.joined(separator: ", "))"
                ))
            }
            
            // Scale validation
            let validTypes = ["linear", "curve"]
            if !validTypes.contains(param.scale.type) {
                errors.append(ConfigValidationError(
                    path: "params.\(paramName).scale.type",
                    message: "Must be one of: \(validTypes.joined(separator: ", "))"
                ))
            }
            
            if param.scale.type == "curve" {
                let validCurves = ["linear", "square", "sqrt", "exp"]
                if let curve = param.scale.curve {
                    if !validCurves.contains(curve) {
                        errors.append(ConfigValidationError(
                            path: "params.\(paramName).scale.curve",
                            message: "Must be one of: \(validCurves.joined(separator: ", "))"
                        ))
                    }
                } else {
                    errors.append(ConfigValidationError(
                        path: "params.\(paramName).scale.curve",
                        message: "Required when type is 'curve'"
                    ))
                }
            }
            
            // Patch ops validation
            if let patches = param.request.patch_ops {
                for (i, patch) in patches.enumerated() {
                    let validOps = ["set", "merge", "delete"]
                    if !validOps.contains(patch.op) {
                        errors.append(ConfigValidationError(
                            path: "params.\(paramName).request.patch_ops[\(i)].op",
                            message: "Must be one of: \(validOps.joined(separator: ", "))"
                        ))
                    }
                    if !patch.pointer.hasPrefix("/") {
                        errors.append(ConfigValidationError(
                            path: "params.\(paramName).request.patch_ops[\(i)].pointer",
                            message: "Must be a valid JSON Pointer (start with /)"
                        ))
                    }
                }
            }
        }
        
        return errors
    }
    
    private static func validateRequestTemplate(_ template: RequestTemplate, path: String) -> [ConfigValidationError] {
        var errors: [ConfigValidationError] = []
        
        let validMethods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
        if !validMethods.contains(template.method) {
            errors.append(ConfigValidationError(
                path: "\(path).method",
                message: "Must be one of: \(validMethods.joined(separator: ", "))"
            ))
        }
        
        if template.path.isEmpty {
            errors.append(ConfigValidationError(path: "\(path).path", message: "Cannot be empty"))
        }
        
        return errors
    }
    
    // MARK: - Error Formatting
    
    private static func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Type mismatch (expected \(type)) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Value not found (expected \(type)) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        @unknown default:
            return error.localizedDescription
        }
    }
    
    // MARK: - Summary Generation
    
    public static func summary(from config: BridgeConfig) -> ConfigSummary {
        ConfigSummary(
            baseUrl: config.server.http.base_url,
            oscPort: config.server.osc_listen.port,
            slotCount: config.slots.count,
            sceneCount: config.scenes.count,
            oneshotCount: config.oneshots.count,
            paramCount: config.params.count
        )
    }
}
