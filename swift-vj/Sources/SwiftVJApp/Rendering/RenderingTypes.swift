// RenderingTypes.swift - Domain types for VJ rendering system
// Port of VJUniverse rendering concepts to Swift/Metal

import Foundation
import simd

// MARK: - Audio State (Immutable Snapshot)

/// Audio analysis state snapshot - immutable, Sendable for thread safety
/// Maps to SynesthesiaAudioOSC.pde smoothed values
struct AudioState: Sendable, Equatable {
    // Band levels (0.0 - 1.0)
    let bass: Float
    let lowMid: Float
    let mid: Float
    let highs: Float
    let level: Float  // Overall

    // Energy envelopes
    let energyFast: Float  // Responsive
    let energySlow: Float  // Sustained

    // Beat/kick
    let kickEnv: Float      // 0-1 envelope
    let kickPulse: Bool     // True on kick hit
    let beatPhase: Float    // 0-1 decaying

    // Tempo sync
    let beat4: Int          // 0-3 beat counter
    let bpmTwitcher: Float  // Sawtooth LFO
    let bpmSin4: Float      // 4-beat sine LFO
    let bpmConfidence: Float

    // Presence (slow-moving structural energy)
    let bassPresence: Float
    let midPresence: Float
    let highPresence: Float

    // Timestamp
    let timestamp: Date

    // Computed
    var isActive: Bool { level > 0.01 }

    /// Default silent state
    static let silent = AudioState(
        bass: 0, lowMid: 0, mid: 0, highs: 0, level: 0,
        energyFast: 0, energySlow: 0,
        kickEnv: 0, kickPulse: false, beatPhase: 0,
        beat4: 0, bpmTwitcher: 0, bpmSin4: 0, bpmConfidence: 0,
        bassPresence: 0, midPresence: 0, highPresence: 0,
        timestamp: Date()
    )
}

// MARK: - Image Display State

/// Image display state with crossfade support
struct ImageDisplayState: Sendable, Equatable {
    let currentImageURL: URL?
    let nextImageURL: URL?
    let crossfadeProgress: Float  // 0.0 - 1.0
    let isFading: Bool
    let coverMode: Bool  // true = cover (fill, crop), false = contain (show all)

    // Folder mode
    let folderImages: [URL]
    let folderIndex: Int
    let beatsPerChange: Int  // 0 = manual

    static let empty = ImageDisplayState(
        currentImageURL: nil,
        nextImageURL: nil,
        crossfadeProgress: 1.0,
        isFading: false,
        coverMode: false,
        folderImages: [],
        folderIndex: 0,
        beatsPerChange: 4
    )
}

// MARK: - Shader Display State

// ShaderDisplayState is now defined in SwiftVJCore/Rendering/DisplayStates.swift
// Use it via: SwiftVJCore.ShaderDisplayState (or just ShaderDisplayState with proper import)

// MARK: - Shader Uniforms

/// Uniform buffer for shader rendering
/// IMPORTANT: Must match Metal uniform block layout (std140)
/// vec2 requires 8-byte alignment, so we need padding after single floats
struct ShaderUniforms {
    var time: Float = 0           // offset 0
    var _pad0: Float = 0          // offset 4 (padding for vec2 alignment)
    var resolution: SIMD2<Float> = SIMD2(1280, 720)  // offset 8
    var mouse: SIMD2<Float> = SIMD2(0.5, 0.5)        // offset 16
    var speed: Float = 0.02       // offset 24
    
    // Audio bands (0.0 - 1.0) - these are consecutive floats, no padding needed
    var bass: Float = 0           // offset 28
    var lowMid: Float = 0         // offset 32
    var mid: Float = 0            // offset 36
    var highs: Float = 0          // offset 40
    var level: Float = 0          // offset 44

    // Beat/kick
    var kickEnv: Float = 0        // offset 48
    var kickPulse: Float = 0      // offset 52
    var beat: Float = 0           // offset 56
    var energyFast: Float = 0     // offset 60
    var energySlow: Float = 0     // offset 64

    // Presence (slow-moving structural energy)
    var bassPresence: Float = 0   // offset 68
    var midPresence: Float = 0    // offset 72
    var highPresence: Float = 0   // offset 76

    // BPM LFOs
    var bpmTwitcher: Float = 0    // offset 80
    var bpmSin4: Float = 0        // offset 84
    var bpmConfidence: Float = 0  // offset 88

    // Audio-reactive time (accumulated, not wall clock)
    var audioTime: Float = 0      // offset 92

    // Extra shader uniforms (match ShaderCompiler wrapper)
    var bin0: Float = 0           // offset 96
    var bin1: Float = 0           // offset 100
    var bin2: Float = 0           // offset 104
    var zoom: Float = 1.0         // offset 108

    /// Update from AudioState (speed and audioTime set separately by tile)
    mutating func update(from audio: AudioState) {
        bass = audio.bass
        lowMid = audio.lowMid
        mid = audio.mid
        highs = audio.highs
        level = audio.level
        kickEnv = audio.kickEnv
        kickPulse = audio.kickPulse ? 1.0 : 0.0
        beat = audio.beatPhase
        energyFast = audio.energyFast
        energySlow = audio.energySlow
        bassPresence = audio.bassPresence
        midPresence = audio.midPresence
        highPresence = audio.highPresence
        bpmTwitcher = audio.bpmTwitcher
        bpmSin4 = audio.bpmSin4
        bpmConfidence = audio.bpmConfidence
        // Note: speed and audioTime are computed by the tile, not copied from AudioState
    }
}

