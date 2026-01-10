// LaserRigLook.swift - Array of emissive beam meshes with bloom/glow
// Demonstrates emissive materials and post-processing bloom dependency

import Foundation
import RealityKit
import simd
import AppKit

final class LaserRigLook: Look {
    private let context: LookContext
    private var rootEntity: Entity!
    private var beamEntities: [ModelEntity] = []
    private var params: LaserRigParams?
    private var elapsedTime: Float = 0
    
    required init(context: LookContext) {
        self.context = context
    }
    
    func makeRootEntity() -> Entity {
        let anchor = AnchorEntity()
        
        // Create initial set of laser beams
        createBeams(count: 12, parent: anchor)
        
        rootEntity = anchor
        return anchor
    }
    
    func update(dt: Double, time: Double, globalParams: GlobalParams) {
        guard let params = params else { return }
        
        elapsedTime += Float(dt * globalParams.timeScale)
        
        // Update beam count if changed
        if beamEntities.count != params.beamCount {
            // Remove old beams
            beamEntities.forEach { $0.removeFromParent() }
            beamEntities.removeAll()
            
            // Create new beams
            createBeams(count: params.beamCount, parent: rootEntity)
        }
        
        // Animate beams (sweep/rotation)
        for (index, beam) in beamEntities.enumerated() {
            let offset = Float(index) / Float(beamEntities.count) * .pi * 2
            let angle = elapsedTime * Float(params.beamSweepSpeed) + offset
            
            // Position in circle
            let radius: Float = 3.0
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            beam.position = SIMD3<Float>(x, 0, z)
            
            // Point toward center (or sweep outward)
            beam.look(at: SIMD3<Float>(0, 0, 0), from: beam.position, relativeTo: nil)
            
            // Color cycling
            let hue = Float(fmod(time * params.colorCycleSpeed * 0.2 + Double(offset), 1.0))
            let color = NSColor(hue: CGFloat(hue), saturation: 1.0, brightness: 1.0, alpha: 1.0)
            
            if var material = beam.model?.materials.first as? UnlitMaterial {
                material.color = .init(tint: color)
                beam.model?.materials = [material]
            }
        }
    }
    
    func teardown() {
        beamEntities.forEach { $0.removeFromParent() }
        beamEntities.removeAll()
        rootEntity?.removeFromParent()
        rootEntity = nil
    }
    
    // MARK: - Private
    
    private func createBeams(count: Int, parent: Entity) {
        for i in 0..<count {
            let beam = createBeam(index: i, total: count)
            parent.addChild(beam)
            beamEntities.append(beam)
        }
    }
    
    private func createBeam(index: Int, total: Int) -> ModelEntity {
        // Thin cylinder for laser beam
        let beamMesh = MeshResource.generateCylinder(height: 5.0, radius: 0.02)
        
        // Emissive unlit material (requires bloom in post-process to glow)
        var material = UnlitMaterial()
        material.color = .init(tint: .red) // Will be updated in update()
        
        let beam = ModelEntity(mesh: beamMesh, materials: [material])
        
        // Initial position in circle
        let angle = Float(index) / Float(total) * .pi * 2
        let radius: Float = 3.0
        let x = cos(angle) * radius
        let z = sin(angle) * radius
        beam.position = SIMD3<Float>(x, 0, z)
        
        return beam
    }
    
    // Public setter for params
    func setParams(_ params: LaserRigParams) {
        self.params = params
    }
}
