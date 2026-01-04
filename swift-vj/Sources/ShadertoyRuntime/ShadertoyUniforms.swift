// ShadertoyUniforms.swift - Shadertoy-compatible uniform buffer
// Matches Shadertoy environment: https://www.shadertoy.com/howto

import Foundation
import simd

// MARK: - Shadertoy Uniforms

/// Uniform buffer layout matching Shadertoy environment
/// All uniforms are always bound every frame for stable ABI
/// Reference: https://www.shadertoy.com/view/Ml2XW1
public struct ShadertoyUniforms {
    // MARK: - Primary Uniforms

    /// Viewport resolution in pixels (width, height, 1.0 for pixel aspect)
    public var iResolution: SIMD3<Float> = SIMD3(1280, 720, 1.0)

    /// Shader playback time in seconds
    public var iTime: Float = 0.0

    /// Time since last frame in seconds
    public var iTimeDelta: Float = 0.016667  // ~60fps default

    /// Frame count since shader start
    public var iFrame: Int32 = 0

    /// Frame rate (1.0 / iTimeDelta, smoothed)
    public var iFrameRate: Float = 60.0

    /// Mouse input: xy = current position when down, zw = click position
    /// Reference: https://www.shadertoy.com/view/XlyBzt
    public var iMouse: SIMD4<Float> = SIMD4(0, 0, 0, 0)

    /// Current date: (year, month, day, seconds since midnight)
    public var iDate: SIMD4<Float> = SIMD4(2024, 1, 1, 0)

    /// Audio sample rate (typically 44100.0)
    public var iSampleRate: Float = 44100.0

    // MARK: - Channel Uniforms

    /// Time offset for each channel (for video/audio sync)
    public var iChannelTime: (Float, Float, Float, Float) = (0, 0, 0, 0)

    /// Resolution of each channel texture (width, height, depth/1.0)
    public var iChannelResolution: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) = (
        SIMD3(1, 1, 1),
        SIMD3(1, 1, 1),
        SIMD3(1, 1, 1),
        SIMD3(1, 1, 1)
    )

    // MARK: - Extended Audio Uniforms (VJ-specific)

    /// Audio frequency bands (bass, lowMid, mid, highs)
    public var iAudioBands: SIMD4<Float> = SIMD4(0, 0, 0, 0)

    /// Audio energy (fast, slow, beat, level)
    public var iAudioEnergy: SIMD4<Float> = SIMD4(0, 0, 0, 0)

    /// Kick envelope and pulse (env, pulse, bpm, confidence)
    public var iKick: SIMD4<Float> = SIMD4(0, 0, 120, 0)

    // MARK: - Padding for Metal alignment

    /// Padding to ensure 16-byte alignment
    private var _padding: SIMD2<Float> = SIMD2(0, 0)

    // MARK: - Initialization

    public init() {}

    // MARK: - Update Methods

    /// Update time-related uniforms for a new frame
    public mutating func updateTime(time: Float, deltaTime: Float, frame: Int32) {
        iTime = time
        iTimeDelta = deltaTime
        iFrame = frame
        iFrameRate = deltaTime > 0 ? 1.0 / deltaTime : 60.0
    }

    /// Update date uniform
    public mutating func updateDate() {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)

        let year = Float(components.year ?? 2024)
        let month = Float(components.month ?? 1)
        let day = Float(components.day ?? 1)

        let hour = Float(components.hour ?? 0)
        let minute = Float(components.minute ?? 0)
        let second = Float(components.second ?? 0)
        let secondsSinceMidnight = hour * 3600 + minute * 60 + second

        iDate = SIMD4(year, month, day, secondsSinceMidnight)
    }

    /// Update mouse from touch/click position
    /// x, y: current position (0 to resolution)
    /// pressed: whether button is down
    public mutating func updateMouse(x: Float, y: Float, pressed: Bool, clicked: Bool) {
        if pressed {
            iMouse.x = x
            iMouse.y = y
        }
        if clicked {
            iMouse.z = x
            iMouse.w = y
        }
        if !pressed {
            // Negative z/w indicates mouse up
            iMouse.z = -abs(iMouse.z)
            iMouse.w = -abs(iMouse.w)
        }
    }

    /// Update resolution
    public mutating func updateResolution(width: Float, height: Float) {
        iResolution = SIMD3(width, height, 1.0)
    }

    /// Update channel resolution at specified index
    public mutating func updateChannelResolution(index: Int, width: Float, height: Float, depth: Float = 1.0) {
        let res = SIMD3<Float>(width, height, depth)
        switch index {
        case 0: iChannelResolution.0 = res
        case 1: iChannelResolution.1 = res
        case 2: iChannelResolution.2 = res
        case 3: iChannelResolution.3 = res
        default: break
        }
    }

    /// Update audio uniforms from audio analysis state
    public mutating func updateAudio(
        bass: Float, lowMid: Float, mid: Float, highs: Float,
        energyFast: Float, energySlow: Float, beat: Float, level: Float,
        kickEnv: Float, kickPulse: Float, bpm: Float, confidence: Float
    ) {
        iAudioBands = SIMD4(bass, lowMid, mid, highs)
        iAudioEnergy = SIMD4(energyFast, energySlow, beat, level)
        iKick = SIMD4(kickEnv, kickPulse, bpm, confidence)
    }
}

