// Math.swift - Math utilities for RealityKit VJ
// Common math operations and helpers

import Foundation
import simd

// MARK: - Vector Extensions

extension SIMD3 where Scalar == Float {
    /// Length of the vector
    var length: Float {
        sqrt(x * x + y * y + z * z)
    }
    
    /// Normalized vector
    var normalized: SIMD3<Float> {
        let len = length
        return len > 0 ? self / len : .zero
    }
}

// MARK: - Color Utilities

extension simd_float3 {
    /// Create RGB color from HSV
    /// - Parameters:
    ///   - h: Hue (0-1)
    ///   - s: Saturation (0-1)
    ///   - v: Value/Brightness (0-1)
    static func fromHSV(h: Float, s: Float, v: Float) -> simd_float3 {
        let h = h.truncatingRemainder(dividingBy: 1.0) * 6.0
        let i = Int(h)
        let f = h - Float(i)
        let p = v * (1.0 - s)
        let q = v * (1.0 - s * f)
        let t = v * (1.0 - s * (1.0 - f))
        
        switch i % 6 {
        case 0: return simd_float3(v, t, p)
        case 1: return simd_float3(q, v, p)
        case 2: return simd_float3(p, v, t)
        case 3: return simd_float3(p, q, v)
        case 4: return simd_float3(t, p, v)
        case 5: return simd_float3(v, p, q)
        default: return simd_float3(v, t, p)
        }
    }
}

// MARK: - Interpolation

/// Linear interpolation
func lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T {
    return a + (b - a) * t
}

/// Smooth step interpolation (cubic Hermite)
func smoothstep<T: FloatingPoint>(_ edge0: T, _ edge1: T, _ x: T) -> T {
    let t = max(T.zero, min((x - edge0) / (edge1 - edge0), T(1)))
    return t * t * (T(3) - T(2) * t)
}

// MARK: - Easing Functions

enum Easing {
    static func easeInOutQuad(_ t: Float) -> Float {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
    
    static func easeOutElastic(_ t: Float) -> Float {
        let c4 = (2 * Float.pi) / 3
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }
}
