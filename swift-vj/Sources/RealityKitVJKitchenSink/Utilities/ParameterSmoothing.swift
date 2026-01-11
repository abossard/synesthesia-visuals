// ParameterSmoothing.swift - Time-based smoothing for UI-driven parameters
// Prevents jarring changes when sliders are adjusted

import Foundation

/// Smooth parameter changes over time to avoid jarring transitions
final class ParameterSmoother {
    private var currentValue: Double
    private var targetValue: Double
    private let smoothTime: Double
    
    /// Create a parameter smoother
    /// - Parameters:
    ///   - initialValue: Starting value
    ///   - smoothTime: Time in seconds to reach 63% of target (tau)
    init(initialValue: Double = 0, smoothTime: Double = 0.3) {
        self.currentValue = initialValue
        self.targetValue = initialValue
        self.smoothTime = smoothTime
    }
    
    /// Update target value (from UI)
    func setTarget(_ value: Double) {
        targetValue = value
    }
    
    /// Update current value toward target
    /// - Parameter dt: Delta time in seconds
    /// - Returns: Smoothed current value
    func update(dt: Double) -> Double {
        if abs(currentValue - targetValue) < 0.001 {
            currentValue = targetValue
            return currentValue
        }
        
        // Exponential smoothing
        let alpha = 1.0 - exp(-dt / smoothTime)
        currentValue += (targetValue - currentValue) * alpha
        
        return currentValue
    }
    
    /// Get current smoothed value without updating
    var value: Double {
        currentValue
    }
    
    /// Immediately snap to target (skip smoothing)
    func snapToTarget() {
        currentValue = targetValue
    }
}

// MARK: - Vector Smoother

/// Smooth 3D vector parameters
final class Vector3Smoother {
    private var x: ParameterSmoother
    private var y: ParameterSmoother
    private var z: ParameterSmoother
    
    init(initialValue: SIMD3<Float> = .zero, smoothTime: Double = 0.3) {
        self.x = ParameterSmoother(initialValue: Double(initialValue.x), smoothTime: smoothTime)
        self.y = ParameterSmoother(initialValue: Double(initialValue.y), smoothTime: smoothTime)
        self.z = ParameterSmoother(initialValue: Double(initialValue.z), smoothTime: smoothTime)
    }
    
    func setTarget(_ value: SIMD3<Float>) {
        x.setTarget(Double(value.x))
        y.setTarget(Double(value.y))
        z.setTarget(Double(value.z))
    }
    
    func update(dt: Double) -> SIMD3<Float> {
        SIMD3<Float>(
            Float(x.update(dt: dt)),
            Float(y.update(dt: dt)),
            Float(z.update(dt: dt))
        )
    }
    
    var value: SIMD3<Float> {
        SIMD3<Float>(
            Float(x.value),
            Float(y.value),
            Float(z.value)
        )
    }
}
