import Foundation
import RealityKit

@available(macOS 15.0, *)
struct DancerParams: LookParams {
    var animationSpeed: Double = 1.0
    var scalePulse: Double = 0.25
    var lightingIntensity: Double = 1.4
    var floorReflectivity: Double = 0.4

    static var defaultValue: DancerParams { .init() }
}

@available(macOS 15.0, *)
final class DancerLook: Look {
    typealias Parameters = DancerParams

    let name = "Dancer"
    private let context: LookContext
    private var root = Entity()
    private var characterEntity = Entity()
    private var idleRotation: Float = 0
    private var mainLight = DirectionalLight()
    private var fillLight = PointLight()
    private var rimLight = SpotLight()
    private var floor = ModelEntity()
    private var animationController: AnimationPlaybackController?

    init(context: LookContext) {
        self.context = context
    }

    func makeRootEntity() -> Entity {
        root = Entity()
        root.position = [0, 0, 0]

        characterEntity = loadCharacter()
        characterEntity.position = [0, 0, 0]
        root.addChild(characterEntity)

        mainLight.light.intensity = 1500
        mainLight.orientation = simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])
        mainLight.position = [2, 4, 3]
        root.addChild(mainLight)

        fillLight.light.intensity = 600
        fillLight.light.color = .init(red: 0.7, green: 0.8, blue: 1.0, alpha: 1.0)
        fillLight.position = [-2, 2, 2]
        root.addChild(fillLight)

        rimLight.light.intensity = 800
        rimLight.light.color = .init(red: 1.0, green: 0.8, blue: 0.6, alpha: 1.0)
        rimLight.position = [0, 3, -3]
        rimLight.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        root.addChild(rimLight)

        floor = ModelEntity(
            mesh: .generatePlane(width: 8, depth: 8),
            materials: [SimpleMaterial(color: .darkGray, roughness: 0.2, isMetallic: false)]
        )
        floor.position = [0, -0.01, 0]
        root.addChild(floor)

        if let animation = characterEntity.availableAnimations.first {
            animationController = characterEntity.playAnimation(animation.repeat(duration: animation.duration))
        }

        return root
    }

    func update(dt: Double, params: GlobalParams, lookParams: DancerParams, time: Double) {
        idleRotation += Float(dt) * 0.4
        let pulse = Float(1.0 + sin(time * 1.2) * lookParams.scalePulse)
        characterEntity.transform.rotation = simd_quatf(angle: idleRotation, axis: [0, 1, 0])
        characterEntity.transform.scale = [pulse, pulse, pulse]

        mainLight.light.intensity = Float(1200 * lookParams.lightingIntensity)
        fillLight.light.intensity = Float(500 * lookParams.lightingIntensity)
        rimLight.light.intensity = Float(800 * lookParams.lightingIntensity)

        if var material = floor.model?.materials.first as? SimpleMaterial {
            material.roughness = .float(Float(1.0 - lookParams.floorReflectivity))
            floor.model?.materials = [material]
        }

        animationController?.speed = Float(lookParams.animationSpeed)
    }

    func teardown() {
        root.removeFromParent()
    }

    private func loadCharacter() -> Entity {
        if let url = context.bundle.url(forResource: "toy_robot_vintage", withExtension: "usdz", subdirectory: "Models") {
            if let entity = try? Entity.load(contentsOf: url) {
                return entity
            }
        }
        let placeholder = ModelEntity(mesh: .generateBox(size: 1.0), materials: [SimpleMaterial(color: .purple, roughness: 0.4, isMetallic: true)])
        return placeholder
    }
}
