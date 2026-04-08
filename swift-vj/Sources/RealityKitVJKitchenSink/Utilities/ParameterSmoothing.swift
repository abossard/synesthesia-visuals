// ParameterSmoothing.swift
// RealityKitVJKitchenSink
//
// Time-based smoothing for UI-driven parameters.
// Provides smooth transitions when parameters change.

import simd
import Foundation

// MARK: - Smoothed Value

/// A value that smoothly interpolates toward a target
struct SmoothedValue {
    private var current: Float
    private var velocity: Float = 0
    var target: Float
    var smoothing: Float  // Lower = faster (0.01 = snappy, 0.1 = smooth)
    var damping: Float    // 0.5-1.0 typical

    init(initial: Float, smoothing: Float = 0.05, damping: Float = 0.8) {
        self.current = initial
        self.target = initial
        self.smoothing = smoothing
        self.damping = damping
    }

    /// Update the smoothed value
    mutating func update(deltaTime: Float) {
        // Critically damped spring
        let diff = target - current
        let springForce = diff / max(smoothing, 0.001)

        velocity = velocity * damping + springForce * deltaTime
        current += velocity

        // Snap when close enough
        if abs(diff) < 0.0001 && abs(velocity) < 0.0001 {
            current = target
            velocity = 0
        }
    }

    /// Get the current smoothed value
    var value: Float {
        return current
    }

    /// Immediately set the value (no smoothing)
    mutating func setImmediate(_ value: Float) {
        current = value
        target = value
        velocity = 0
    }
}

// MARK: - Smoothed SIMD3

/// A SIMD3 value that smoothly interpolates toward a target
struct SmoothedSIMD3 {
    private var current: SIMD3<Float>
    private var velocity: SIMD3<Float> = .zero
    var target: SIMD3<Float>
    var smoothing: Float
    var damping: Float

    init(initial: SIMD3<Float>, smoothing: Float = 0.05, damping: Float = 0.8) {
        self.current = initial
        self.target = initial
        self.smoothing = smoothing
        self.damping = damping
    }

    mutating func update(deltaTime: Float) {
        let diff = target - current
        let springForce = diff / max(smoothing, 0.001)

        velocity = velocity * damping + springForce * deltaTime
        current += velocity

        if length(diff) < 0.0001 && length(velocity) < 0.0001 {
            current = target
            velocity = .zero
        }
    }

    var value: SIMD3<Float> {
        return current
    }

    mutating func setImmediate(_ value: SIMD3<Float>) {
        current = value
        target = value
        velocity = .zero
    }
}

// MARK: - Exponential Smoothing

/// Simple exponential moving average (EMA)
struct ExponentialSmoothing {
    private var value: Float
    let alpha: Float  // 0-1, higher = faster response

    init(initial: Float, alpha: Float = 0.1) {
        self.value = initial
        self.alpha = alpha
    }

    mutating func update(_ newValue: Float) -> Float {
        value = alpha * newValue + (1 - alpha) * value
        return value
    }

    var current: Float { value }
}

// MARK: - Velocity Tracker

/// Tracks velocity from position changes
struct VelocityTracker {
    private var lastPosition: Float
    private var velocity: Float = 0
    private let smoothing: Float

    init(initial: Float, smoothing: Float = 0.1) {
        self.lastPosition = initial
        self.smoothing = smoothing
    }

    mutating func update(_ newPosition: Float, deltaTime: Float) -> Float {
        let rawVelocity = (newPosition - lastPosition) / max(deltaTime, 0.0001)
        velocity = velocity * (1 - smoothing) + rawVelocity * smoothing
        lastPosition = newPosition
        return velocity
    }

    var currentVelocity: Float { velocity }
}

// MARK: - Envelope

/// Attack-sustain-release envelope generator
struct Envelope {
    enum State {
        case idle
        case attack
        case sustain
        case release
    }

    private(set) var state: State = .idle
    private var value: Float = 0
    private var time: Float = 0

    let attackTime: Float
    let releaseTime: Float
    let sustainLevel: Float

