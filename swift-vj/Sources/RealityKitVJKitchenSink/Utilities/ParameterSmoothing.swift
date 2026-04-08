import Foundation

@available(macOS 15.0, *)
struct ParameterSmoothing<T: SIMD> where T.Scalar == Float {
    private var value: T
    private let response: Float

    init(initialValue: T, response: Float = 12) {
        self.value = initialValue
        self.response = response
    }

    mutating func update(target: T, deltaTime: Double) -> T {
        let dt = Float(deltaTime)
        let alpha = 1 - exp(-response * dt)
        value = value + (target - value) * alpha
        return value
    }
}
