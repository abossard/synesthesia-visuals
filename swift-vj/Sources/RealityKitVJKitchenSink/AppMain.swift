// AppMain.swift
// RealityKitVJKitchenSink
//
// Main application entry point for the RealityKit VJ Kitchen Sink demo.
// Renders multiple high-quality RealityKit "looks" with Syphon output.

import SwiftUI
import RealityKit
import AppKit

@main
struct RealityKitVJKitchenSinkApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}

// MARK: - App Delegate for Window Management

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy to regular (foreground GUI app)
        // Without this, SPM-built SwiftUI apps won't show windows
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app is active and frontmost
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Force window creation and display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Global Application State

/// Single source of truth for all application parameters
@MainActor
final class AppState: ObservableObject {
    // MARK: - Global Parameters

    @Published var isPaused: Bool = false
    @Published var timeScale: Double = 1.0
    @Published var cameraMotionEnabled: Bool = true
    @Published var cameraMotionSpeed: Double = 0.3
    @Published var environmentIntensity: Double = 1.0
    @Published var bloomIntensity: Double = 0.5
    @Published var syphonEnabled: Bool = true

    // MARK: - Look Selection

    @Published var currentLookType: LookType = .spaceDome

    // MARK: - Per-Look Parameters

    @Published var spaceDomeParams = SpaceDomeParams()
    @Published var waterParams = WaterParams()
    @Published var laserRigParams = LaserRigParams()
    @Published var dancerParams = DancerParams()
    @Published var proceduralMeshParams = ProceduralMeshParams()

    // MARK: - Diagnostics

    @Published var currentFPS: Double = 0.0
    @Published var frameCount: Int = 0

    // MARK: - Time Tracking

    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var accumulatedTime: Double = 0.0

    /// Returns the current time for animation (respects pause and time scale)
    var animationTime: Double {
        accumulatedTime
    }

    /// Call this each frame to update time tracking
    func updateFrame() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - lastFrameTime
        lastFrameTime = now

        if !isPaused {
            accumulatedTime += dt * timeScale
        }

        frameCount += 1

        // Smooth FPS calculation
        let fps = 1.0 / max(dt, 0.001)
        currentFPS = currentFPS * 0.9 + fps * 0.1
    }

    /// Get parameters for the current look
    func currentLookParams() -> any LookParams {
        switch currentLookType {
        case .spaceDome:
            return spaceDomeParams
        case .water:
            return waterParams
        case .laserRig:
            return laserRigParams
        case .dancer:
            return dancerParams
        case .proceduralMesh:
            return proceduralMeshParams
        }
    }
}

// MARK: - Look Types

enum LookType: String, CaseIterable, Identifiable {
    case spaceDome = "Space Dome"
    case water = "Water"
    case laserRig = "Laser Rig"
    case dancer = "Dancer"
    case proceduralMesh = "Procedural Mesh"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .spaceDome: return "moon.stars"
        case .water: return "water.waves"
        case .laserRig: return "laser.burst"
        case .dancer: return "figure.dance"
        case .proceduralMesh: return "cube.transparent"
        }
    }
}

// MARK: - Look Parameters Protocol

protocol LookParams: Codable {
    static var defaults: Self { get }
}

// MARK: - Space Dome Parameters

struct SpaceDomeParams: LookParams, Codable {
    var starDensity: Double = 1.0
    var domeHueSpeed: Double = 0.1
    var cameraDriftAmplitude: Double = 0.5
    var nebulaIntensity: Double = 0.6

    static var defaults: SpaceDomeParams { SpaceDomeParams() }
}

// MARK: - Water Parameters

struct WaterParams: LookParams, Codable {
    var waveAmplitude: Double = 0.3
    var waveFrequency: Double = 2.0
    var specular: Double = 0.8
    var roughness: Double = 0.2
    var causticTint: SIMD3<Float> = SIMD3<Float>(0.2, 0.5, 0.8)

    static var defaults: WaterParams { WaterParams() }
}

// MARK: - Laser Rig Parameters

struct LaserRigParams: LookParams, Codable {
    var beamCount: Int = 12
    var beamSweepSpeed: Double = 1.0
    var glowIntensity: Double = 2.0
    var colorCycleSpeed: Double = 0.5
    var fanAngle: Double = 60.0

    static var defaults: LaserRigParams { LaserRigParams() }
}

// MARK: - Dancer Parameters

struct DancerParams: LookParams, Codable {
    var animationSpeed: Double = 1.0
    var scalePulse: Double = 0.1
    var lightingIntensity: Double = 1.0
    var floorReflectivity: Double = 0.5
    var rotationSpeed: Double = 0.2

    static var defaults: DancerParams { DancerParams() }
}

// MARK: - Procedural Mesh Parameters

struct ProceduralMeshParams: LookParams, Codable {
    var ribbonLength: Int = 100
    var thickness: Double = 0.1
    var noiseScale: Double = 1.0
    var colorGradientSpeed: Double = 0.3
    var waveCount: Int = 3

    static var defaults: ProceduralMeshParams { ProceduralMeshParams() }
}
