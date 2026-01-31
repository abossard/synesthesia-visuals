// SceneGenerator.swift - Generate LedFX scenes for DJ sets
// Following Grokking Simplicity: pure functions for scene generation

import Foundation

/// Generates LedFX scenes based on track analysis and mood
public enum SceneGenerator {
    
    // MARK: - Scene Templates
    
    /// Generate a scene based on track energy and mood
    public static func generateScene(
        name: String,
        virtualIds: [String],
        energy: Double,  // 0.0 - 1.0
        valence: Double, // 0.0 - 1.0 (negative to positive mood)
        bpm: Double? = nil,
        tags: [String] = []
    ) -> LedFXScene {
        // Determine effect type based on energy and valence
        let effectType = selectEffectType(energy: energy, valence: valence)
        let effectConfig = generateEffectConfig(
            type: effectType,
            energy: energy,
            valence: valence,
            bpm: bpm
        )
        
        // Create virtual actions for all devices
        var virtuals: [String: VirtualAction] = [:]
        for virtualId in virtualIds {
            virtuals[virtualId] = VirtualAction(
                action: .activate,
                type: effectType,
                config: effectConfig
            )
        }
        
        return LedFXScene(
            name: name,
            sceneImage: nil,
            sceneTags: tags.isEmpty ? nil : tags.joined(separator: ","),
            virtuals: virtuals,
            active: false
        )
    }
    
    /// Generate a blackout scene
    public static func generateBlackoutScene(
        name: String = "blackout",
        virtualIds: [String]
    ) -> LedFXScene {
        var virtuals: [String: VirtualAction] = [:]
        for virtualId in virtualIds {
            virtuals[virtualId] = VirtualAction(action: .forceblack)
        }
        
        return LedFXScene(
            name: name,
            sceneImage: nil,
            sceneTags: "utility,blackout",
            virtuals: virtuals,
            active: false
        )
    }
    
    /// Generate a simple color scene
    public static func generateColorScene(
        name: String,
        virtualIds: [String],
        color: String,
        brightness: Double = 1.0
    ) -> LedFXScene {
        let config = EffectConfig([
            "color": .string(color),
            "brightness": .double(brightness)
        ])
        
        var virtuals: [String: VirtualAction] = [:]
        for virtualId in virtualIds {
            virtuals[virtualId] = VirtualAction(
                action: .activate,
                type: "solid",
                config: config
            )
        }
        
        return LedFXScene(
            name: name,
            sceneImage: nil,
            sceneTags: "color,simple",
            virtuals: virtuals,
            active: false
        )
    }
    
    // MARK: - Effect Selection (Pure Calculation)
    
    private static func selectEffectType(energy: Double, valence: Double) -> String {
        // High energy scenes
        if energy > 0.7 {
            if valence > 0.6 {
                return "strobe"  // High energy, positive mood
            } else {
                return "energy"   // High energy, negative mood
            }
        }
        
        // Medium energy scenes
        if energy > 0.4 {
            if valence > 0.5 {
                return "scroll"  // Medium energy, positive
            } else {
                return "gradient"  // Medium energy, neutral/negative
            }
        }
        
        // Low energy scenes
        if valence > 0.6 {
            return "wavelength"  // Low energy, positive (chill)
        } else {
            return "fade"  // Low energy, negative (somber)
        }
    }
    
