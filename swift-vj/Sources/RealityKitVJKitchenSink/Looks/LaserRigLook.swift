// LaserRigLook.swift
// RealityKitVJKitchenSink
//
// Laser beam rig look with emissive materials and bloom-dependent glow.
// Features: array of beam meshes in fan/grid, color cycling, sweep animation.

import RealityKit
import simd

/// Laser rig with animated beam array
final class LaserRigLook: Look {
    typealias Params = LaserRigParams

    let rootEntity: Entity

    private var beamEntities: [Entity] = []
    private var rigEntity: Entity?
    private var floorEntity: Entity?
    private var fogEntity: Entity?

    private let context: LookContext

    // Animation state
    private var sweepAngle: Float = 0
    private var colorPhase: Float = 0

    // Beam configuration
    private let beamLength: Float = 15.0
    private let beamRadius: Float = 0.02

    required init(context: LookContext) {
        self.context = context
        self.rootEntity = Entity()
        rootEntity.name = "LaserRigLook"

        setupRig()
        setupFloor()
        setupAtmosphere()
    }

    // MARK: - Setup

    private func setupRig() {
        let rig = Entity()
        rig.name = "LaserRig"
        rig.position = SIMD3<Float>(0, 5, 0)  // Mounted high

        rootEntity.addChild(rig)
        rigEntity = rig

        // Create initial beams
        rebuildBeams(count: 12)
    }

    private func rebuildBeams(count: Int) {
        guard let rig = rigEntity else { return }

        // Remove existing beams
        for beam in beamEntities {
            beam.removeFromParent()
        }
        beamEntities.removeAll()

        // Create new beams
        for i in 0..<count {
            let beam = createBeam(index: i, totalCount: count)
            rig.addChild(beam)
            beamEntities.append(beam)
        }
    }

    private func createBeam(index: Int, totalCount: Int) -> Entity {
        // Create a thin cylinder for the laser beam
        let mesh = MeshResource.generateCylinder(height: beamLength, radius: beamRadius)

        // Start with a bright emissive material
        var material = UnlitMaterial()
        material.color = .init(tint: .init(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0))

        // For true laser look, we want the bloom post-process to make it glow

        let beam = ModelEntity(mesh: mesh, materials: [material])
        beam.name = "LaserBeam_\(index)"

        // Position beam to point downward from rig
        // Pivot is at center, so offset by half length
        beam.position = SIMD3<Float>(0, -beamLength / 2, 0)

        // Wrap in container for rotation
        let beamContainer = Entity()
        beamContainer.name = "BeamContainer_\(index)"
        beamContainer.addChild(beam)

        return beamContainer
    }

    private func setupFloor() {
        // Dark reflective floor for laser show effect
        let floorMesh = MeshResource.generatePlane(width: 30, depth: 30)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0))
        material.metallic = .init(floatLiteral: 0.9)
        material.roughness = .init(floatLiteral: 0.1)

        let floor = ModelEntity(mesh: floorMesh, materials: [material])
        floor.name = "LaserFloor"
        floor.position = SIMD3<Float>(0, -0.5, 0)

        rootEntity.addChild(floor)
        floorEntity = floor
    }

    private func setupAtmosphere() {
        // Add fog/haze particles for laser visibility
        let fog = Entity()
        fog.name = "AtmosphericFog"

        var emitter = ParticleEmitterComponent()

        emitter.emitterShape = .box
        emitter.emitterShapeSize = SIMD3<Float>(20, 10, 20)
        emitter.birthRate = 50

        emitter.mainEmitter.birthRate = 20
        emitter.mainEmitter.lifeSpan = 8.0
        emitter.mainEmitter.size = 0.5
        emitter.mainEmitter.sizeVariation = 0.3
        emitter.mainEmitter.color = .constant(.single(.init(white: 0.2, alpha: 0.3)))
        emitter.mainEmitter.speed = 0.1
        emitter.mainEmitter.acceleration = SIMD3<Float>(0, 0.05, 0)
        emitter.mainEmitter.opacityCurve = .linearFadeIn

        fog.components[ParticleEmitterComponent.self] = emitter
        fog.position = SIMD3<Float>(0, 2, 0)

        rootEntity.addChild(fog)
        fogEntity = fog
    }

    // MARK: - Look Protocol

    func activate() {
        sweepAngle = 0
        colorPhase = 0
    }

    func deactivate() {
        // Nothing special needed
    }

    func update(time: Double, deltaTime: Double, params: LaserRigParams) {
        let t = Float(time)
        let dt = Float(deltaTime)

        // Check if beam count changed
        if beamEntities.count != params.beamCount {
            rebuildBeams(count: params.beamCount)
        }

        // Update sweep animation
        sweepAngle += dt * Float(params.beamSweepSpeed) * 0.5

        // Update color cycling
        colorPhase += dt * Float(params.colorCycleSpeed) * 0.2
        if colorPhase > 1.0 { colorPhase -= 1.0 }

        // Update each beam
        updateBeams(
            time: t,
            params: params
        )
    }

    private func updateBeams(time: Float, params: LaserRigParams) {
        let beamCount = beamEntities.count
        guard beamCount > 0 else { return }

        let halfAngle = Float(params.fanAngle) * .pi / 180.0 / 2.0

        for (i, beamContainer) in beamEntities.enumerated() {
            // Calculate beam angle in fan
            let normalizedIndex = Float(i) / Float(beamCount - 1) - 0.5
            let baseAngle = normalizedIndex * 2.0 * halfAngle

            // Add sweep animation
            let sweepOffset = sin(sweepAngle + Float(i) * 0.3) * 0.3

            // Apply rotation
            let beamAngle = baseAngle + sweepOffset
            beamContainer.orientation = simd_quatf(angle: beamAngle, axis: SIMD3<Float>(0, 0, 1))

            // Update beam color
            if let beam = beamContainer.children.first as? ModelEntity {
                updateBeamColor(
                    beam: beam,
                    index: i,
                    totalCount: beamCount,
                    params: params
                )
            }
        }
    }

    private func updateBeamColor(beam: ModelEntity, index: Int, totalCount: Int, params: LaserRigParams) {
        // Calculate color based on position and cycle phase
        let hueOffset = Float(index) / Float(totalCount)
        let hue = fmod(colorPhase + hueOffset, 1.0)

        // Create bright, saturated color
        let color = SIMD3<Float>.fromHSV(h: hue, s: 1.0, v: 1.0)

        // Scale by glow intensity for emissive effect
        let glowColor = color * Float(params.glowIntensity)

        var material = UnlitMaterial()
        material.color = .init(tint: .init(
            red: CGFloat(min(glowColor.x, 1.0)),
            green: CGFloat(min(glowColor.y, 1.0)),
            blue: CGFloat(min(glowColor.z, 1.0)),
            alpha: 1.0
        ))

        beam.model?.materials = [material]
    }

    func teardown() {
        beamEntities.removeAll()
        rootEntity.removeFromParent()
    }
}