// MARK: - Tile Configuration

/// Tile configuration for Syphon output
struct TileConfig: Sendable {
    let name: String
    let syphonName: String
    let width: Int
    let height: Int

    static let shader = TileConfig(name: "Shader", syphonName: "Shader", width: 1280, height: 720)
    static let mask = TileConfig(name: "Mask", syphonName: "Mask", width: 1280, height: 720)
    static let lyrics = TileConfig(name: "Lyrics", syphonName: "Lyrics", width: 1280, height: 720)
    static let refrain = TileConfig(name: "Refrain", syphonName: "Refrain", width: 1280, height: 720)
    static let songInfo = TileConfig(name: "SongInfo", syphonName: "SongInfo", width: 1280, height: 720)
    static let image = TileConfig(name: "Image", syphonName: "Image", width: 1280, height: 720)
}

// MARK: - Utility Functions

/// Synthetic mouse rotation speed (matches VJUniverse synthMouseSpeed)
private let synthMouseSpeed: Float = 0.25

/// Calculate target mouse position (pure Lissajous curve)
/// This is the "desired" position - actual mouse is smoothed toward this
func calcSyntheticMouseTarget(
    time: Float,
    energySlow: Float
) -> SIMD2<Float> {
    // Base rotation
    let t = time * synthMouseSpeed
    
    // Figure-8 Lissajous curve: x = sin(t), y = sin(2t)
    let fig8X = sin(t)
    let fig8Y = sin(t * 2.0)
    
    // Energy-modulated amplitude (only slow energy, no jittery bass/mid)
    let radius: Float = 0.18 + energySlow * 0.12  // 0.18-0.30 range
    
    // Final position (centered at 0.5)
    let x = 0.5 + fig8X * radius
    let y = 0.5 + fig8Y * radius
    
    return SIMD2<Float>(x, y)
}

/// Smooth mouse position with momentum (eliminates jitter, keeps reactivity)
/// Uses critically damped spring for natural movement
func smoothMouse(
    current: SIMD2<Float>,
    target: SIMD2<Float>,
    velocity: inout SIMD2<Float>,
    deltaTime: Float,
    smoothing: Float,
    energyBoost: Float
) -> SIMD2<Float> {
    // Adaptive smoothing: faster response during high energy
    let adaptiveSmoothing = smoothing - energyBoost * 0.15  // 0.92 → 0.77 at full energy
    let smoothingFactor = pow(adaptiveSmoothing, deltaTime * 60.0)  // Frame-rate independent
    
    // Spring-damper system for natural movement
    let springStrength: Float = 8.0  // How fast to chase target
    let damping: Float = 0.85  // Momentum decay
    
    // Calculate spring force toward target
    let displacement = target - current
    let springForce = displacement * springStrength
    
    // Update velocity with spring force and damping
    velocity = velocity * damping + springForce * deltaTime
    
    // Apply velocity to position
    var newPos = current + velocity * deltaTime
    
    // Also blend toward target for stability
    newPos = newPos * smoothingFactor + target * (1.0 - smoothingFactor)
    
    // Clamp to valid range
    newPos.x = min(max(newPos.x, 0.05), 0.95)
    newPos.y = min(max(newPos.y, 0.05), 0.95)
    
    return newPos
}

/// Legacy function for compatibility
func calcSyntheticMouse(
    time: Float,
    energySlow: Float,
    bass: Float,
    mid: Float,
    beatPhase: Float
) -> SIMD2<Float> {
    return calcSyntheticMouseTarget(time: time, energySlow: energySlow)
}
/// Quadratic ease-in-out for animations
/// Pure function
func easeInOutQuad(_ t: Float) -> Float {
    t < 0.5
        ? 2 * t * t
        : 1 - pow(-2 * t + 2, 2) / 2
}

/// Calculate aspect ratio dimensions for image display
/// Pure function from ImageTile.pde
func calcAspectRatioDimensions(
    imgW: Float, imgH: Float,
    bufW: Float, bufH: Float,
    cover: Bool
) -> (x: Float, y: Float, w: Float, h: Float) {
    let imgAspect = imgW / imgH
    let bufAspect = bufW / bufH

    let drawW: Float
    let drawH: Float

    if cover {
        // Cover: fill container, may crop
        if imgAspect > bufAspect {
            drawH = bufH
            drawW = bufH * imgAspect
        } else {
            drawW = bufW
            drawH = bufW / imgAspect
        }
    } else {
        // Contain: show all, may letterbox
        if imgAspect > bufAspect {
            drawW = bufW
            drawH = bufW / imgAspect
        } else {
            drawH = bufH
            drawW = bufH * imgAspect
        }
    }

    return (
        x: (bufW - drawW) / 2,
        y: (bufH - drawH) / 2,
        w: drawW,
        h: drawH
    )
}

/// Linear interpolation
func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}
