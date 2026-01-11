// RenderingTypes.swift - Domain types for VJ rendering system
// Port of VJUniverse rendering concepts to Swift/Metal

import Foundation
import simd
import SwiftVJCore

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

// MARK: - Lyrics Display State

/// Single lyric line for display (simplified from SwiftVJCore.LyricLine)
struct DisplayLyricLine: Sendable, Equatable, Identifiable {
    let id: Int
    let timeSec: Float
    let text: String

    init(id: Int = 0, timeSec: Float, text: String) {
        self.id = id
        self.timeSec = timeSec
        self.text = text
    }
    
    /// Create from SwiftVJCore.LyricLine
    init(from line: SwiftVJCore.LyricLine, id: Int) {
        self.id = id
        self.timeSec = Float(line.timeSec)
        self.text = line.text
    }
}

/// Lyrics display state for 3-line karaoke view
struct LyricsDisplayState: Sendable, Equatable {
    let lines: [DisplayLyricLine]
    let activeIndex: Int
    let textOpacity: Float  // 0-255
    let fadeDelayMs: Float
    let fadeDurationMs: Float
    let lastChangeTime: Date

    var prevLine: String? {
        guard activeIndex > 0, activeIndex - 1 < lines.count else { return nil }
        return lines[activeIndex - 1].text
    }

    var currentLine: String? {
        guard activeIndex >= 0, activeIndex < lines.count else { return nil }
        return lines[activeIndex].text
    }

    var nextLine: String? {
        guard activeIndex + 1 < lines.count else { return nil }
        return lines[activeIndex + 1].text
    }

    static let empty = LyricsDisplayState(
        lines: [],
        activeIndex: -1,
        textOpacity: 0,
        fadeDelayMs: 5000,
        fadeDurationMs: 1000,
        lastChangeTime: Date.distantPast
    )
}

// MARK: - Refrain Display State

/// Refrain/chorus display state (larger text, faster fade)
struct RefrainDisplayState: Sendable, Equatable {
    let text: String
    let opacity: Float  // 0-255
    let active: Bool
    let lastChangeTime: Date

    static let empty = RefrainDisplayState(
        text: "",
        opacity: 0,
        active: false,
        lastChangeTime: Date.distantPast
    )
}

// MARK: - Song Info Display State

/// Song info display state with fade envelope
struct SongInfoDisplayState: Sendable, Equatable {
    let artist: String
    let title: String
    let album: String
    let opacity: Float      // 0-255
    let displayTime: Float  // Seconds since shown
    let active: Bool
    let lastChangeTime: Date

    // Fade envelope timing (from VJUniverse)
    static let fadeInDuration: Float = 0.5
    static let holdDuration: Float = 5.0
    static let fadeOutDuration: Float = 1.0

    static var totalDuration: Float {
        fadeInDuration + holdDuration + fadeOutDuration
    }

    /// Calculate opacity based on display time
    func computeOpacity() -> Float {
        guard active else { return 0 }

        if displayTime < Self.fadeInDuration {
            // Fade in
            return (displayTime / Self.fadeInDuration) * 255
        } else if displayTime < Self.fadeInDuration + Self.holdDuration {
            // Hold
            return 255
        } else if displayTime < Self.totalDuration {
            // Fade out
            let fadeProgress = (displayTime - Self.fadeInDuration - Self.holdDuration) / Self.fadeOutDuration
            return (1.0 - fadeProgress) * 255
        } else {
            return 0
        }
    }

    static let empty = SongInfoDisplayState(
        artist: "",
        title: "",
        album: "",
        opacity: 0,
        displayTime: 0,
        active: false,
        lastChangeTime: Date.distantPast
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

// Use canonical types from ShaderRepository module (via SwiftVJCore re-export)
// typealias ShaderRating = SwiftVJCore.ShaderRating  // Already available via import
// typealias ShaderInfo = SwiftVJCore.ShaderInfo      // Already available via import

/// Shader display state
struct ShaderDisplayState: Sendable, Equatable {
    let current: SwiftVJCore.ShaderInfo?
    let isLoaded: Bool
    let error: String?
    let audioTime: Float  // Audio-reactive accumulated time
    let syntheticMouse: SIMD2<Float>

    static let empty = ShaderDisplayState(
        current: nil,
        isLoaded: false,
        error: nil,
        audioTime: 0,
        syntheticMouse: SIMD2<Float>(0.5, 0.5)
    )
}

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
