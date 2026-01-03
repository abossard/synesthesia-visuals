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

    // Audio-reactive speed (Magic-style ramping)
    let speed: Float        // 0.02 - 1.20

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
        speed: 0.02,
        timestamp: Date()
    )
}

// MARK: - Lyrics Display State

/// Single lyric line with timestamp
struct LyricLine: Sendable, Equatable, Identifiable {
    let id: Int
    let timeSec: Float
    let text: String

    init(id: Int = 0, timeSec: Float, text: String) {
        self.id = id
        self.timeSec = timeSec
        self.text = text
    }
}

/// Lyrics display state for 3-line karaoke view
struct LyricsDisplayState: Sendable, Equatable {
    let lines: [LyricLine]
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

/// Shader rating for filtering (from VJUniverse)
enum ShaderRating: Int, Sendable, Codable {
    case best = 1
    case good = 2
    case ok = 3
    case skip = 4
    case broken = 5

    var displayName: String {
        switch self {
        case .best: return "Best"
        case .good: return "Good"
        case .ok: return "OK"
        case .skip: return "Skip"
        case .broken: return "Broken"
        }
    }
}

/// Shader info for loaded shader
struct ShaderInfo: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let path: URL
    let rating: ShaderRating

    init(name: String, path: URL, rating: ShaderRating = .good) {
        self.id = name
        self.name = name
        self.path = path
        self.rating = rating
    }
}

/// Shader display state
struct ShaderDisplayState: Sendable, Equatable {
    let current: ShaderInfo?
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
struct ShaderUniforms {
    var time: Float = 0
    var resolution: SIMD2<Float> = SIMD2(1280, 720)
    var mouse: SIMD2<Float> = SIMD2(0.5, 0.5)
    var speed: Float = 0.02

    // Audio bands (0.0 - 1.0)
    var bass: Float = 0
    var lowMid: Float = 0
    var mid: Float = 0
    var highs: Float = 0
    var level: Float = 0

    // Beat/kick
    var kickEnv: Float = 0
    var kickPulse: Float = 0
    var beat: Float = 0
    var energyFast: Float = 0
    var energySlow: Float = 0

    /// Update from AudioState
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
        speed = audio.speed
    }
}

// MARK: - Tile Configuration

/// Tile configuration for Syphon output
struct TileConfig: Sendable {
    let name: String
    let syphonName: String
    let width: Int
    let height: Int

    static let shader = TileConfig(name: "Shader", syphonName: "SwiftVJ/Shader", width: 1280, height: 720)
    static let mask = TileConfig(name: "Mask", syphonName: "SwiftVJ/Mask", width: 1280, height: 720)
    static let lyrics = TileConfig(name: "Lyrics", syphonName: "SwiftVJ/Lyrics", width: 1280, height: 720)
    static let refrain = TileConfig(name: "Refrain", syphonName: "SwiftVJ/Refrain", width: 1280, height: 720)
    static let songInfo = TileConfig(name: "SongInfo", syphonName: "SwiftVJ/SongInfo", width: 1280, height: 720)
    static let image = TileConfig(name: "Image", syphonName: "SwiftVJ/Image", width: 1280, height: 720)
}

// MARK: - Utility Functions

/// Calculate synthetic mouse position (Lissajous curve)
/// Pure function from VJUniverse
func calcSyntheticMouse(
    time: Float,
    energySlow: Float,
    bass: Float,
    mid: Float,
    beatPhase: Float
) -> SIMD2<Float> {
    // Base radius (expands with energy)
    let radius = 0.12 + energySlow * 0.18

    // Figure-8 pattern: x = sin(t), y = sin(2t)
    let x = 0.5 + sin(time) * radius * (1 + bass * 0.3)
    let y = 0.5 + sin(time * 2) * radius * (1 + mid * 0.2)

    // Phase offset on beats
    let phaseOffset = beatPhase * 0.1

    return SIMD2<Float>(
        min(max(x + phaseOffset, 0), 1),
        min(max(y, 0), 1)
    )
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
