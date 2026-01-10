import Foundation

@available(macOS 15.0, *)
enum Math {
    static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }

    static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}
