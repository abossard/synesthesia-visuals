// Noise.swift
// RealityKitVJKitchenSink
//
// Deterministic noise functions for procedural animation.
// No external dependencies - pure Swift implementation.

import simd
import Foundation

// MARK: - Noise Generator

/// Deterministic noise generator
struct Noise {
    // MARK: - Hash Functions

    /// Simple hash function for reproducible randomness
    private static func hash(_ n: Float) -> Float {
        let x = sin(n) * 43758.5453123
        return x - floor(x)
    }

    /// 2D hash
    private static func hash2(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let n = sin(dot(p, SIMD2<Float>(127.1, 311.7)))
        let m = sin(dot(p, SIMD2<Float>(269.5, 183.3)))
        return SIMD2<Float>(hash(n * 43758.5453), hash(m * 43758.5453))
    }

    /// 3D hash
    private static func hash3(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let n = sin(dot(p, SIMD3<Float>(127.1, 311.7, 74.7)))
        let m = sin(dot(p, SIMD3<Float>(269.5, 183.3, 246.1)))
        let o = sin(dot(p, SIMD3<Float>(113.5, 271.9, 124.6)))
        return SIMD3<Float>(hash(n * 43758.5453), hash(m * 43758.5453), hash(o * 43758.5453))
    }

    // MARK: - Value Noise

    /// 1D value noise
    static func value(_ x: Float) -> Float {
        let i = floor(x)
        let f = x - i

        // Cubic interpolation
        let u = f * f * (3.0 - 2.0 * f)

        return Float.lerp(hash(i), hash(i + 1), u)
    }

    /// 2D value noise
    static func value(_ p: SIMD2<Float>) -> Float {
        let i = SIMD2<Float>(floor(p.x), floor(p.y))
        let f = p - i

        // Cubic interpolation
        let u = f * f * (3.0 - 2.0 * f)

        let a = hash(dot(i, SIMD2<Float>(1, 157)))
        let b = hash(dot(i + SIMD2<Float>(1, 0), SIMD2<Float>(1, 157)))
        let c = hash(dot(i + SIMD2<Float>(0, 1), SIMD2<Float>(1, 157)))
        let d = hash(dot(i + SIMD2<Float>(1, 1), SIMD2<Float>(1, 157)))

        return Float.lerp(
            Float.lerp(a, b, u.x),
            Float.lerp(c, d, u.x),
            u.y
        )
    }

    /// 3D value noise
    static func value(_ p: SIMD3<Float>) -> Float {
        let i = SIMD3<Float>(floor(p.x), floor(p.y), floor(p.z))
        let f = p - i

        // Smooth interpolation
        let u = f * f * (3.0 - 2.0 * f)

        // Hash corners
        func h(_ offset: SIMD3<Float>) -> Float {
            return hash(dot(i + offset, SIMD3<Float>(1, 157, 113)))
        }

        return Float.lerp(
            Float.lerp(
                Float.lerp(h(SIMD3<Float>(0, 0, 0)), h(SIMD3<Float>(1, 0, 0)), u.x),
                Float.lerp(h(SIMD3<Float>(0, 1, 0)), h(SIMD3<Float>(1, 1, 0)), u.x),
                u.y
            ),
            Float.lerp(
                Float.lerp(h(SIMD3<Float>(0, 0, 1)), h(SIMD3<Float>(1, 0, 1)), u.x),
                Float.lerp(h(SIMD3<Float>(0, 1, 1)), h(SIMD3<Float>(1, 1, 1)), u.x),
                u.y
            ),
            u.z
        )
    }

    // MARK: - Gradient Noise (Perlin-like)

    /// Gradient function for 2D
    private static func gradient2(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let h = hash2(p)
        let angle = h.x * 2.0 * .pi
        return SIMD2<Float>(cos(angle), sin(angle))
    }

    /// 2D gradient noise
    static func gradient(_ p: SIMD2<Float>) -> Float {
        let i = SIMD2<Float>(floor(p.x), floor(p.y))
        let f = p - i

        // Smooth interpolation (quintic curve)
        let f2 = f * f
        let f3 = f2 * f
        let inner = f * 6.0 - SIMD2<Float>(repeating: 15.0)
        let u = f3 * (f2 * inner + SIMD2<Float>(repeating: 10.0))

        let n00 = dot(gradient2(i + SIMD2<Float>(0, 0)), f - SIMD2<Float>(0, 0))
        let n10 = dot(gradient2(i + SIMD2<Float>(1, 0)), f - SIMD2<Float>(1, 0))
        let n01 = dot(gradient2(i + SIMD2<Float>(0, 1)), f - SIMD2<Float>(0, 1))
        let n11 = dot(gradient2(i + SIMD2<Float>(1, 1)), f - SIMD2<Float>(1, 1))

        return Float.lerp(
            Float.lerp(n00, n10, u.x),
            Float.lerp(n01, n11, u.x),
            u.y
        ) * 0.5 + 0.5  // Normalize to 0-1
    }

    // MARK: - Fractal Noise (FBM)

