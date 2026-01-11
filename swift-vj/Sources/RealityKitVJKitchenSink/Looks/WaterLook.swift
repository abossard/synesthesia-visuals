// WaterLook.swift
// RealityKitVJKitchenSink
//
// Water surface look with animated wave simulation using vertex displacement.
// Uses standard PBR materials since CustomMaterial requires precompiled Metal shaders.

import RealityKit
import Metal
import simd
import CoreGraphics

/// Water surface with animated waves using procedural mesh updates
@MainActor
final class WaterLook: Look {
    typealias Params = WaterParams

    let rootEntity: Entity

    private var waterPlaneEntity: ModelEntity?
    private var underglowLight: Entity?

    private let context: LookContext

    // Grid parameters for wave simulation
    private let gridSize: Int = 64
    private let planeSize: Float = 30.0
    private var baseVertices: [SIMD3<Float>] = []

    // Animation state
    private var animTime: Float = 0

    required init(context: LookContext) {
        self.context = context
        self.rootEntity = Entity()
        rootEntity.name = "WaterLook"

        setupWaterPlane()
        setupEnvironment()
        setupLighting()
    }

    // MARK: - Setup

    private func setupWaterPlane() {
        // Create a subdivided plane for wave animation
        let mesh = MeshResource.generatePlane(
            width: planeSize,
            depth: planeSize,
            cornerRadius: 0
        )

        // Create water material
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.15, green: 0.4, blue: 0.65, alpha: 0.9))
        material.metallic = .init(floatLiteral: 0.1)
        material.roughness = .init(floatLiteral: 0.15)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.85))

        let waterPlane = ModelEntity(mesh: mesh, materials: [material])
        waterPlane.name = "WaterSurface"
        waterPlane.position = SIMD3<Float>(0, 0, 0)

        rootEntity.addChild(waterPlane)
        waterPlaneEntity = waterPlane
    }

    private func setupEnvironment() {
        // Add a floor/depth indicator beneath the water
        let floorMesh = MeshResource.generatePlane(width: 40, depth: 40)

        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: .init(red: 0.02, green: 0.05, blue: 0.1, alpha: 1.0))
        floorMaterial.metallic = .init(floatLiteral: 0.0)
        floorMaterial.roughness = .init(floatLiteral: 0.9)

        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.name = "SeaFloor"
        floor.position = SIMD3<Float>(0, -5, 0)

        rootEntity.addChild(floor)

        // Add some underwater objects for visual interest
        addUnderwaterRocks()
    }

    private func addUnderwaterRocks() {
        let rockCount = 8

        for i in 0..<rockCount {
            let angle = Float(i) / Float(rockCount) * 2 * .pi
            let distance = Float.random(in: 5...12)

            let position = SIMD3<Float>(
                cos(angle) * distance,
                Float.random(in: -4 ... -1),
                sin(angle) * distance
            )

            let rockSize = Float.random(in: 0.5...2.0)
            let rock = createRock(size: rockSize, position: position)
            rootEntity.addChild(rock)
        }
    }

    private func createRock(size: Float, position: SIMD3<Float>) -> Entity {
        let mesh = MeshResource.generateSphere(radius: size)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.15, green: 0.12, blue: 0.1, alpha: 1.0))
        material.roughness = .init(floatLiteral: 0.95)

        let rock = ModelEntity(mesh: mesh, materials: [material])
        rock.name = "UnderwaterRock"
        rock.position = position

        // Random scale distortion for more natural shapes
        rock.scale = SIMD3<Float>(
            Float.random(in: 0.8...1.2),
            Float.random(in: 0.6...1.4),
            Float.random(in: 0.8...1.2)
        )

        return rock
    }

    private func setupLighting() {
        // Key light (sun-like)
        let sunLight = Entity()
        sunLight.components[DirectionalLightComponent.self] = DirectionalLightComponent(
            color: .init(red: 1.0, green: 0.95, blue: 0.8, alpha: 1.0),
            intensity: 2000,
            isRealWorldProxy: false
        )
        sunLight.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0))
        sunLight.name = "SunLight"
        rootEntity.addChild(sunLight)

        // Underglow for caustic-like effect
        let underGlow = Entity()
        underGlow.components[PointLightComponent.self] = PointLightComponent(
            color: .init(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0),
            intensity: 1000,
            attenuationRadius: 15
        )
        underGlow.position = SIMD3<Float>(0, -3, 0)
        underGlow.name = "UnderGlow"
        rootEntity.addChild(underGlow)
        underglowLight = underGlow
    }

    // MARK: - Look Protocol

    func activate() {
        animTime = 0
    }

    func deactivate() {
        // Nothing special needed
    }

    func update(time: Double, deltaTime: Double, params: WaterParams) {
        animTime = Float(time)

        // Animate water plane with gentle wave motion via transform
        updateWaterAnimation(params: params)

        // Animate underglow for caustic effect
        updateCausticGlow(time: animTime, params: params)

        // Update material properties
        updateWaterMaterial(params: params)
    }

    private func updateWaterAnimation(params: WaterParams) {
        guard let waterPlane = waterPlaneEntity else { return }

        // Simulate waves with entity transform oscillation
        let amplitude = Float(params.waveAmplitude) * 0.3
        let frequency = Float(params.waveFrequency)

        // Multi-frequency wave motion
        let wave1 = sin(animTime * frequency) * amplitude
        let wave2 = sin(animTime * frequency * 0.7 + 1.0) * amplitude * 0.5
        let tilt = sin(animTime * frequency * 0.3) * 0.02

        waterPlane.position.y = wave1 + wave2

        // Gentle tilt for wave feel
        waterPlane.orientation = simd_quatf(
            angle: tilt,
            axis: normalize(SIMD3<Float>(1, 0, 0.5))
        )
    }

    private func updateWaterMaterial(params: WaterParams) {
        guard let waterPlane = waterPlaneEntity,
              var material = waterPlane.model?.materials.first as? PhysicallyBasedMaterial else { return }

        // Update roughness based on params
        material.roughness = .init(floatLiteral: Float(params.roughness))

        // Animate color slightly based on time
        let colorShift = sin(animTime * 0.5) * 0.1
        let tint = params.causticTint
        material.baseColor = .init(tint: .init(
            red: CGFloat(0.15 + tint.x * 0.3 + colorShift),
            green: CGFloat(0.4 + tint.y * 0.2),
            blue: CGFloat(0.65 + tint.z * 0.1),
            alpha: 0.85
        ))

        waterPlane.model?.materials = [material]
    }

    private func updateCausticGlow(time: Float, params: WaterParams) {
        guard let glow = underglowLight else { return }

        // Animate caustic glow position
        let wanderX = sin(time * 0.5) * 3.0
        let wanderZ = cos(time * 0.7) * 3.0
        glow.position = SIMD3<Float>(wanderX, -3, wanderZ)

        // Pulse intensity
        let pulse = 800 + sin(time * 2.0) * 200
        if var light = glow.components[PointLightComponent.self] {
            light.intensity = pulse * Float(params.specular)

            // Tint based on params
            let tint = params.causticTint
            light.color = .init(
                red: CGFloat(tint.x),
                green: CGFloat(tint.y),
                blue: CGFloat(tint.z),
                alpha: 1.0
            )

            glow.components[PointLightComponent.self] = light
        }
    }

    func teardown() {
        rootEntity.removeFromParent()
    }
}
