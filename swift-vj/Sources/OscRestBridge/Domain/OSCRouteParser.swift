// OSCRouteParser.swift - Pure functions for parsing OSC routes
// Following Grokking Simplicity: pure calculations

import Foundation

public enum OSCRouteParser {
    
    // MARK: - Route Parsing
    
    /// Parse an OSC path into a structured route
    /// Format: /ledfx/<type>/<name>/<slot>
    /// Returns nil if malformed or unknown type
    public static func parse(_ path: String) -> ParsedOSCRoute? {
        let components = path.split(separator: "/").map(String.init)
        
        // Expected: ["", "ledfx", <type>, <name>, <slot>] (5 components)
        // or ["", "ledfx", "blackout", <slot>] (4 components for blackout)
        
        guard components.count >= 4,
              components[0].isEmpty,  // Leading /
              components[1] == "ledfx" else {
            return nil
        }
        
        let routeType = components[2]
        
        switch routeType {
        case "scene":
            guard components.count == 5 else { return nil }
            let sceneName = components[3]
            let slot = components[4]
            return .scene(slot: slot, sceneName: sceneName)
            
        case "oneshot":
            guard components.count == 5 else { return nil }
            let oneshotName = components[3]
            let slot = components[4]
            return .oneshot(slot: slot, oneshotName: oneshotName)
            
        case "blackout":
            guard components.count == 4 else { return nil }
            let slot = components[3]
            return .blackout(slot: slot)
            
        case "param":
            guard components.count == 5 else { return nil }
            let paramName = components[3]
            let slot = components[4]
            return .param(slot: slot, paramName: paramName)
            
        default:
            return nil
        }
    }
    
    /// Extract the first numeric value from OSC arguments
    public static func extractNumeric(_ values: [Any]) -> Double? {
        for value in values {
            if let int = value as? Int {
                return Double(int)
            } else if let float = value as? Float {
                return Double(float)
            } else if let double = value as? Double {
                return double
            } else if let int32 = value as? Int32 {
                return Double(int32)
            } else if let float32 = value as? Float32 {
                return Double(float32)
            }
        }
        return nil
    }
}
