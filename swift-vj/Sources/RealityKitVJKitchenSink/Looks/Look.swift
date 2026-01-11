// Look.swift - Protocol defining a RealityKit "look" (scene preset)
// Each look is a self-contained visual style with its own entities and parameters

import Foundation
import RealityKit
import Metal

// MARK: - Look Protocol

/// A Look represents a complete visual scene with its own entities and behavior
protocol Look: AnyObject {
    /// Initialize the look with a rendering context
    init(context: LookContext)
    
    /// Create and return the root entity for this look's scene graph
    func makeRootEntity() -> Entity
    
    /// Update the look for the current frame
    /// - Parameters:
    ///   - dt: Delta time since last update (seconds)
    ///   - time: Total elapsed time (seconds)
    ///   - globalParams: Global parameters (camera, environment, etc.)
    func update(dt: Double, time: Double, globalParams: GlobalParams)
    
    /// Clean up resources before switching looks
    func teardown()
}

// MARK: - Look Context

/// Context provided to looks for accessing shared resources
struct LookContext {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
}

// MARK: - Look Type

/// Enum identifying each look type
enum LookType: String, CaseIterable, Identifiable, Codable {
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

// MARK: - Global Parameters

/// Parameters affecting all looks (camera, environment, post-processing)
@MainActor
class GlobalParams: ObservableObject {
    @Published var timeScale: Double = 1.0
    @Published var paused: Bool = false
    @Published var cameraMotion: Double = 0.3
    @Published var environmentIntensity: Double = 1.0
    @Published var bloomIntensity: Double = 0.3
    @Published var syphonEnabled: Bool = true
}

// MARK: - Per-Look Parameters

/// Parameters for Space Dome look
@MainActor
class SpaceDomeParams: ObservableObject {
    @Published var starDensity: Double = 1.0
    @Published var domeHueSpeed: Double = 0.2
    @Published var cameraDriftAmplitude: Double = 2.0
}

/// Parameters for Water look
@MainActor
class WaterParams: ObservableObject {
    @Published var waveAmplitude: Double = 0.1
    @Published var waveFrequency: Double = 2.0
    @Published var specular: Double = 0.8
    @Published var roughness: Double = 0.2
}

/// Parameters for Laser Rig look
@MainActor
class LaserRigParams: ObservableObject {
    @Published var beamCount: Int = 12
    @Published var beamSweepSpeed: Double = 1.0
    @Published var glowIntensity: Double = 1.0
    @Published var colorCycleSpeed: Double = 0.5
}

/// Parameters for Dancer look
@MainActor
class DancerParams: ObservableObject {
    @Published var animationSpeed: Double = 1.0
    @Published var scalePulse: Double = 0.1
    @Published var lightingIntensity: Double = 1.0
    @Published var floorReflectivity: Double = 0.3
}

/// Parameters for Procedural Mesh look
@MainActor
class ProceduralMeshParams: ObservableObject {
    @Published var ribbonLength: Int = 50
    @Published var thickness: Double = 0.05
    @Published var noiseScale: Double = 1.0
    @Published var colorGradientSpeed: Double = 1.0
}
