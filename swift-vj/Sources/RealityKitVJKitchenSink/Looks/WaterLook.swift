// WaterLook.swift - Large plane with CustomMaterial for animated waves
// Reference: https://developer.apple.com/documentation/realitykit/custommaterial
// Reference: https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials

import Foundation
import RealityKit
import Metal
import simd

final class WaterLook: Look {
    private let context: LookContext
    private var rootEntity: Entity!
    private var waterPlane: ModelEntity!
    private var params: WaterParams?
    private var elapsedTime: Float = 0
    
    required init(context: LookContext) {
        self.context = context
    }
    
    func makeRootEntity() -> Entity {
        let anchor = AnchorEntity()
        
        // Create large plane for water surface
        let planeMesh = MeshResource.generatePlane(width: 20, depth: 20, cornerRadius: 0)
        
        // Create custom material with water shader
        do {
            var material = try createWaterMaterial()
            waterPlane = ModelEntity(mesh: planeMesh, materials: [material])
            waterPlane.position = SIMD3<Float>(0, 0, 0)
            
            anchor.addChild(waterPlane)
        } catch {
            print("[WaterLook] Failed to create material: \(error)")
            // Fallback to simple material
            var fallback = SimpleMaterial()
            fallback.color = .init(tint: .cyan.withAlphaComponent(0.6), texture: nil)
            fallback.metallic = .init(floatLiteral: 0.8)
            fallback.roughness = .init(floatLiteral: 0.2)
            waterPlane = ModelEntity(mesh: planeMesh, materials: [fallback])
            anchor.addChild(waterPlane)
        }
        
        // Add directional light for specular highlights
        let light = DirectionalLight()
        light.light.intensity = 5000
        light.light.color = .white
        light.orientation = simd_quatf(angle: .pi/4, axis: SIMD3<Float>(1, -1, 0))
        anchor.addChild(light)
        
        rootEntity = anchor
        return anchor
    }
    
    func update(dt: Double, time: Double, globalParams: GlobalParams) {
        guard let params = params else { return }
        
        elapsedTime += Float(dt * globalParams.timeScale)
        
        // Update custom material parameters via CustomMaterial
        if var material = waterPlane.model?.materials.first as? CustomMaterial {
            // Update custom parameters for wave animation
            // Note: This requires proper shader setup with custom parameters
            // For now we'll do a simple position offset
            waterPlane.position.y = sin(elapsedTime * 0.5) * 0.1
        }
    }
    
    func teardown() {
        rootEntity?.removeFromParent()
        waterPlane = nil
        rootEntity = nil
    }
    
    // MARK: - Private
    
    private func createWaterMaterial() throws -> CustomMaterial {
        // Create base material
        var baseMaterial = PhysicallyBasedMaterial()
        baseMaterial.baseColor = .init(tint: .cyan.withAlphaComponent(0.6))
        baseMaterial.metallic = .init(floatLiteral: 0.1)
        baseMaterial.roughness = .init(floatLiteral: 0.3)
        
        // Create custom material with geometry modifier for waves
        let customMaterial = try CustomMaterial(from: baseMaterial, geometryModifier: { geometry in
            // Metal shader for vertex displacement
            // Note: This is a simplified approach - full implementation would use
            // CustomMaterial with proper Metal shader functions
            return """
            // Simple wave displacement
            float time = uniforms.time;
            float wave = sin(geometry.position().x * 2.0 + time) * 
                        cos(geometry.position().z * 2.0 + time) * 0.1;
            geometry.position().y += wave;
            """
        })
        
        return customMaterial
    }
    
    // Public setter for params
    func setParams(_ params: WaterParams) {
        self.params = params
    }
}