// MARK: - Metal Shader Uniform Layout

/// Metal-compatible uniform buffer layout (matches MSL struct)
/// Designed for stable ABI across all shaders
public struct ShadertoyUniformBuffer {
    // Core Shadertoy uniforms - always present
    public var iResolution: SIMD3<Float>       // 12 bytes
    public var _pad0: Float                     // 4 bytes (alignment)

    public var iTime: Float                     // 4 bytes
    public var iTimeDelta: Float                // 4 bytes
    public var iFrame: Int32                    // 4 bytes
    public var iFrameRate: Float                // 4 bytes

    public var iMouse: SIMD4<Float>             // 16 bytes
    public var iDate: SIMD4<Float>              // 16 bytes

    public var iSampleRate: Float               // 4 bytes
    public var _pad1: SIMD3<Float>              // 12 bytes (alignment)

    // Channel times
    public var iChannelTime0: Float             // 4 bytes
    public var iChannelTime1: Float             // 4 bytes
    public var iChannelTime2: Float             // 4 bytes
    public var iChannelTime3: Float             // 4 bytes

    // Channel resolutions (16 bytes each with padding)
    public var iChannelResolution0: SIMD3<Float>
    public var _pad2: Float
    public var iChannelResolution1: SIMD3<Float>
    public var _pad3: Float
    public var iChannelResolution2: SIMD3<Float>
    public var _pad4: Float
    public var iChannelResolution3: SIMD3<Float>
    public var _pad5: Float

    // Extended audio uniforms (VJ-specific)
    public var iAudioBands: SIMD4<Float>        // 16 bytes
    public var iAudioEnergy: SIMD4<Float>       // 16 bytes
    public var iKick: SIMD4<Float>              // 16 bytes

    // Total: 256 bytes (good cache alignment)

    /// Initialize from ShadertoyUniforms
    public init(from uniforms: ShadertoyUniforms) {
        iResolution = uniforms.iResolution
        _pad0 = 0

        iTime = uniforms.iTime
        iTimeDelta = uniforms.iTimeDelta
        iFrame = uniforms.iFrame
        iFrameRate = uniforms.iFrameRate

        iMouse = uniforms.iMouse
        iDate = uniforms.iDate

        iSampleRate = uniforms.iSampleRate
        _pad1 = SIMD3(0, 0, 0)

        iChannelTime0 = uniforms.iChannelTime.0
        iChannelTime1 = uniforms.iChannelTime.1
        iChannelTime2 = uniforms.iChannelTime.2
        iChannelTime3 = uniforms.iChannelTime.3

        iChannelResolution0 = uniforms.iChannelResolution.0
        _pad2 = 0
        iChannelResolution1 = uniforms.iChannelResolution.1
        _pad3 = 0
        iChannelResolution2 = uniforms.iChannelResolution.2
        _pad4 = 0
        iChannelResolution3 = uniforms.iChannelResolution.3
        _pad5 = 0

        iAudioBands = uniforms.iAudioBands
        iAudioEnergy = uniforms.iAudioEnergy
        iKick = uniforms.iKick
    }

    /// Initialize with defaults
    public init() {
        self.init(from: ShadertoyUniforms())
    }
}

// MARK: - Size Verification

extension ShadertoyUniformBuffer {
    /// Expected size for buffer allocation
    public static var expectedSize: Int { 256 }

    /// Verify struct layout matches expected size
    public static func verifyLayout() -> Bool {
        let actualSize = MemoryLayout<ShadertoyUniformBuffer>.stride
        return actualSize == expectedSize
    }
}
