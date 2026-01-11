// SpaceDomeLook.swift - Inverted sphere sky dome with starfield
// Reference: https://developer.apple.com/documentation/realitykit/particleemittercomponent

import Foundation
import RealityKit
import simd
import AppKit

final class SpaceDomeLook: Look {
    private let context: LookContext
    private var rootEntity: Entity!
    private var domeEntity: ModelEntity!
    private var starEmitter: Entity!
    private var params: SpaceDomeParams?
    
    required init(context: LookContext) {
        self.context = context
    }
    
    func makeRootEntity() -> Entity {
        let anchor = AnchorEntity()
        
        // Create inverted sky dome (large sphere viewed from inside)
        let domeMesh = MeshResource.generateSphere(radius: 50)
        
        // Use unlit material with gradient for space sky
        var domeMaterial = UnlitMaterial()
        domeMaterial.color = .init(tint: .black)
        
        domeEntity = ModelEntity(mesh: domeMesh, materials: [domeMaterial])
        
        // Invert normals by scaling negative (to see inside)
        domeEntity.scale = SIMD3<Float>(-1, -1, -1)
        
        anchor.addChild(domeEntity)
        
        // Create star particle emitter
        starEmitter = createStarfield()
        anchor.addChild(starEmitter)
        
        rootEntity = anchor
        return anchor
    }
    
    func update(dt: Double, time: Double, globalParams: GlobalParams) {
        guard let params = params else {
            // Lazy-init params on first update (after MainActor available)
            return
        }
        
        // Time-based hue shift for dome color
        let hue = Float(fmod(time * params.domeHueSpeed * 0.1, 1.0))
        let skyColor = NSColor(hue: CGFloat(hue), saturation: 0.3, brightness: 0.15, alpha: 1.0)
        
        if var material = domeEntity.model?.materials.first as? UnlitMaterial {
            material.color = .init(tint: skyColor)
            domeEntity.model?.materials = [material]
        }
        
        // Subtle rotation for stars
        starEmitter.transform.rotation *= simd_quatf(
            angle: Float(dt * params.domeHueSpeed * 0.05),
            axis: SIMD3<Float>(0, 1, 0)
        )
    }
    
    func teardown() {
        rootEntity?.removeFromParent()
        domeEntity = nil
        starEmitter = nil
        rootEntity = nil
    }
    
    // MARK: - Private
    
    private func createStarfield() -> Entity {
        let emitterEntity = Entity()
        
        // Create particle emitter component for stars
        var particles = ParticleEmitterComponent()
        
        // Emit from a spherical volume
        particles.emitterShape = .sphere
        particles.emitterShapeSize = SIMD3<Float>(40, 40, 40)
        
        // Emit a burst at start, then occasional new stars
        particles.birthRate = 5
        particles.burstCount = 500
        particles.emitterDuration = 10.0
        
        // Particle lifetime
        particles.mainEmitter.lifeSpan = 100.0
        particles.mainEmitter.lifeSpanVariation = 20.0
        
        // Size (stars are points)
        particles.mainEmitter.size = 0.02
        particles.mainEmitter.sizeVariation = 0.01
        
        // Color (white with slight variation)
        particles.mainEmitter.color = .evolving(
            start: .constant(.white),
            end: .constant(.white)
        )
        
        // No velocity (stationary stars)
        particles.speed = 0.0
        
        emitterEntity.components.set(particles)
        
        return emitterEntity
    }
    
    // Public setter for params (called from coordinator)
    func setParams(_ params: SpaceDomeParams) {
        self.params = params
    }
}
