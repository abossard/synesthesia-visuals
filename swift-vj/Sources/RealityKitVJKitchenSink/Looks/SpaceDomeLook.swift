import AppKit
import Foundation
import RealityKit

@available(macOS 15.0, *)
struct SpaceDomeParams: LookParams {
    var starDensity: Double = 1.2
    var hueSpeed: Double = 0.35
    var cameraDrift: Double = 0.8

    static var defaultValue: SpaceDomeParams { .init() }
}

@available(macOS 15.0, *)
final class SpaceDomeLook: Look {
    typealias Parameters = SpaceDomeParams

    let name = "Space Dome"
    private let context: LookContext
    private var domeEntity = ModelEntity()
    private var particleEntity = Entity()

    init(context: LookContext) {
        self.context = context
    }

    func makeRootEntity() -> Entity {
        let root = Entity()

        let sphere = MeshResource.generateSphere(radius: 6.0)
        var material = UnlitMaterial(color: .init(red: 0.02, green: 0.03, blue: 0.06, alpha: 1.0))
        material.color = .init(tint: .init(red: 0.02, green: 0.03, blue: 0.06, alpha: 1.0), texture: nil)
        domeEntity = ModelEntity(mesh: sphere, materials: [material])
        domeEntity.scale = SIMD3<Float>(repeating: -1)
        root.addChild(domeEntity)

        var emitter = ParticleEmitterComponent()
        emitter.birthRate = 1200
        emitter.emitterShape = .sphere
        emitter.emissionDirection = .init(0, 0, 0)
        emitter.mainEmitterDirection = .init(0, 1, 0)
        emitter.particleColor = .white
        emitter.particleSize = 0.01
        emitter.lifespan = 8.0
        emitter.velocity = 0.0
        particleEntity.components.set(emitter)
        particleEntity.position = .zero
        root.addChild(particleEntity)

        return root
    }

    func update(dt: Double, params: GlobalParams, lookParams: SpaceDomeParams, time: Double) {
        let hue = Float((time * lookParams.hueSpeed).truncatingRemainder(dividingBy: 1.0))
        let color = NSColor(hue: CGFloat(hue), saturation: 0.45, brightness: 0.25, alpha: 1.0)
        if var material = domeEntity.model?.materials.first as? UnlitMaterial {
            material.color = .init(tint: color, texture: nil)
            domeEntity.model?.materials = [material]
        }
        if var emitter = particleEntity.components[ParticleEmitterComponent.self] {
            emitter.birthRate = Float(1200.0 * lookParams.starDensity)
            particleEntity.components.set(emitter)
        }
    }

    func teardown() {
        domeEntity.removeFromParent()
        particleEntity.removeFromParent()
    }
}
