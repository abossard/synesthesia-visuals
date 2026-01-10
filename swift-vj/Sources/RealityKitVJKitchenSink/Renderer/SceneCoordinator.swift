// SceneCoordinator.swift - Main coordinator owning ARView, camera, update loop
// Manages scene lifecycle, look switching, and frame updates

import Foundation
import RealityKit
import SwiftUI
import Combine
import Metal

@MainActor
final class SceneCoordinator: ObservableObject {
    // MARK: - Published Properties
    
    @Published var selectedLookType: LookType = .spaceDome {
        didSet {
            if selectedLookType != oldValue {
                switchLook(to: selectedLookType)
            }
        }
    }
    
    @Published var globalParams = GlobalParams()
    @Published var spaceDomeParams = SpaceDomeParams()
    @Published var waterParams = WaterParams()
    @Published var laserRigParams = LaserRigParams()
    @Published var dancerParams = DancerParams()
    @Published var proceduralMeshParams = ProceduralMeshParams()
    
    @Published var fps: Double = 60.0
    
    var currentLookName: String {
        selectedLookType.displayName
    }
    
    // MARK: - Private Properties
    
    private(set) var arView: ARView?
    private var lookManager: LookManager?
    private var syphonOutput: SyphonOutput?
    private var postProcess: PostProcess?
    
    private var lastUpdateTime: TimeInterval = 0
    private var totalElapsedTime: TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // MARK: - Init
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal is required for RealityKit VJ")
        }
        
        self.device = device
        self.commandQueue = queue
    }
    
    // MARK: - Lifecycle
    
    func start() async {
        guard arView == nil else { return }
        
        // Create ARView in non-AR mode
        // Reference: https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.renderOptions = [.disableMotionBlur]
        
        // Setup camera
        setupCamera(view: view)
        
        // Create look manager
        let context = LookContext(device: device, commandQueue: commandQueue)
        let manager = LookManager(scene: view.scene, context: context)
        self.lookManager = manager
        
        // Switch to initial look
        manager.switchTo(selectedLookType)
        updateCurrentLookParams()
        
        // Setup Syphon output
        // Reference: https://github.com/Syphon/Syphon-Framework
        syphonOutput = SyphonOutput(
            name: "RealityKitVJKitchenSink",
            device: device,
            commandQueue: commandQueue
        )
        
        // Setup post-processing
        // Reference: https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess
        postProcess = PostProcess(
            device: device,
            syphonOutput: syphonOutput!,
            coordinator: self
        )
        view.renderCallbacks.postProcess = postProcess!.callback
        
        // Start update loop
        lastUpdateTime = CACurrentMediaTime()
        startUpdateLoop(view: view)
        
        self.arView = view
        
        print("[SceneCoordinator] Started with look: \(selectedLookType.displayName)")
    }
    
    func stop() {
        lookManager?.teardownAll()
        syphonOutput?.stop()
        arView = nil
        lookManager = nil
        syphonOutput = nil
        postProcess = nil
    }
    
    // MARK: - Private
    
    private func setupCamera(view: ARView) {
        // Setup default camera position for non-AR mode
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.position = SIMD3<Float>(0, 2, 8)
        cameraAnchor.look(at: SIMD3<Float>(0, 0, 0), from: cameraAnchor.position, relativeTo: nil)
        
        // Note: In non-AR mode, we need to manually control camera
        // Store camera anchor for animation
        view.scene.addAnchor(cameraAnchor)
    }
    
    private func switchLook(to lookType: LookType) {
        lookManager?.switchTo(lookType)
        updateCurrentLookParams()
    }
    
    private func updateCurrentLookParams() {
        // Pass params to current look
        guard let manager = lookManager else { return }
        
        // Inject params into current look based on type
        // Note: This requires looks to have setParams methods
        // For type safety, we'd use a protocol or associated types
    }
    
    private func startUpdateLoop(view: ARView) {
        // RealityKit ARView has built-in update loop via scene.subscribe
        view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self = self else { return }
            
            let currentTime = CACurrentMediaTime()
            let dt = currentTime - self.lastUpdateTime
            self.lastUpdateTime = currentTime
            
            // Apply time scale and pause
            let effectiveDt = self.globalParams.paused ? 0 : dt * self.globalParams.timeScale
            self.totalElapsedTime += effectiveDt
            
            // Update FPS
            if dt > 0 {
                self.fps = 1.0 / dt
            }
            
            // Update camera motion
            self.updateCamera(dt: effectiveDt, view: view)
            
            // Update look
            self.lookManager?.update(
                dt: effectiveDt,
                time: self.totalElapsedTime,
                globalParams: self.globalParams
            )
        }.store(in: &cancellables)
    }
    
    private func updateCamera(dt: Double, view: ARView) {
        // Orbital camera motion based on globalParams.cameraMotion
        guard globalParams.cameraMotion > 0.01 else { return }
        
        let radius: Float = 8.0
        let speed = Float(globalParams.cameraMotion * 0.2)
        let angle = Float(totalElapsedTime * Double(speed))
        
        let x = cos(angle) * radius
        let z = sin(angle) * radius
        let y: Float = 2.0 + sin(angle * 0.5) * Float(globalParams.cameraMotion)
        
        // Find camera anchor (first anchor in scene)
        if let cameraAnchor = view.scene.anchors.first {
            cameraAnchor.position = SIMD3<Float>(x, y, z)
            cameraAnchor.look(at: SIMD3<Float>(0, 0, 0), from: cameraAnchor.position, relativeTo: nil)
        }
    }
}
