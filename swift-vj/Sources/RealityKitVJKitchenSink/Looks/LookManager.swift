import Foundation
import RealityKit

@available(macOS 15.0, *)
final class LookManager {
    private let context: LookContext
    private var anchor = AnchorEntity(world: .zero)
    private(set) var currentLookKind: LookKind?
    private var currentLook: AnyLook?

    init(context: LookContext) {
        self.context = context
        context.view.scene.addAnchor(anchor)
    }

    func switchLook(to kind: LookKind) {
        if currentLookKind == kind {
            return
        }

        currentLook?.teardown()
        anchor.children.removeAll()

        let look: AnyLook
        switch kind {
        case .spaceDome:
            look = AnyLook(SpaceDomeLook(context: context))
        case .water:
            look = AnyLook(WaterLook(context: context))
        case .laserRig:
            look = AnyLook(LaserRigLook(context: context))
        case .dancer:
            look = AnyLook(DancerLook(context: context))
        case .proceduralMesh:
            look = AnyLook(ProceduralMeshLook(context: context))
        }

        let root = look.makeRootEntity()
        anchor.addChild(root)
        currentLook = look
        currentLookKind = kind
    }

    func update(deltaTime: Double, globalParams: GlobalParams, lookParams: LookParamsContainer, time: Double) {
        guard let currentLookKind, let currentLook else { return }

        switch currentLookKind {
        case .spaceDome:
            currentLook.update(dt: deltaTime, params: globalParams, lookParams: lookParams.spaceDome, time: time)
        case .water:
            currentLook.update(dt: deltaTime, params: globalParams, lookParams: lookParams.water, time: time)
        case .laserRig:
            currentLook.update(dt: deltaTime, params: globalParams, lookParams: lookParams.laserRig, time: time)
        case .dancer:
            currentLook.update(dt: deltaTime, params: globalParams, lookParams: lookParams.dancer, time: time)
        case .proceduralMesh:
            currentLook.update(dt: deltaTime, params: globalParams, lookParams: lookParams.proceduralMesh, time: time)
        }
    }

    func teardown() {
        currentLook?.teardown()
        currentLook = nil
        anchor.removeFromParent()
    }
}