    init(attackTime: Float = 0.1, releaseTime: Float = 0.3, sustainLevel: Float = 1.0) {
        self.attackTime = attackTime
        self.releaseTime = releaseTime
        self.sustainLevel = sustainLevel
    }

    mutating func trigger() {
        state = .attack
        time = 0
    }

    mutating func release() {
        state = .release
        time = 0
    }

    mutating func update(deltaTime: Float) -> Float {
        time += deltaTime

        switch state {
        case .idle:
            value = 0

        case .attack:
            if attackTime > 0 {
                value = min(time / attackTime, 1.0) * sustainLevel
                if time >= attackTime {
                    state = .sustain
                    time = 0
                }
            } else {
                value = sustainLevel
                state = .sustain
                time = 0
            }

        case .sustain:
            value = sustainLevel

        case .release:
            if releaseTime > 0 {
                value = sustainLevel * max(1.0 - time / releaseTime, 0.0)
                if time >= releaseTime {
                    state = .idle
                    time = 0
                }
            } else {
                value = 0
                state = .idle
                time = 0
            }
        }

        return value
    }

    var current: Float { value }
    var isActive: Bool { state != .idle }
}

// MARK: - Pulse Generator

/// Generates periodic pulses
struct PulseGenerator {
    private var phase: Float = 0
    let frequency: Float  // Hz
    let pulseWidth: Float  // 0-1, portion of cycle that's "on"

    init(frequency: Float = 1.0, pulseWidth: Float = 0.5) {
        self.frequency = frequency
        self.pulseWidth = pulseWidth
    }

    mutating func update(deltaTime: Float) -> Float {
        phase += deltaTime * frequency
        phase = phase.truncatingRemainder(dividingBy: 1.0)
        return phase < pulseWidth ? 1.0 : 0.0
    }

    var value: Float {
        return phase < pulseWidth ? 1.0 : 0.0
    }
}

// MARK: - LFO (Low Frequency Oscillator)

/// Low-frequency oscillator for modulation
struct LFO {
    enum Waveform {
        case sine
        case triangle
        case sawtooth
        case square
        case random
    }

    private var phase: Float = 0
    private var lastRandom: Float = 0
    private var nextRandom: Float = 0

    let frequency: Float
    let waveform: Waveform
    var amplitude: Float
    var offset: Float

    init(frequency: Float = 1.0, waveform: Waveform = .sine, amplitude: Float = 1.0, offset: Float = 0.0) {
        self.frequency = frequency
        self.waveform = waveform
        self.amplitude = amplitude
        self.offset = offset

        lastRandom = Float.random(in: -1...1)
        nextRandom = Float.random(in: -1...1)
    }

    mutating func update(deltaTime: Float) -> Float {
        let oldPhase = phase
        phase += deltaTime * frequency
        phase = phase.truncatingRemainder(dividingBy: 1.0)

        // Check for cycle wrap
        if phase < oldPhase {
            lastRandom = nextRandom
            nextRandom = Float.random(in: -1...1)
        }

        let rawValue: Float

        switch waveform {
        case .sine:
            rawValue = sin(phase * 2 * .pi)

        case .triangle:
            rawValue = phase < 0.5
                ? 4.0 * phase - 1.0
                : 3.0 - 4.0 * phase

        case .sawtooth:
            rawValue = 2.0 * phase - 1.0

        case .square:
            rawValue = phase < 0.5 ? 1.0 : -1.0

        case .random:
            rawValue = Float.lerp(lastRandom, nextRandom, Float.smoothstep(0, 1, phase))
        }

        return rawValue * amplitude + offset
    }

    var value: Float {
        switch waveform {
        case .sine:
            return sin(phase * 2 * .pi) * amplitude + offset
        case .triangle:
            let raw = phase < 0.5 ? 4.0 * phase - 1.0 : 3.0 - 4.0 * phase
            return raw * amplitude + offset
        case .sawtooth:
            return (2.0 * phase - 1.0) * amplitude + offset
        case .square:
            return (phase < 0.5 ? 1.0 : -1.0) * amplitude + offset
        case .random:
            return Float.lerp(lastRandom, nextRandom, Float.smoothstep(0, 1, phase)) * amplitude + offset
        }
    }
}
