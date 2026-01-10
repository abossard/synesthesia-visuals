// SpaceDomeLook.swift
// RealityKitVJKitchenSink
//
// Space/sky dome look with starfield particles and nebula effects.
// Features: inverted sphere dome, particle starfield, hue-shifting nebula.

import RealityKit
import simd

/// Space dome with starfield particles and animated nebula
final class SpaceDomeLook: Look {
    typealias Params = SpaceDomeParams

    let rootEntity: Entity

    private var domeEntity: Entity?
    private var starfieldEntity: Entity?
    private var nebulaEntities: [Entity] = []

    private var baseHue: Float = 0
    private var starPhase: Float = 0

    // Store device reference for materials
    private let context: LookContext

    required init(context: LookContext) {
        self.context = context
        self.rootEntity = Entity()
        rootEntity.name = "SpaceDomeLook"

        setupDome()
        setupStarfield()
        setupNebulaClouds()
        setupAmbientLight()
    }

    // MARK: - Setup

    private func setupDome() {
        // Create an inverted sphere for the sky dome
        // We use a large sphere with normals facing inward

        let domeRadius: Float = 50.0

        // Generate dome mesh (inverted sphere)
        let mesh = MeshResource.generateSphere(radius: domeRadius)

        // Create dark gradient material
        var material = UnlitMaterial()
        material.color = .init(tint: .init(red: 0.02, green: 0.02, blue: 0.05, alpha: 1.0))

        let dome = ModelEntity(mesh: mesh, materials: [material])
        dome.name = "SkyDome"
        dome.scale = SIMD3<Float>(-1, 1, 1)  // Invert X to flip normals

        rootEntity.addChild(dome)
        domeEntity = dome
    }

    private func setupStarfield() {
        // Create particle emitter for stars
        // Reference: https://developer.apple.com/documentation/realitykit/particleemittercomponent

        let starfield = Entity()
        starfield.name = "Starfield"

        // Configure particle emitter
        var emitter = ParticleEmitterComponent()

        // Emission settings
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = SIMD3<Float>(repeating: 40)
        emitter.birthRate = 500
        emitter.burstCount = 2000
        emitter.burstCountVariation = 500

        // Particle appearance
        emitter.mainEmitter.birthRate = 100
        emitter.mainEmitter.lifeSpan = 10.0
        emitter.mainEmitter.size = 0.02
        emitter.mainEmitter.sizeVariation = 0.015
        emitter.mainEmitter.color = .evolving(
            start: .single(.white),
            end: .single(.init(white: 0.8, alpha: 0.5))
        )

        // Particle behavior
        emitter.mainEmitter.acceleration = SIMD3<Float>(0, 0, 0)
        emitter.mainEmitter.speed = 0.01
        emitter.mainEmitter.speedVariation = 0.005

        // Add some twinkling
        emitter.mainEmitter.opacityCurve = .linearFadeOut

        starfield.components[ParticleEmitterComponent.self] = emitter
        starfield.position = SIMD3<Float>(0, 0, 0)

        rootEntity.addChild(starfield)
        starfieldEntity = starfield
    }

    private func setupNebulaClouds() {
        // Create several nebula "clouds" using semi-transparent spheres
        let nebulaColors: [SIMD3<Float>] = [
            SIMD3<Float>(0.5, 0.2, 0.8),  // Purple
            SIMD3<Float>(0.2, 0.4, 0.9),  // Blue
            SIMD3<Float>(0.8, 0.3, 0.5),  // Pink
            SIMD3<Float>(0.1, 0.6, 0.7),  // Teal
        ]

        for i in 0..<4 {
            let angle = Float(i) * .pi / 2.0
            let distance: Float = 25.0
            let height = Float.random(in: -5...10)

            let position = SIMD3<Float>(
                cos(angle) * distance,
                height,
                sin(angle) * distance
            )

            let nebula = createNebulaCloud(
                color: nebulaColors[i],
                position: position,
                scale: Float.random(in: 8...15)
            )
            nebula.name = "Nebula_\(i)"

            rootEntity.addChild(nebula)
            nebulaEntities.append(nebula)
        }
    }

