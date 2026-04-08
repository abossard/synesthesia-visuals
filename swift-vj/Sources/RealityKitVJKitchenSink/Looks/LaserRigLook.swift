import AppKit
import Foundation
import RealityKit

@available(macOS 15.0, *)
struct LaserRigParams: LookParams {
    var beamCount: Double = 24
    var sweepSpeed: Double = 1.0
    var glowIntensity: Double = 1.4
    var colorCycle: Double = 0.8

    static var defaultValue: LaserRigParams { .init() }
}

@available(macOS 15.0, *)
final class LaserRigLook: Look {
    typealias Parameters = LaserRigParams

    let name = "Laser Rig"
    private let context: LookContext
    private var root = Entity()
    private var beamEntities: [ModelEntity] = []
    private var baseMaterial = UnlitMaterial(color: .green)

    init(context: LookContext) {
        self.context = context
    }

    func makeRootEntity() -> Entity {
        root = Entity()
        baseMaterial.color = .init(tint: .green, texture: nil)
        createBeams(count: 24)
        return root
    }

    func update(dt: Double, params: GlobalParams, lookParams: LaserRigParams, time: Double) {
        let beamCount = Int(lookParams.beamCount)
        if beamEntities.count != beamCount {
            root.children.removeAll()
            beamEntities.removeAll()
            createBeams(count: beamCount)
        }

        let hue = Float((time * lookParams.colorCycle).truncatingRemainder(dividingBy: 1.0))
        let tint = NSColor(hue: CGFloat(hue), saturation: 0.9, brightness: 0.9, alpha: 1.0)
        let material = UnlitMaterial(color: tint)

        let sweep = Float(sin(time * lookParams.sweepSpeed))
        for (index, beam) in beamEntities.enumerated() {
            let offset = Float(index) / Float(max(1, beamEntities.count - 1))
            let angle = (offset - 0.5) * 1.6 + sweep * 0.5
            beam.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            beam.model?.materials = [material]
        }

        context.postProcess.bloomIntensity = max(params.bloomIntensity, lookParams.glowIntensity)
    }

    func teardown() {
        root.removeFromParent()
        beamEntities.removeAll()
    }

    private func createBeams(count: Int) {
        let beamMesh = MeshResource.generateCylinder(radius: 0.015, height: 6.0)
        for index in 0..<count {
            let beam = ModelEntity(mesh: beamMesh, materials: [baseMaterial])
            beam.position = [0, 1.2, -1.0]
            beamEntities.append(beam)
            root.addChild(beam)

            let offset = Float(index) / Float(max(1, count - 1))
            let angle = (offset - 0.5) * 1.4
            beam.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        }

        let floor = ModelEntity(mesh: .generatePlane(width: 8, depth: 8), materials: [SimpleMaterial(color: .black, roughness: 0.8, isMetallic: false)])
        floor.position.y = -0.01
        root.addChild(floor)
    }
}
