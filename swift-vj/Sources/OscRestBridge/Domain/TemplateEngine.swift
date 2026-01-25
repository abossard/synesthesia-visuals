// TemplateEngine.swift - Pure functions for string interpolation
// Following Grokking Simplicity: pure calculations

import Foundation

public enum TemplateEngine {
    
    // MARK: - Template Variables
    
    public struct TemplateContext {
        public let sceneId: String?
        public let slotName: String?
        public let slotVirtualIds: [String]?
        public let paramRaw: Double?
        public let paramScaled: Double?
        public let paramMode: String?
        
        public init(
            sceneId: String? = nil,
            slotName: String? = nil,
            slotVirtualIds: [String]? = nil,
            paramRaw: Double? = nil,
            paramScaled: Double? = nil,
            paramMode: String? = nil
        ) {
            self.sceneId = sceneId
            self.slotName = slotName
            self.slotVirtualIds = slotVirtualIds
            self.paramRaw = paramRaw
            self.paramScaled = paramScaled
            self.paramMode = paramMode
        }
    }
    
    // MARK: - String Interpolation
    
    /// Replace template variables in a string
    public static func interpolate(_ template: String, context: TemplateContext) -> String {
        var result = template
        
        // Scene variables
        if let sceneId = context.sceneId {
            result = result.replacingOccurrences(of: "${scene.id}", with: sceneId)
        }
        
        // Slot variables
        if let slotName = context.slotName {
            result = result.replacingOccurrences(of: "${slot.name}", with: slotName)
        }
        if let virtualIds = context.slotVirtualIds, !virtualIds.isEmpty {
            result = result.replacingOccurrences(of: "${slot.targets.virtual_ids[0]}", with: virtualIds[0])
        }
        
        // Param variables (as strings for paths)
        if let paramRaw = context.paramRaw {
            result = result.replacingOccurrences(of: "${param.raw}", with: "\(paramRaw)")
        }
        if let paramScaled = context.paramScaled {
            result = result.replacingOccurrences(of: "${param.scaled}", with: "\(paramScaled)")
        }
        if let paramMode = context.paramMode {
            result = result.replacingOccurrences(of: "${param.mode}", with: paramMode)
        }
        
        return result
    }
    
    // MARK: - JSON Substitution
    
    /// Replace template variables in JSON value (returns JSON-compatible type)
    public static func substituteJSON(_ value: Any, context: TemplateContext) -> Any {
        if let string = value as? String {
            // Check for exact template match -> return numeric
            if string == "${param.raw}", let raw = context.paramRaw {
                return raw
            }
            if string == "${param.scaled}", let scaled = context.paramScaled {
                return scaled
            }
            // Otherwise interpolate as string
            return interpolate(string, context: context)
        } else if let dict = value as? [String: Any] {
            return dict.mapValues { substituteJSON($0, context: context) }
        } else if let array = value as? [Any] {
            return array.map { substituteJSON($0, context: context) }
        } else {
            return value
        }
    }
}
