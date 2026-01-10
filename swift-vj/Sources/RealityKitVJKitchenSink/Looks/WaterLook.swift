import Foundation
import RealityKit

@available(macOS 15.0, *)
struct WaterParams: LookParams {
    var waveAmplitude: Double = 0.25
    var waveFrequency: Double = 1.4
    var roughness: Double = 0.25
    var causticTint: Double = 0.6

    static var defaultValue: WaterParams { .init() }
}

@available(macOS 15.0, *)
final class WaterLook: Look {
    typealias Parameters = WaterParams

    let name = "Water"
    private let context: LookContext
    private var root = Entity()
    private var waterEntity = ModelEntity()
    private var time: Float = 0

    init(context: LookContext) {
        self.context = context
    }

    func makeRootEntity() -> Entity {
        root = Entity()

        let plane = MeshResource.generatePlane(width: 10.0, depth: 10.0)
        do {
            var material = try CustomMaterial(
                surfaceShader: .named("waterSurface", in: context.bundle),
                geometryModifier: .named("waterGeometry", in: context.bundle),
                lightingModel: .physicallyBased
            )
            material.roughness = .float(0.25)
            material.metallic = .float(0.0)
            material.custom.value = WaterUniforms(time: 0, amplitude: 0.25, frequency: 1.4, causticTint: 0.6)
            waterEntity = ModelEntity(mesh: plane, materials: [material])
        } catch {
            waterEntity = ModelEntity(mesh: plane, materials: [SimpleMaterial(color: .cyan, roughness: 0.2, isMetallic: false)])
        }
        waterEntity.transform.translation = [0, 0, 0]
        root.addChild(waterEntity)

        let light = DirectionalLight()
        light.light.intensity = 1300
        light.position = [2, 4, 3]
        root.addChild(light)

        return root
    }

    func update(dt: Double, params: GlobalParams, lookParams: WaterParams, time: Double) {
        self.time += Float(dt)
        if var material = waterEntity.model?.materials.first as? CustomMaterial {
            material.roughness = .float(Float(lookParams.roughness))
            material.custom.value = WaterUniforms(
                time: self.time,
                amplitude: Float(lookParams.waveAmplitude),
                frequency: Float(lookParams.waveFrequency),
                causticTint: Float(lookParams.causticTint)
            )
            waterEntity.model?.materials = [material]
        }
    }

    func teardown() {
        root.removeFromParent()
    }
}

@available(macOS 15.0, *)
struct WaterUniforms: CustomMaterialParameter, Codable {
    var time: Float
    var amplitude: Float
    var frequency: Float
    var causticTint: Float
}
