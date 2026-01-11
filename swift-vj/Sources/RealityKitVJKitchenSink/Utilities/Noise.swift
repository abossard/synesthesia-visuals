// Noise.swift - Deterministic noise functions for procedural generation
// Simple Perlin-style noise for deforming meshes

import Foundation
import simd

/// Simple 3D noise implementation
struct Noise {
    /// Perlin-style noise (simplified)
    /// - Parameters:
    ///   - x: X coordinate
    ///   - y: Y coordinate
    ///   - z: Z coordinate
    /// - Returns: Noise value in range [-1, 1]
    static func perlin3D(x: Float, y: Float, z: Float) -> Float {
        // Simplified deterministic noise using sine waves
        // Production version would use proper Perlin/Simplex noise
        
        let freq1: Float = 1.0
        let freq2: Float = 2.71828
        let freq3: Float = 1.41421
        
        let n1 = sin(x * freq1 + cos(y * freq2))
        let n2 = sin(y * freq2 + cos(z * freq3))
        let n3 = sin(z * freq3 + cos(x * freq1))
        
        return (n1 + n2 + n3) / 3.0
    }
    
    /// Fractional Brownian Motion (layered noise)
    /// - Parameters:
    ///   - x: X coordinate
    ///   - y: Y coordinate
    ///   - z: Z coordinate
    ///   - octaves: Number of noise layers
    ///   - persistence: Amplitude decay per octave
    /// - Returns: Noise value
    static func fbm3D(
        x: Float,
        y: Float,
        z: Float,
        octaves: Int = 4,
        persistence: Float = 0.5
    ) -> Float {
        var total: Float = 0
        var amplitude: Float = 1.0
        var frequency: Float = 1.0
        var maxValue: Float = 0
        
        for _ in 0..<octaves {
            total += perlin3D(
                x: x * frequency,
                y: y * frequency,
                z: z * frequency
            ) * amplitude
            
            maxValue += amplitude
            amplitude *= persistence
            frequency *= 2.0
        }
        
        return total / maxValue
    }
    
    /// 3D noise from vector
    static func perlin3D(v: SIMD3<Float>) -> Float {
        perlin3D(x: v.x, y: v.y, z: v.z)
    }
    
    /// FBM from vector
    static func fbm3D(
        v: SIMD3<Float>,
        octaves: Int = 4,
        persistence: Float = 0.5
    ) -> Float {
        fbm3D(x: v.x, y: v.y, z: v.z, octaves: octaves, persistence: persistence)
    }
}

// MARK: - Hash Functions

/// Simple deterministic hash for seeding noise
func hash(_ x: Int, _ y: Int, _ z: Int) -> Float {
    let n = x &* 374761393 &+ y &* 668265263 &+ z &* 1911520717
    let bits = (n ^ (n >> 13)) &* 1274126177
    return Float(bits & 0x7fffffff) / Float(0x7fffffff) * 2.0 - 1.0
}
