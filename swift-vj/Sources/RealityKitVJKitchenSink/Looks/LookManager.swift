// LookManager.swift - Manages switching between looks cleanly
// Deep module pattern: hides complexity of entity lifecycle

import Foundation
import RealityKit

@MainActor
final class LookManager {
    // MARK: - Properties
    
    private let context: LookContext
    private var currentLook: Look?
    private var currentRootEntity: Entity?
    private let scene: RealityKit.Scene
    
    var currentLookType: LookType?
    
    // MARK: - Init
    
    init(scene: RealityKit.Scene, context: LookContext) {
        self.scene = scene
        self.context = context
    }
    
    // MARK: - Look Switching
    
    /// Switch to a new look type, cleanly tearing down the current one
    func switchTo(_ lookType: LookType) {
        // Teardown current look if any
        if let current = currentLook {
            current.teardown()
        }
        
        // Remove current root entity from scene
        if let root = currentRootEntity {
            scene.removeAnchor(root as! AnchorEntity)
        }
        
        // Create new look
        let newLook = createLook(type: lookType)
        let newRoot = newLook.makeRootEntity()
        
        // Add to scene
        if let anchor = newRoot as? AnchorEntity {
            scene.addAnchor(anchor)
        } else {
            // Wrap in anchor if not already
            let anchor = AnchorEntity()
            anchor.addChild(newRoot)
            scene.addAnchor(anchor)
        }
        
        // Update state
        currentLook = newLook
        currentRootEntity = newRoot
        currentLookType = lookType
        
        print("[LookManager] Switched to: \(lookType.displayName)")
    }
    
    /// Update the current look
    func update(dt: Double, time: Double, globalParams: GlobalParams) {
        currentLook?.update(dt: dt, time: time, globalParams: globalParams)
    }
    
    /// Teardown everything
    func teardownAll() {
        currentLook?.teardown()
        if let root = currentRootEntity {
            scene.removeAnchor(root as! AnchorEntity)
        }
        currentLook = nil
        currentRootEntity = nil
        currentLookType = nil
    }
    
    // MARK: - Factory
    
    private func createLook(type: LookType) -> Look {
        switch type {
        case .spaceDome:
            return SpaceDomeLook(context: context)
        case .water:
            return WaterLook(context: context)
        case .laserRig:
            return LaserRigLook(context: context)
        case .dancer:
            return DancerLook(context: context)
        case .proceduralMesh:
            return ProceduralMeshLook(context: context)
        }
    }
}
