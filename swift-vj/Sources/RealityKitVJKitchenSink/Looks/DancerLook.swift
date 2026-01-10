// DancerLook.swift
// RealityKitVJKitchenSink
//
// Character/dancer look with USDZ model loading.
// Reference: https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file

import RealityKit
import Foundation
import simd

/// Character look with USDZ model, 3-point lighting, and animation
final class DancerLook: Look {
    typealias Params = DancerParams

    let rootEntity: Entity

    private var characterEntity: Entity?
    private var floorEntity: Entity?
    private var spotlightEntities: [Entity] = []

    private let context: LookContext

    // Animation state
    private var rotationAngle: Float = 0
    private var bobPhase: Float = 0
    private var baseScale: Float = 1.0

    // Loading state
    private var isLoading = false
    private var loadingFailed = false

    // Default USDZ URL (Apple's sample robot)
    private static let defaultUSDZURL = URL(string: "https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz")!

    required init(context: LookContext) {
        self.context = context
        self.rootEntity = Entity()
        rootEntity.name = "DancerLook"

        setupStage()
        setupLighting()
        loadCharacter()
    }

    // MARK: - Setup

    private func setupStage() {
        // Create a stage floor
        let floorMesh = MeshResource.generatePlane(width: 10, depth: 10)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0))
        material.metallic = .init(floatLiteral: 0.7)
        material.roughness = .init(floatLiteral: 0.3)

        let floor = ModelEntity(mesh: floorMesh, materials: [material])
        floor.name = "StageFloor"
        floor.position = SIMD3<Float>(0, 0, 0)

        // Enable shadow receiving
        floor.components[GroundingShadowComponent.self] = GroundingShadowComponent(castsShadow: false)

        rootEntity.addChild(floor)
        floorEntity = floor

        // Add a circular platform
        let platformMesh = MeshResource.generateCylinder(height: 0.1, radius: 2.0)

        var platformMaterial = PhysicallyBasedMaterial()
        platformMaterial.baseColor = .init(tint: .init(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0))
        platformMaterial.metallic = .init(floatLiteral: 0.8)
        platformMaterial.roughness = .init(floatLiteral: 0.2)

        let platform = ModelEntity(mesh: platformMesh, materials: [platformMaterial])
        platform.name = "Platform"
        platform.position = SIMD3<Float>(0, 0.05, 0)

        rootEntity.addChild(platform)
    }

    private func setupLighting() {
        // 3-point lighting setup for dramatic character presentation

        // Key light (main illumination)
        let keyLight = Entity()
        keyLight.components[SpotLightComponent.self] = SpotLightComponent(
            color: .init(red: 1.0, green: 0.95, blue: 0.9, alpha: 1.0),
            intensity: 5000,
            innerAngleInDegrees: 20,
            outerAngleInDegrees: 40,
            attenuationRadius: 20
        )
        keyLight.position = SIMD3<Float>(3, 5, 3)
        keyLight.look(at: SIMD3<Float>(0, 1, 0), from: keyLight.position, relativeTo: nil)
        keyLight.name = "KeyLight"
        rootEntity.addChild(keyLight)
        spotlightEntities.append(keyLight)

        // Fill light (soften shadows)
        let fillLight = Entity()
        fillLight.components[SpotLightComponent.self] = SpotLightComponent(
            color: .init(red: 0.6, green: 0.7, blue: 1.0, alpha: 1.0),
            intensity: 2000,
            innerAngleInDegrees: 30,
            outerAngleInDegrees: 50,
            attenuationRadius: 15
        )
        fillLight.position = SIMD3<Float>(-4, 3, 2)
        fillLight.look(at: SIMD3<Float>(0, 1, 0), from: fillLight.position, relativeTo: nil)
        fillLight.name = "FillLight"
        rootEntity.addChild(fillLight)
        spotlightEntities.append(fillLight)

        // Rim/back light (separation from background)
        let rimLight = Entity()
        rimLight.components[SpotLightComponent.self] = SpotLightComponent(
            color: .init(red: 1.0, green: 0.8, blue: 0.6, alpha: 1.0),
            intensity: 3000,
            innerAngleInDegrees: 15,
            outerAngleInDegrees: 35,
            attenuationRadius: 15
        )
        rimLight.position = SIMD3<Float>(0, 4, -4)
        rimLight.look(at: SIMD3<Float>(0, 1, 0), from: rimLight.position, relativeTo: nil)
        rimLight.name = "RimLight"
        rootEntity.addChild(rimLight)
        spotlightEntities.append(rimLight)
    }

    private func loadCharacter() {
        guard !isLoading else { return }
        isLoading = true

        // First try to load from bundle resources
        if let bundleURL = Bundle.main.url(forResource: "toy_robot_vintage", withExtension: "usdz") {
            loadFromURL(bundleURL)
            return
        }

        // Try to load from app support directory (cached download)
        let cachedPath = getCachedModelPath()
        if FileManager.default.fileExists(atPath: cachedPath.path) {
            loadFromURL(cachedPath)
            return
        }

        // Create placeholder and attempt download
        createPlaceholderCharacter()
        downloadModel()
    }

    private func getCachedModelPath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("RealityKitVJKitchenSink")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("toy_robot_vintage.usdz")
    }

    private func loadFromURL(_ url: URL) {
        Task { @MainActor in
            do {
                let entity = try await Entity.load(contentsOf: url)

                // Remove placeholder if present
                if let existing = characterEntity {
                    existing.removeFromParent()
                }

                // Configure loaded model
                entity.name = "Character"
                entity.position = SIMD3<Float>(0, 0.1, 0)

                // Calculate and store base scale
                let bounds = entity.visualBounds(relativeTo: nil)
                let maxDimension = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                baseScale = 2.0 / max(maxDimension, 0.1)  // Fit to ~2 units
                entity.scale = SIMD3<Float>(repeating: baseScale)

                // Center on platform
                let centerOffset = (bounds.min + bounds.max) / 2
                entity.position.y -= centerOffset.y * baseScale

                // Enable shadows
                entity.components[GroundingShadowComponent.self] = GroundingShadowComponent(castsShadow: true)

                rootEntity.addChild(entity)
                characterEntity = entity

                // Start any available animations
                startAnimations(on: entity)

                isLoading = false

            } catch {
                print("Failed to load USDZ: \(error)")
                loadingFailed = true
                isLoading = false
            }
        }
    }

    private func downloadModel() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: DancerLook.defaultUSDZURL)

                // Save to cache
                let cachedPath = getCachedModelPath()
                try data.write(to: cachedPath)

                // Load the downloaded model
                await MainActor.run {
                    loadFromURL(cachedPath)
                }

            } catch {
                print("Failed to download USDZ: \(error)")
                await MainActor.run {
                    loadingFailed = true
                    isLoading = false
                }
            }
        }
    }

    private func createPlaceholderCharacter() {
        // Create a simple humanoid placeholder while loading
        let torsoMesh = MeshResource.generateBox(size: SIMD3<Float>(0.4, 0.6, 0.2))
        let headMesh = MeshResource.generateSphere(radius: 0.15)
        let limbMesh = MeshResource.generateCylinder(height: 0.5, radius: 0.05)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.5, green: 0.5, blue: 0.55, alpha: 1.0))
        material.metallic = .init(floatLiteral: 0.3)
        material.roughness = .init(floatLiteral: 0.7)

        let placeholder = Entity()
        placeholder.name = "PlaceholderCharacter"

        // Torso
        let torso = ModelEntity(mesh: torsoMesh, materials: [material])
        torso.position = SIMD3<Float>(0, 1.0, 0)
        placeholder.addChild(torso)

        // Head
        let head = ModelEntity(mesh: headMesh, materials: [material])
        head.position = SIMD3<Float>(0, 1.5, 0)
        placeholder.addChild(head)

        // Arms
        let leftArm = ModelEntity(mesh: limbMesh, materials: [material])
        leftArm.position = SIMD3<Float>(-0.35, 1.0, 0)
        leftArm.orientation = simd_quatf(angle: .pi / 6, axis: SIMD3<Float>(0, 0, 1))
        placeholder.addChild(leftArm)

        let rightArm = ModelEntity(mesh: limbMesh, materials: [material])
        rightArm.position = SIMD3<Float>(0.35, 1.0, 0)
        rightArm.orientation = simd_quatf(angle: -.pi / 6, axis: SIMD3<Float>(0, 0, 1))
        placeholder.addChild(rightArm)

        // Legs
        let leftLeg = ModelEntity(mesh: limbMesh, materials: [material])
        leftLeg.position = SIMD3<Float>(-0.1, 0.35, 0)
        placeholder.addChild(leftLeg)

        let rightLeg = ModelEntity(mesh: limbMesh, materials: [material])
        rightLeg.position = SIMD3<Float>(0.1, 0.35, 0)
        placeholder.addChild(rightLeg)

        placeholder.position = SIMD3<Float>(0, 0.1, 0)
        baseScale = 1.0

        rootEntity.addChild(placeholder)
        characterEntity = placeholder
    }

    private func startAnimations(on entity: Entity) {
        // Find and play any available animations
        let animations = entity.availableAnimations
        for animation in animations {
            entity.playAnimation(animation.repeat())
        }
    }

    // MARK: - Look Protocol

    func activate() {
        rotationAngle = 0
        bobPhase = 0
    }

    func deactivate() {
        // Stop animations
        characterEntity?.stopAllAnimations()
    }

    func update(time: Double, deltaTime: Double, params: DancerParams) {
        let t = Float(time)
        let dt = Float(deltaTime)

        // Update rotation
        rotationAngle += dt * Float(params.rotationSpeed)

        // Update bob animation
        bobPhase += dt * Float(params.animationSpeed) * 2.0

        // Apply transforms to character
        updateCharacterTransform(params: params)

        // Update lighting intensity
        updateLighting(intensity: Float(params.lightingIntensity))

        // Update floor reflectivity
        updateFloor(reflectivity: Float(params.floorReflectivity))
    }

    private func updateCharacterTransform(params: DancerParams) {
        guard let character = characterEntity else { return }

        // Rotation
        character.orientation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))

        // Bob animation (idle movement)
        let bobOffset = sin(bobPhase) * 0.1
        let baseY: Float = 0.1
        character.position.y = baseY + bobOffset

        // Scale pulse
        let scalePulse = 1.0 + sin(bobPhase * 1.5) * Float(params.scalePulse)
        let finalScale = baseScale * scalePulse
        character.scale = SIMD3<Float>(repeating: finalScale)
    }

    private func updateLighting(intensity: Float) {
        for (i, light) in spotlightEntities.enumerated() {
            if var spotlight = light.components[SpotLightComponent.self] {
                // Base intensities for each light
                let baseIntensities: [Float] = [5000, 2000, 3000]  // key, fill, rim
                spotlight.intensity = baseIntensities[i] * intensity

                light.components[SpotLightComponent.self] = spotlight
            }
        }
    }

    private func updateFloor(reflectivity: Float) {
        guard let floor = floorEntity as? ModelEntity else { return }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0))
        material.metallic = .init(floatLiteral: Double(0.3 + reflectivity * 0.6))
        material.roughness = .init(floatLiteral: Double(0.6 - reflectivity * 0.4))

        floor.model?.materials = [material]
    }

    func teardown() {
        characterEntity?.stopAllAnimations()
        rootEntity.removeFromParent()
    }
}