    private func createNebulaCloud(color: SIMD3<Float>, position: SIMD3<Float>, scale: Float) -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1.0)

        var material = UnlitMaterial()
        material.color = .init(tint: .init(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 0.15
        ))
        material.blending = .transparent(opacity: .init(floatLiteral: 0.15))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.scale = SIMD3<Float>(repeating: scale)

        return entity
    }

    private func setupAmbientLight() {
        // Add subtle ambient lighting for the scene
        let ambientLight = Entity()
        ambientLight.components[PointLightComponent.self] = PointLightComponent(
            color: .init(red: 0.3, green: 0.3, blue: 0.5, alpha: 1.0),
            intensity: 500,
            attenuationRadius: 100
        )
        ambientLight.position = SIMD3<Float>(0, 10, 0)

        rootEntity.addChild(ambientLight)
    }

    // MARK: - Look Protocol

    func activate() {
        // Reset animation state
        baseHue = 0
        starPhase = 0
    }

    func deactivate() {
        // Clean up any running animations
    }

    func update(time: Double, deltaTime: Double, params: SpaceDomeParams) {
        let dt = Float(deltaTime)
        let t = Float(time)

        // Update hue shift
        baseHue += dt * Float(params.domeHueSpeed) * 0.1
        if baseHue > 1.0 { baseHue -= 1.0 }

        // Update dome color based on hue
        updateDomeColor(hue: baseHue)

        // Update starfield density
        updateStarfield(density: Float(params.starDensity), time: t)

        // Animate nebula clouds
        updateNebulaClouds(intensity: Float(params.nebulaIntensity), time: t)

        // Apply camera drift through scene rotation
        if let dome = domeEntity {
            let driftAngle = sin(t * 0.1) * Float(params.cameraDriftAmplitude) * 0.1
            dome.orientation = simd_quatf(angle: driftAngle, axis: SIMD3<Float>(0, 1, 0))
        }
    }

    // MARK: - Animation Updates

    private func updateDomeColor(hue: Float) {
        guard let dome = domeEntity as? ModelEntity else { return }

        // Convert hue to RGB with low saturation for subtle effect
        let color = SIMD3<Float>.fromHSV(h: hue, s: 0.3, v: 0.05)

        var material = UnlitMaterial()
        material.color = .init(tint: .init(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 1.0
        ))

        dome.model?.materials = [material]
    }

    private func updateStarfield(density: Float, time: Float) {
        guard let starfield = starfieldEntity else { return }

        // Update particle emitter birth rate based on density
        if var emitter = starfield.components[ParticleEmitterComponent.self] {
            emitter.mainEmitter.birthRate = 50 * density

            // Add subtle size pulsing
            let sizePulse = 0.01 + 0.01 * sin(time * 2.0)
            emitter.mainEmitter.size = sizePulse

            starfield.components[ParticleEmitterComponent.self] = emitter
        }
    }

    private func updateNebulaClouds(intensity: Float, time: Float) {
        for (i, nebula) in nebulaEntities.enumerated() {
            guard let model = nebula as? ModelEntity else { continue }

            // Slow rotation for each nebula
            let rotationSpeed: Float = 0.05 + Float(i) * 0.02
            let rotation = simd_quatf(angle: time * rotationSpeed, axis: SIMD3<Float>(0.2, 1, 0.1))
            nebula.orientation = rotation

            // Breathing effect on scale
            let breathe = 1.0 + 0.1 * sin(time * 0.5 + Float(i))
            let baseScale = 8.0 + Float(i) * 2.0
            nebula.scale = SIMD3<Float>(repeating: baseScale * breathe)

            // Update opacity based on intensity
            if let currentMaterial = model.model?.materials.first as? UnlitMaterial {
                var material = currentMaterial
                material.blending = .transparent(opacity: .init(floatLiteral: Double(0.1 * intensity)))
                model.model?.materials = [material]
            }
        }
    }

    func teardown() {
        // Particle emitters clean up automatically
        rootEntity.removeFromParent()
    }
}
