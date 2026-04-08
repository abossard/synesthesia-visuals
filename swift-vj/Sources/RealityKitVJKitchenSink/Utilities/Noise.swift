import Foundation

@available(macOS 15.0, *)
struct ValueNoise {
    private let seed: Int

    init(seed: Int) {
        self.seed = seed
    }

    func sample(x: Double, y: Double) -> Double {
        let xi = floor(x)
        let yi = floor(y)
        let xf = x - xi
        let yf = y - yi

        let v00 = hash(x: Int(xi), y: Int(yi))
        let v10 = hash(x: Int(xi + 1), y: Int(yi))
        let v01 = hash(x: Int(xi), y: Int(yi + 1))
        let v11 = hash(x: Int(xi + 1), y: Int(yi + 1))

        let u = fade(xf)
        let v = fade(yf)
        let x1 = lerp(v00, v10, t: u)
        let x2 = lerp(v01, v11, t: u)
        return lerp(x1, x2, t: v)
    }

    private func hash(x: Int, y: Int) -> Double {
        var n = x &* 374761393 &+ y &* 668265263 &+ seed &* 69069
        n = (n ^ (n >> 13)) &* 1274126177
        let normalized = Double(n & 0x7fffffff) / Double(Int32.max)
        return normalized * 2.0 - 1.0
    }

    private func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    private func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }
}
