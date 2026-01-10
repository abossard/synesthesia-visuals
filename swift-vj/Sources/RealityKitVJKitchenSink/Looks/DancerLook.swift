// DancerLook.swift - USDZ character with animation and 3-point lighting
// Reference: https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file
// Reference: https://developer.apple.com/augmented-reality/quick-look/

import Foundation
import RealityKit
import simd

final class DancerLook: Look {
    private let context: LookContext
    private var rootEntity: Entity!
    private var characterEntity: Entity?
    private var floorPlane: ModelEntity!
    private var lights: [Entity] = []
    private var params: DancerParams?
    private var elapsedTime: Float = 0
    private var baseScale: Float = 1.0
    
    required init(context: LookContext) {
        self.context = context
    }
    
    func makeRootEntity() -> Entity {
        let anchor = AnchorEntity()
        
        // Try to load USDZ model
        loadCharacter(into: anchor)
        
        // Create floor plane with shadow receiver
        let floorMesh = MeshResource.generatePlane(width: 10, depth: 10)
        var floorMaterial = SimpleMaterial()
        floorMaterial.color = .init(tint: .gray.withAlphaComponent(0.3))
        floorMaterial.metallic = .init(floatLiteral: 0.0)
        floorMaterial.roughness = .init(floatLiteral: 0.8)
        
        floorPlane = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floorPlane.position = SIMD3<Float>(0, -1, 0)
        anchor.addChild(floorPlane)
        
        // Create 3-point lighting
        setupLighting(parent: anchor)
        
        rootEntity = anchor
        return anchor
    }
    
    func update(dt: Double, time: Double, globalParams: GlobalParams) {
        guard let params = params else { return }
        guard let character = characterEntity else { return }
        
        elapsedTime += Float(dt * globalParams.timeScale * params.animationSpeed)
        
        // Animate character (idle bob or spin if no animations)
        // Check if character has animations
        if character.availableAnimations.isEmpty {
            // Manual animation: gentle bob + spin
            let bobHeight = sin(elapsedTime * 2.0) * 0.1
            let spinAngle = elapsedTime * 0.5
            
            character.position.y = bobHeight
            character.orientation = simd_quatf(angle: spinAngle, axis: SIMD3<Float>(0, 1, 0))
        } else {
            // Play first available animation
            // Note: Proper implementation would play all animations or specific ones
            if let animation = character.availableAnimations.first {
                character.playAnimation(animation.repeat())
            }
        }
        
        // Scale pulse
        let pulse = 1.0 + sin(elapsedTime * 3.0) * Float(params.scalePulse)
        character.scale = SIMD3<Float>(repeating: baseScale * pulse)
        
        // Update lighting intensity
        for light in lights {
            if let pointLight = light.components[PointLightComponent.self] {
                var updated = pointLight
                updated.light.intensity = Float(params.lightingIntensity) * 1000
                light.components[PointLightComponent.self] = updated
            }
        }
        
        // Update floor reflectivity
        if var material = floorPlane.model?.materials.first as? SimpleMaterial {
            material.metallic = .init(floatLiteral: params.floorReflectivity)
            floorPlane.model?.materials = [material]
        }
    }
    
    func teardown() {
        characterEntity?.removeFromParent()
        lights.forEach { $0.removeFromParent() }
        lights.removeAll()
        rootEntity?.removeFromParent()
        characterEntity = nil
        floorPlane = nil
        rootEntity = nil
    }
    
    // MARK: - Private
    
    private func loadCharacter(into parent: Entity) {
        // Try to load from Resources/Models/toy_robot_vintage.usdz
        // Reference: https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz
        
        if let url = Bundle.module.url(forResource: "toy_robot_vintage", withExtension: "usdz", subdirectory: "Models") {
            Entity.loadAsync(contentsOf: url).sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[DancerLook] Failed to load USDZ: \(error)")
                        self.createFallbackCharacter(parent: parent)
                    }
                },
                receiveValue: { entity in
                    entity.position = SIMD3<Float>(0, 0, 0)
                    self.baseScale = 1.0
                    entity.scale = SIMD3<Float>(repeating: self.baseScale)
                    parent.addChild(entity)
                    self.characterEntity = entity
                    print("[DancerLook] USDZ loaded successfully")
                }
            ).store(in: &cancellables)
        } else {
            print("[DancerLook] USDZ not found, using fallback")
            createFallbackCharacter(parent: parent)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func createFallbackCharacter(parent: Entity) {
        // Simple capsule character as fallback
        let bodyMesh = MeshResource.generateBox(width: 0.5, height: 1.5, depth: 0.3)
        let headMesh = MeshResource.generateSphere(radius: 0.25)
        
        var bodyMaterial = SimpleMaterial()
        bodyMaterial.color = .init(tint: .orange)
        bodyMaterial.metallic = .init(floatLiteral: 0.3)
        bodyMaterial.roughness = .init(floatLiteral: 0.6)
        
        let body = ModelEntity(mesh: bodyMesh, materials: [bodyMaterial])
        let head = ModelEntity(mesh: headMesh, materials: [bodyMaterial])
        head.position = SIMD3<Float>(0, 1.0, 0)
        
        body.addChild(head)
        
        baseScale = 1.0
        body.scale = SIMD3<Float>(repeating: baseScale)
        parent.addChild(body)
        characterEntity = body
    }
    
    private func setupLighting(parent: Entity) {
        // 3-point lighting setup
        
        // Key light (main, front-right)
        let keyLight = Entity()
        var keyComponent = PointLightComponent()
        keyComponent.light.intensity = 1000
        keyComponent.light.color = .white
        keyLight.components.set(keyComponent)
        keyLight.position = SIMD3<Float>(2, 2, 2)
        parent.addChild(keyLight)
        lights.append(keyLight)
        
        // Fill light (softer, front-left)
        let fillLight = Entity()
        var fillComponent = PointLightComponent()
        fillComponent.light.intensity = 500
        fillComponent.light.color = .white
        fillLight.components.set(fillComponent)
        fillLight.position = SIMD3<Float>(-2, 1, 2)
        parent.addChild(fillLight)
        lights.append(fillLight)
        
        // Back light (rim light)
        let backLight = Entity()
        var backComponent = PointLightComponent()
        backComponent.light.intensity = 700
        backComponent.light.color = .cyan
        backLight.components.set(backComponent)
        backLight.position = SIMD3<Float>(0, 1, -3)
        parent.addChild(backLight)
        lights.append(backLight)
    }
    
    // Public setter for params
    func setParams(_ params: DancerParams) {
        self.params = params
    }
}

import Combine
