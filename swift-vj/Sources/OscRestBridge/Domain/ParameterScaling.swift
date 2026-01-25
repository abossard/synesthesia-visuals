// ParameterScaling.swift - Pure functions for parameter scaling
// Following Grokking Simplicity: pure calculations

import Foundation

public enum ParameterScaling {
    
    // MARK: - Input Mode Detection
    
    /// Detect input mode from value range
    public static func detectMode(_ value: Double, accepted: [String], defaultMode: String) -> String {
        // Simple heuristic: if value is > 1.0, assume MIDI
        if accepted.contains("midi_0_127") && value > 1.0 {
            return "midi_0_127"
        }
        if accepted.contains("normalized_0_1") && value <= 1.0 {
            return "normalized_0_1"
        }
        return defaultMode
    }
    
    // MARK: - Scaling
    
    /// Scale a parameter value according to config
    /// Returns (scaledValue, mode)
    public static func scale(
        _ rawValue: Double,
        config: ParamScale,
        inputConfig: ParamInput
    ) -> (scaled: Double, mode: String) {
        let mode = detectMode(rawValue, accepted: inputConfig.accepted, defaultMode: inputConfig.default_mode)
        
        // Normalize to 0..1 based on input mode
        var normalized: Double
        switch mode {
        case "midi_0_127":
            normalized = clamp(rawValue, min: 0, max: 127) / 127.0
        case "normalized_0_1":
            normalized = clamp(rawValue, min: 0, max: 1)
        default:
            normalized = clamp(rawValue, min: 0, max: 1)
        }
        
        // Apply curve
        let curved = applyCurve(normalized, curve: config.curve ?? "linear")
        
        // Map to output range
        let scaled = mapRange(curved, fromMin: 0, fromMax: 1, toMin: config.out_min, toMax: config.out_max)
        
        return (scaled, mode)
    }
    
    // MARK: - Helper Functions
    
    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        if value < min { return min }
        if value > max { return max }
        return value
    }
    
    private static func applyCurve(_ normalized: Double, curve: String) -> Double {
        switch curve {
        case "linear":
            return normalized
        case "square":
            return normalized * normalized
        case "sqrt":
            return sqrt(normalized)
        case "exp":
            // Exponential curve with k=4
            // Formula: (exp(k*x) - 1) / (exp(k) - 1)
            let k = 4.0
            return (exp(k * normalized) - 1) / (exp(k) - 1)
        default:
            return normalized
        }
    }
    
    private static func mapRange(_ value: Double, fromMin: Double, fromMax: Double, toMin: Double, toMax: Double) -> Double {
        let normalized = (value - fromMin) / (fromMax - fromMin)
        return toMin + normalized * (toMax - toMin)
    }
}
