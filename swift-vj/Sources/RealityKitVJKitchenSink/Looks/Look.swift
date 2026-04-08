// Look.swift
// RealityKitVJKitchenSink
//
// Protocol defining a visual "Look" - a self-contained scene configuration.
// Each Look manages its own entities, materials, and update logic.

import RealityKit
import Metal
import simd

/// Context provided to looks for initialization
@MainActor
struct LookContext {
    let arView: ARView
    let device: MTLDevice
    let scene: RealityKit.Scene

    /// Get or create an anchor for the look's entities
    func makeAnchor() -> AnchorEntity {
        let anchor = AnchorEntity(world: .zero)
        return anchor
    }
}

/// Protocol defining a visual look/scene
@MainActor
protocol Look: AnyObject {
    /// The type of parameters this look uses
    associatedtype Params: LookParams

    /// Initialize with context
    init(context: LookContext)

    /// The root entity containing all look-specific entities
    var rootEntity: Entity { get }

    /// Called when the look is activated
    func activate()

    /// Called when the look is deactivated (before removal)
    func deactivate()

    /// Called each frame to update the look
    /// - Parameters:
    ///   - time: Accumulated animation time (respects pause/time scale)
    ///   - deltaTime: Time since last frame (scaled)
    ///   - params: Current parameters for this look
    func update(time: Double, deltaTime: Double, params: Params)

    /// Clean up resources when the look is permanently removed
    func teardown()
}

/// Extension to provide default implementations
extension Look {
    func activate() {
        // Default: no-op
    }

    func deactivate() {
        // Default: no-op
    }

    func teardown() {
        // Default: just remove entities
        rootEntity.removeFromParent()
    }
}

/// Type-erased look wrapper for uniform management
@MainActor
final class AnyLook {
    private let _rootEntity: () -> Entity
    private let _activate: () -> Void
    private let _deactivate: () -> Void
    private let _update: (Double, Double, any LookParams) -> Void
    private let _teardown: () -> Void

    let lookType: LookType

    init<L: Look>(_ look: L, type: LookType) {
        self.lookType = type

        _rootEntity = { look.rootEntity }
        _activate = { look.activate() }
        _deactivate = { look.deactivate() }
        _update = { time, dt, params in
            if let typedParams = params as? L.Params {
                look.update(time: time, deltaTime: dt, params: typedParams)
            }
        }
        _teardown = { look.teardown() }
    }

    var rootEntity: Entity { _rootEntity() }

    func activate() { _activate() }
    func deactivate() { _deactivate() }
    func update(time: Double, deltaTime: Double, params: any LookParams) {
        _update(time, deltaTime, params)
    }
    func teardown() { _teardown() }
}
