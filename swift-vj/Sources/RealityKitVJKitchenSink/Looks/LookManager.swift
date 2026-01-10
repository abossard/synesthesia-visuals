// LookManager.swift
// RealityKitVJKitchenSink
//
// Manages look lifecycle and transitions.

import RealityKit
import Metal

/// Manages visual looks and handles transitions between them
final class LookManager {
    private weak var arView: ARView?
    private let device: MTLDevice

    private var currentLook: AnyLook?
    private var lookAnchor: AnchorEntity?

    private(set) var currentLookType: LookType?

    init(arView: ARView, device: MTLDevice) {
        self.arView = arView
        self.device = device

        // Create a dedicated anchor for looks
        lookAnchor = AnchorEntity(world: .zero)
        arView.scene.anchors.append(lookAnchor!)
    }

    /// Switch to a new look
    func switchToLook(_ lookType: LookType) {
        guard lookType != currentLookType else { return }

        // Deactivate and teardown current look
        if let currentLook = currentLook {
            currentLook.deactivate()
            currentLook.teardown()
        }

        // Create new look
        guard let arView = arView else { return }

        let context = LookContext(
            arView: arView,
            device: device,
            scene: arView.scene
        )

        let newLook = createLook(type: lookType, context: context)
        currentLook = newLook
        currentLookType = lookType

        // Add to scene
        if let anchor = lookAnchor {
            // Remove old children
            for child in anchor.children {
                child.removeFromParent()
            }
            // Add new look's root
            anchor.addChild(newLook.rootEntity)
        }

        // Activate
        newLook.activate()
    }

    /// Update the current look
    func update(time: Double, deltaTime: Double, params: any LookParams) {
        currentLook?.update(time: time, deltaTime: deltaTime, params: params)
    }

    /// Create a look instance for the given type
    private func createLook(type: LookType, context: LookContext) -> AnyLook {
        switch type {
        case .spaceDome:
            let look = SpaceDomeLook(context: context)
            return AnyLook(look, type: type)
        case .water:
            let look = WaterLook(context: context)
            return AnyLook(look, type: type)
        case .laserRig:
            let look = LaserRigLook(context: context)
            return AnyLook(look, type: type)
        case .dancer:
            let look = DancerLook(context: context)
            return AnyLook(look, type: type)
        case .proceduralMesh:
            let look = ProceduralMeshLook(context: context)
            return AnyLook(look, type: type)
        }
    }

    /// Clean up all resources
    func teardown() {
        currentLook?.teardown()
        currentLook = nil
        currentLookType = nil
        lookAnchor?.removeFromParent()
    }
}