    /// Fractal Brownian Motion (multiple octaves of noise)
    static func fbm(_ p: SIMD2<Float>, octaves: Int = 4, lacunarity: Float = 2.0, gain: Float = 0.5) -> Float {
        var value: Float = 0
        var amplitude: Float = 0.5
        var maxValue: Float = 0

        var currentP = p

        for _ in 0..<octaves {
            value += amplitude * Self.value(currentP)
            maxValue += amplitude

            amplitude *= gain
            currentP *= lacunarity
        }

        return value / maxValue
    }

    /// 3D FBM
    static func fbm(_ p: SIMD3<Float>, octaves: Int = 4, lacunarity: Float = 2.0, gain: Float = 0.5) -> Float {
        var value: Float = 0
        var amplitude: Float = 0.5
        var maxValue: Float = 0

        var currentP = p

        for _ in 0..<octaves {
            value += amplitude * self.value(currentP)
            maxValue += amplitude

            amplitude *= gain
            currentP *= lacunarity
        }

        return value / maxValue
    }

    // MARK: - Ridged Noise

    /// Ridged multi-fractal noise (good for terrain, worms)
    static func ridged(_ p: SIMD2<Float>, octaves: Int = 4, lacunarity: Float = 2.0, gain: Float = 0.5) -> Float {
        var value: Float = 0
        var amplitude: Float = 0.5
        var maxValue: Float = 0

        var currentP = p

        for _ in 0..<octaves {
            let n = 1.0 - abs(self.value(currentP) * 2.0 - 1.0)
            value += amplitude * n * n
            maxValue += amplitude

            amplitude *= gain
            currentP *= lacunarity
        }

        return value / maxValue
    }

    // MARK: - Turbulence

    /// Turbulence (absolute value of noise)
    static func turbulence(_ p: SIMD2<Float>, octaves: Int = 4) -> Float {
        var value: Float = 0
        var amplitude: Float = 0.5
        var maxValue: Float = 0

        var currentP = p

        for _ in 0..<octaves {
            value += amplitude * abs(self.value(currentP) * 2.0 - 1.0)
            maxValue += amplitude

            amplitude *= 0.5
            currentP *= 2.0
        }

        return value / maxValue
    }

    // MARK: - Cellular/Worley Noise

    /// Simple Worley noise (distance to nearest cell point)
    static func worley(_ p: SIMD2<Float>) -> Float {
        let i = SIMD2<Float>(floor(p.x), floor(p.y))
        let f = p - i

        var minDist: Float = 1.0

        for j in -1...1 {
            for k in -1...1 {
                let offset = SIMD2<Float>(Float(j), Float(k))
                let randomOffset = hash2(i + offset)
                let cellPoint = offset + randomOffset

                let dist = length(cellPoint - f)
                minDist = min(minDist, dist)
            }
        }

        return minDist
    }

    // MARK: - Domain Warping

    /// Domain warp using FBM
    static func warpedFbm(_ p: SIMD2<Float>, time: Float, scale: Float = 0.5) -> Float {
        let warp = SIMD2<Float>(
            fbm(p + SIMD2<Float>(0, time * 0.1)),
            fbm(p + SIMD2<Float>(5.2, time * 0.1))
        )

        return fbm(p + warp * scale)
    }
}

// MARK: - Simplex Noise

/// Simplex noise implementation (faster than Perlin for higher dimensions)
extension Noise {
    // Simplex skew factors
    private static let F2: Float = 0.5 * (sqrt(3.0) - 1.0)
    private static let G2: Float = (3.0 - sqrt(3.0)) / 6.0

    /// 2D Simplex noise
    static func simplex(_ p: SIMD2<Float>) -> Float {
        let s = (p.x + p.y) * F2
        let i = floor(p.x + s)
        let j = floor(p.y + s)

        let t = (i + j) * G2
        let x0 = p.x - (i - t)
        let y0 = p.y - (j - t)

        var i1: Float, j1: Float
        if x0 > y0 {
            i1 = 1; j1 = 0
        } else {
            i1 = 0; j1 = 1
        }

        let x1 = x0 - i1 + G2
        let y1 = y0 - j1 + G2
        let x2 = x0 - 1.0 + 2.0 * G2
        let y2 = y0 - 1.0 + 2.0 * G2

        // Calculate contributions
        var n0: Float = 0
        var t0 = 0.5 - x0*x0 - y0*y0
        if t0 >= 0 {
            t0 *= t0
            let g = gradient2(SIMD2<Float>(i, j))
            n0 = t0 * t0 * (g.x * x0 + g.y * y0)
        }

        var n1: Float = 0
        var t1 = 0.5 - x1*x1 - y1*y1
        if t1 >= 0 {
            t1 *= t1
            let g = gradient2(SIMD2<Float>(i + i1, j + j1))
            n1 = t1 * t1 * (g.x * x1 + g.y * y1)
        }

        var n2: Float = 0
        var t2 = 0.5 - x2*x2 - y2*y2
        if t2 >= 0 {
            t2 *= t2
            let g = gradient2(SIMD2<Float>(i + 1, j + 1))
            n2 = t2 * t2 * (g.x * x2 + g.y * y2)
        }

        // Scale to 0-1 range
        return 70.0 * (n0 + n1 + n2) * 0.5 + 0.5
    }
}
