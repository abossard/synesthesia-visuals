import Foundation
import RealityKit

@available(macOS 15.0, *)
protocol Look {
    associatedtype Parameters: LookParams
    var name: String { get }
    init(context: LookContext)
    func makeRootEntity() -> Entity
    func update(dt: Double, params: GlobalParams, lookParams: Parameters, time: Double)
    func teardown()
}

@available(macOS 15.0, *)
protocol LookParams: Codable {
    static var defaultValue: Self { get }
}

@available(macOS 15.0, *)
struct LookContext {
    let view: ARView
    let postProcess: PostProcess
    let bundle: Bundle = .module
}

@available(macOS 15.0, *)
struct AnyLook {
    let name: String
    private let _makeRoot: () -> Entity
    private let _update: (Double, GlobalParams, LookParams, Double) -> Void
    private let _teardown: () -> Void

    init<L: Look>(_ look: L) {
        name = look.name
        _makeRoot = { look.makeRootEntity() }
        _update = { dt, globalParams, params, time in
            guard let typedParams = params as? L.Parameters else { return }
            look.update(dt: dt, params: globalParams, lookParams: typedParams, time: time)
        }
        _teardown = { look.teardown() }
    }

    func makeRootEntity() -> Entity {
        _makeRoot()
    }

    func update(dt: Double, params: GlobalParams, lookParams: LookParams, time: Double) {
        _update(dt, params, lookParams, time)
    }

    func teardown() {
        _teardown()
    }
}

@available(macOS 15.0, *)
enum LookKind: String, CaseIterable, Identifiable {
    case spaceDome
    case water
    case laserRig
    case dancer
    case proceduralMesh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spaceDome: return "Space Dome"
        case .water: return "Water"
        case .laserRig: return "Laser Rig"
        case .dancer: return "Dancer"
        case .proceduralMesh: return "Procedural Mesh"
        }
    }
}
