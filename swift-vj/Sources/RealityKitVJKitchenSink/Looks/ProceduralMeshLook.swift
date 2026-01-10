// ProceduralMeshLook.swift - Dynamic ribbon/tube using LowLevelMesh
// Reference: https://developer.apple.com/documentation/realitykit/lowlevelmesh

import Foundation
import RealityKit
import simd

final class ProceduralMeshLook: Look {
    private let context: LookContext
    private var rootEntity: Entity!
    private var ribbonEntity: ModelEntity!
    private var params: ProceduralMeshParams?
    private var elapsedTime: Float = 0
    
    // LowLevelMesh resources
    private var lowLevelMesh: LowLevelMesh?
    
    required init(context: LookContext) {
        self.context = context
    }
    
    func makeRootEntity() -> Entity {
        let anchor = AnchorEntity()
        
        // Create initial ribbon mesh
        createRibbon(parent: anchor)
        
        rootEntity = anchor
        return anchor
    }
    
    func update(dt: Double, time: Double, globalParams: GlobalParams) {
        guard let params = params else { return }
        
        elapsedTime += Float(dt * globalParams.timeScale)
        
        // Update ribbon mesh with procedural deformation
        updateRibbonMesh(params: params, time: elapsedTime)
        
        // Color gradient cycling
        let hue = Float(fmod(time * params.colorGradientSpeed * 0.2, 1.0))
        let color = UIColor(hue: CGFloat(hue), saturation: 0.8, brightness: 1.0, alpha: 1.0)
        
        if var material = ribbonEntity.model?.materials.first as? UnlitMaterial {
            material.color = .init(tint: color)
            ribbonEntity.model?.materials = [material]
        }
    }
    
    func teardown() {
        ribbonEntity?.removeFromParent()
        rootEntity?.removeFromParent()
        lowLevelMesh = nil
        ribbonEntity = nil
        rootEntity = nil
    }
    
    // MARK: - Private
    
    private func createRibbon(parent: Entity) {
        // Create initial ribbon with simple geometry
        // Full LowLevelMesh implementation would update this every frame
        
        let segments = 50
        let thickness: Float = 0.05
        
        // Generate tube/ribbon mesh
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Create a simple tube along a path
        let sidesPerSegment = 8
        
        for i in 0..<segments {
            let t = Float(i) / Float(segments)
            let angle = t * .pi * 4 // Multiple loops
            
            // Center path (will be deformed by noise)
            let centerX = cos(angle) * 2.0
            let centerY = sin(angle * 2) * 1.0
            let centerZ = sin(angle) * 2.0
            let center = SIMD3<Float>(centerX, centerY, centerZ)
            
            // Create ring around path
            for j in 0..<sidesPerSegment {
                let ringAngle = Float(j) / Float(sidesPerSegment) * .pi * 2
                let offset = SIMD3<Float>(
                    cos(ringAngle) * thickness,
                    sin(ringAngle) * thickness,
                    0
                )
                
                positions.append(center + offset)
                normals.append(normalize(offset))
            }
        }
        
        // Generate indices for triangle strip
        for i in 0..<(segments - 1) {
            for j in 0..<sidesPerSegment {
                let current = UInt32(i * sidesPerSegment + j)
                let next = UInt32(i * sidesPerSegment + (j + 1) % sidesPerSegment)
                let currentNext = UInt32((i + 1) * sidesPerSegment + j)
                let nextNext = UInt32((i + 1) * sidesPerSegment + (j + 1) % sidesPerSegment)
                
                // Two triangles per quad
                indices.append(contentsOf: [current, next, currentNext])
                indices.append(contentsOf: [next, nextNext, currentNext])
            }
        }
        
        // Create mesh resource
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        
        do {
            let mesh = try MeshResource.generate(from: [descriptor])
            
            var material = UnlitMaterial()
            material.color = .init(tint: .magenta)
            
            ribbonEntity = ModelEntity(mesh: mesh, materials: [material])
            parent.addChild(ribbonEntity)
        } catch {
            print("[ProceduralMesh] Failed to create mesh: \(error)")
        }
    }
    
    private func updateRibbonMesh(params: ProceduralMeshParams, time: Float) {
        // In a full implementation, this would use LowLevelMesh to update vertices
        // For now, we'll animate via transform
        
        // Simple rotation to show it's alive
        ribbonEntity.orientation = simd_quatf(
            angle: time * 0.3,
            axis: SIMD3<Float>(0, 1, 0)
        )
        
        // Note: Full implementation would:
        // 1. Create LowLevelMesh with updateable vertex buffer
        // 2. Every frame, update vertex positions with noise-based deformation
        // 3. Call mesh.replace(positions: newPositions)
        // Reference: https://developer.apple.com/documentation/realitykit/lowlevelmesh
    }
    
    // Public setter for params
    func setParams(_ params: ProceduralMeshParams) {
        self.params = params
    }
}
