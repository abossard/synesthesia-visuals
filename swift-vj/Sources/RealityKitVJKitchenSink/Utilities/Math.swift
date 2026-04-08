// Math.swift
// RealityKitVJKitchenSink
//
// Mathematical utility functions for animation and geometry.

import simd
import Foundation

// MARK: - Float Extensions

extension Float {
    /// Linear interpolation
    static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }

    /// Smooth step (cubic Hermite interpolation)
    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    /// Smoother step (quintic interpolation)
    static func smootherstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    /// Remap value from one range to another
    static func remap(_ value: Float, _ inMin: Float, _ inMax: Float, _ outMin: Float, _ outMax: Float) -> Float {
        let t = (value - inMin) / (inMax - inMin)
        return outMin + t * (outMax - outMin)
    }

    /// Fractional part
    var fract: Float {
        return self - floor(self)
    }
}

// MARK: - SIMD Extensions

extension SIMD3 where Scalar == Float {
    /// Linear interpolation between two vectors
    static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }

    /// Create from HSV color values (h, s, v in 0-1 range)
    static func fromHSV(h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let c = v * s
        let x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0))
        let m = v - c

        var rgb: SIMD3<Float>

        if h < 1.0/6.0 {
            rgb = SIMD3<Float>(c, x, 0)
        } else if h < 2.0/6.0 {
            rgb = SIMD3<Float>(x, c, 0)
        } else if h < 3.0/6.0 {
            rgb = SIMD3<Float>(0, c, x)
        } else if h < 4.0/6.0 {
            rgb = SIMD3<Float>(0, x, c)
        } else if h < 5.0/6.0 {
            rgb = SIMD3<Float>(x, 0, c)
        } else {
            rgb = SIMD3<Float>(c, 0, x)
        }

        return rgb + SIMD3<Float>(repeating: m)
    }
}

// MARK: - simd_quatf Extensions

extension simd_quatf {
    /// Create rotation from one vector to another
    init(from: SIMD3<Float>, to: SIMD3<Float>) {
        let fromNorm = normalize(from)
        let toNorm = normalize(to)

        let d = dot(fromNorm, toNorm)

        if d >= 0.999999 {
            // Vectors are parallel
            self = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        } else if d <= -0.999999 {
            // Vectors are anti-parallel
            var axis = cross(SIMD3<Float>(1, 0, 0), fromNorm)
            if simd.length(axis) < 0.001 {
                axis = cross(SIMD3<Float>(0, 1, 0), fromNorm)
            }
            axis = normalize(axis)
            self = simd_quatf(angle: .pi, axis: axis)
        } else {
            let axis = normalize(cross(fromNorm, toNorm))
            let angle = acos(d)
            self = simd_quatf(angle: angle, axis: axis)
        }
    }

    /// Spherical linear interpolation
    static func slerp(_ q1: simd_quatf, _ q2: simd_quatf, _ t: Float) -> simd_quatf {
        return simd_slerp(q1, q2, t)
    }
}

// MARK: - Easing Functions

enum Easing {
    /// Quadratic ease in
    static func easeIn(_ t: Float) -> Float {
        return t * t
    }

    /// Quadratic ease out
    static func easeOut(_ t: Float) -> Float {
        return 1.0 - (1.0 - t) * (1.0 - t)
    }

    /// Quadratic ease in-out
    static func easeInOut(_ t: Float) -> Float {
        return t < 0.5
            ? 2.0 * t * t
            : 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
    }

    /// Elastic ease out (for bouncy animations)
    static func elasticOut(_ t: Float) -> Float {
        let c4 = (2.0 * Float.pi) / 3.0
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return pow(2.0, -10.0 * t) * sin((t * 10.0 - 0.75) * c4) + 1.0
    }

    /// Bounce ease out
    static func bounceOut(_ t: Float) -> Float {
        let n1: Float = 7.5625
        let d1: Float = 2.75
        var t = t

        if t < 1.0 / d1 {
            return n1 * t * t
        } else if t < 2.0 / d1 {
            t -= 1.5 / d1
            return n1 * t * t + 0.75
        } else if t < 2.5 / d1 {
            t -= 2.25 / d1
            return n1 * t * t + 0.9375
        } else {
            t -= 2.625 / d1
            return n1 * t * t + 0.984375
        }
    }
}

// MARK: - Geometric Utilities

/// Generate points on a circle
func circlePoints(center: SIMD3<Float>, radius: Float, count: Int, normal: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) -> [SIMD3<Float>] {
    var points: [SIMD3<Float>] = []

    // Create orthonormal basis
    let up = abs(normal.y) < 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
    let right = normalize(cross(up, normal))
    let forward = cross(normal, right)

    for i in 0..<count {
        let angle = Float(i) / Float(count) * 2.0 * .pi
        let x = cos(angle) * radius
        let z = sin(angle) * radius
        let point = center + right * x + forward * z
        points.append(point)
    }

    return points
}

/// Generate a spiral of points
func spiralPoints(center: SIMD3<Float>, startRadius: Float, endRadius: Float, height: Float, turns: Float, count: Int) -> [SIMD3<Float>] {
    var points: [SIMD3<Float>] = []

    for i in 0..<count {
        let t = Float(i) / Float(count - 1)
        let angle = t * turns * 2.0 * .pi
        let radius = Float.lerp(startRadius, endRadius, t)
        let y = t * height

        let x = cos(angle) * radius
        let z = sin(angle) * radius

        points.append(center + SIMD3<Float>(x, y, z))
    }

    return points
}