    private static func generateEffectConfig(
        type: String,
        energy: Double,
        valence: Double,
        bpm: Double?
    ) -> EffectConfig {
        var config: [String: EffectValue] = [:]
        
        // Common parameters
        config["brightness"] = .double(0.7 + (energy * 0.3))  // 0.7-1.0
        
        // Type-specific parameters
        switch type {
        case "strobe":
            let speed = bpm.map { $0 / 60.0 } ?? (2.0 + energy * 8.0)  // Hz
            config["speed"] = .double(speed)
            config["color"] = .string(selectColor(valence: valence))
            
        case "energy":
            config["speed"] = .double(1.0 + energy * 4.0)
            config["color_low"] = .string("#FF0000")
            config["color_mid"] = .string("#FF8800")
            config["color_high"] = .string("#FFFF00")
            
        case "scroll":
            let scrollSpeed = bpm.map { $0 / 120.0 } ?? (0.5 + energy * 1.5)
            config["scroll_speed"] = .double(scrollSpeed)
            config["gradient_repeat"] = .int(Int(2 + energy * 3))
            config["color"] = .string(selectColor(valence: valence))
            
        case "gradient":
            config["gradient_roll"] = .double(0.2 + energy * 0.5)
            config["color_start"] = .string(selectColor(valence: valence - 0.2))
            config["color_end"] = .string(selectColor(valence: valence + 0.2))
            
        case "wavelength":
            config["speed"] = .double(0.3 + energy * 0.4)
            config["color"] = .string(selectColor(valence: valence))
            config["blur"] = .int(5)
            
        case "fade":
            config["speed"] = .double(0.1 + energy * 0.3)
            config["color"] = .string(selectColor(valence: valence))
            
        default:
            break
        }
        
        return EffectConfig(config)
    }
    
    private static func selectColor(valence: Double) -> String {
        // Map valence to color (negative -> red/blue, positive -> yellow/green)
        if valence < 0.3 {
            return "#0000FF"  // Blue (sad)
        } else if valence < 0.5 {
            return "#8800FF"  // Purple (neutral/dark)
        } else if valence < 0.7 {
            return "#00FF88"  // Cyan/Green (positive)
        } else {
            return "#FFFF00"  // Yellow (very positive)
        }
    }
    
    // MARK: - DJ Set Utilities
    
    /// Generate a complete set of scenes for a DJ set
    public static func generateDJSetScenes(
        virtualIds: [String],
        tracks: [(name: String, energy: Double, valence: Double, bpm: Double?)]
    ) -> [String: LedFXScene] {
        var scenes: [String: LedFXScene] = [:]
        
        // Add blackout scene
        scenes["blackout"] = generateBlackoutScene(virtualIds: virtualIds)
        
        // Add scenes for each track
        for (index, track) in tracks.enumerated() {
            let sceneId = "track_\(index + 1)"
            scenes[sceneId] = generateScene(
                name: track.name,
                virtualIds: virtualIds,
                energy: track.energy,
                valence: track.valence,
                bpm: track.bpm,
                tags: ["dj-set", "auto-generated"]
            )
        }
        
        // Add utility scenes
        scenes["warm_white"] = generateColorScene(
            name: "Warm White",
            virtualIds: virtualIds,
            color: "#FFE4B5",
            brightness: 0.8
        )
        
        scenes["cool_white"] = generateColorScene(
            name: "Cool White",
            virtualIds: virtualIds,
            color: "#F0F8FF",
            brightness: 0.8
        )
        
        return scenes
    }
    
    /// Generate preset scenes for common moods
    public static func generatePresetScenes(virtualIds: [String]) -> [String: LedFXScene] {
        var scenes: [String: LedFXScene] = [:]
        
        // Energy levels
        scenes["high_energy"] = generateScene(
            name: "High Energy",
            virtualIds: virtualIds,
            energy: 0.9,
            valence: 0.7,
            tags: ["preset", "energy"]
        )
        
        scenes["medium_energy"] = generateScene(
            name: "Medium Energy",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5,
            tags: ["preset", "energy"]
        )
        
        scenes["low_energy"] = generateScene(
            name: "Low Energy",
            virtualIds: virtualIds,
            energy: 0.2,
            valence: 0.6,
            tags: ["preset", "chill"]
        )
        
        // Mood-based
        scenes["uplifting"] = generateScene(
            name: "Uplifting",
            virtualIds: virtualIds,
            energy: 0.6,
            valence: 0.9,
            tags: ["preset", "mood", "positive"]
        )
        
        scenes["dark"] = generateScene(
            name: "Dark",
            virtualIds: virtualIds,
            energy: 0.7,
            valence: 0.2,
            tags: ["preset", "mood", "dark"]
        )
        
        // Utility
        scenes["blackout"] = generateBlackoutScene(virtualIds: virtualIds)
        
        return scenes
    }
}
