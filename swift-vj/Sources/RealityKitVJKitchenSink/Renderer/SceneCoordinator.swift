// SceneCoordinator.swift
// RealityKitVJKitchenSink
//
// Manages ARView, camera, update loop, and timebase.
// Owns the LookManager and coordinates scene transitions.

import RealityKit
import Combine
import Metal
import simd

/// Coordinates scene rendering, look management, and camera control
@MainActor
final class SceneCoordinator {
    private weak var arView: ARView?
    private weak var appState: AppState?

    private var lookManager: LookManager?
    private var syphonOutput: SyphonOutput?
    private var postProcessor: PostProcessor?

    // Store display link reference outside of MainActor for cleanup
    nonisolated(unsafe) private var displayLinkRef: CVDisplayLink?
    private var displayLink: CVDisplayLink? {
        get { displayLinkRef }
        set { displayLinkRef = newValue }
    }
    private var lastFrameTime: CFAbsoluteTime = 0
    private var accumulatedTime: Double = 0

    private var cameraEntity: Entity?
    private var baseCameraTransform: Transform = .identity

    private var cancellables = Set<AnyCancellable>()

    // Camera orbit parameters
    private var orbitAngle: Float = 0
    private var orbitRadius: Float = 5.0
    private var orbitHeight: Float = 2.0

    deinit {
        // DisplayLink cleanup (using deprecated CVDisplayLink APIs)
        // TODO: Migrate to NSView.displayLink when refactoring to NSView-based architecture
        if #available(macOS 15.0, *) {
            // Still using CVDisplayLink as modern API requires NSView context
        }
        cleanupDisplayLink()
    }
    
    private nonisolated func cleanupDisplayLink() {
        if let link = displayLinkRef {
            CVDisplayLinkStop(link)
        }
    }

    // MARK: - Setup

    func setup(arView: ARView, appState: AppState) {
        self.arView = arView
        self.appState = appState

        // Set up Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Failed to create Metal device")
            return
        }

        // Initialize Syphon output
        syphonOutput = SyphonOutput(device: device, serverName: "RealityKitVJKitchenSink")

        // Initialize post processor
        postProcessor = PostProcessor(device: device)

        // Set up camera
        setupCamera(in: arView)

        // Set up environment
        setupEnvironment(in: arView)

        // Initialize look manager
        lookManager = LookManager(arView: arView, device: device)

        // Set up render callbacks for Syphon publishing
        setupRenderCallbacks(arView: arView)

        // Start with the initial look
        lookManager?.switchToLook(appState.currentLookType)

        // Start display link (using deprecated CVDisplayLink APIs)
        // TODO: Migrate to NSView.displayLink when refactoring to NSView-based architecture
        if #available(macOS 15.0, *) {
            // Still using CVDisplayLink as modern API requires NSView context
        }
        startDisplayLink()

        // Observe look changes
        observeStateChanges()
    }

    func updateAppState(_ newState: AppState) {
        // State reference is updated, but we observe specific changes via Combine
        self.appState = newState
    }

    // MARK: - Camera Setup

    private func setupCamera(in arView: ARView) {
        // In nonAR mode, the camera is fixed - we control scene rotation instead
        // arView.cameraTransform is read-only in RealityKit

        // Set initial camera position for reference
        let initialPosition = SIMD3<Float>(0, 2, 5)
        let lookAtTarget = SIMD3<Float>(0, 0, 0)

        // Store base transform for orbit calculations
        baseCameraTransform = Transform(
            scale: .one,
            rotation: lookAt(from: initialPosition, to: lookAtTarget),
            translation: initialPosition
        )

        orbitRadius = length(initialPosition - lookAtTarget)
        orbitHeight = initialPosition.y
    }

    private func lookAt(from position: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let forward = normalize(target - position)
        let right = normalize(cross(SIMD3<Float>(0, 1, 0), forward))
        let up = cross(forward, right)

        let m = simd_float3x3(columns: (right, up, -forward))
        return simd_quatf(m)
    }

    // MARK: - Environment Setup

    private func setupEnvironment(in arView: ARView) {
        // Create a skybox-like environment
        // Use a color gradient background
        arView.environment.background = .color(.black)

        // Set up lighting
        let anchor = AnchorEntity(world: .zero)

        // Key light
        let keyLight = createDirectionalLight(
            color: .white,
            intensity: 1000,
            direction: SIMD3<Float>(-0.5, -0.8, -0.3)
        )
        anchor.addChild(keyLight)

        // Fill light
        let fillLight = createDirectionalLight(
            color: UIColor(red: 0.6, green: 0.7, blue: 1.0, alpha: 1.0),
            intensity: 400,
            direction: SIMD3<Float>(0.5, -0.3, 0.5)
        )
        anchor.addChild(fillLight)

        // Rim light
        let rimLight = createDirectionalLight(
            color: UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1.0),
            intensity: 600,
            direction: SIMD3<Float>(0.0, 0.5, 1.0)
        )
        anchor.addChild(rimLight)

        arView.scene.anchors.append(anchor)
    }

    private func createDirectionalLight(color: UIColor, intensity: Float, direction: SIMD3<Float>) -> Entity {
        let light = Entity()
        light.components[DirectionalLightComponent.self] = DirectionalLightComponent(
            color: color,
            intensity: intensity,
            isRealWorldProxy: false
        )
        // Point light in direction
        let q = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: normalize(direction))
        light.transform.rotation = q
        return light
    }

    // MARK: - Render Callbacks

    private func setupRenderCallbacks(arView: ARView) {
        // Set up postprocess callback to capture rendered frame and publish to Syphon
        // Reference: https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess

        arView.renderCallbacks.postProcess = { [weak self] context in
            guard let self = self else { return }

            // Get the rendered texture
            let sourceTexture = context.sourceColorTexture

            // Apply bloom if enabled
            if let bloomIntensity = self.appState?.bloomIntensity, bloomIntensity > 0.01 {
                self.postProcessor?.applyBloom(
                    commandBuffer: context.commandBuffer,
                    sourceTexture: sourceTexture,
                    targetTexture: context.targetColorTexture,
                    intensity: Float(bloomIntensity)
                )
            } else {
                // Just copy source to target
                self.postProcessor?.copyTexture(
                    commandBuffer: context.commandBuffer,
                    sourceTexture: sourceTexture,
                    targetTexture: context.targetColorTexture
                )
            }

            // Publish to Syphon if enabled
            if self.appState?.syphonEnabled == true {
                self.syphonOutput?.publish(
                    texture: context.targetColorTexture,
                    commandBuffer: context.commandBuffer
                )
            }
        }
    }

    // MARK: - Display Link
    // Note: Using deprecated CVDisplayLink APIs. Modern NSView.displayLink requires NSView context.

    private func startDisplayLink() {
        var displayLink: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        guard result == kCVReturnSuccess, let link = displayLink else {
            print("Failed to create display link")
            return
        }

        self.displayLink = link

        // Set up callback
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
            let coordinator = Unmanaged<SceneCoordinator>.fromOpaque(userInfo!).takeUnretainedValue()
            coordinator.frameCallback()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)

        lastFrameTime = CFAbsoluteTimeGetCurrent()
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    private func frameCallback() {
        let now = CFAbsoluteTimeGetCurrent()
        let dt = now - lastFrameTime
        lastFrameTime = now

        // Dispatch UI updates to main thread
        DispatchQueue.main.async { [weak self] in
            self?.updateFrame(dt: dt)
        }
    }

    private func updateFrame(dt: Double) {
        guard arView != nil, let appState = appState else { return }

        // Update app state frame tracking
        appState.updateFrame()

        // Check for look changes
        checkLookChange()

        // Skip updates if paused
        guard !appState.isPaused else { return }

        let scaledDt = dt * appState.timeScale
        accumulatedTime += scaledDt

        // Update camera motion
        if appState.cameraMotionEnabled {
            updateCameraMotion(dt: Float(scaledDt), speed: Float(appState.cameraMotionSpeed))
        }

        // Update current look
        lookManager?.update(
            time: accumulatedTime,
            deltaTime: scaledDt,
            params: appState.currentLookParams()
        )
    }

    private func updateCameraMotion(dt: Float, speed: Float) {
        guard let appState = appState else { return }

        // Get look-specific camera drift amplitude
        var driftAmplitude: Float = 1.0
        if let spaceDomeParams = appState.currentLookParams() as? SpaceDomeParams {
            driftAmplitude = Float(spaceDomeParams.cameraDriftAmplitude)
        }

        // Orbital camera motion - we rotate the scene root instead of camera
        orbitAngle += dt * speed * 0.5 * driftAmplitude

        // Apply rotation to look manager's root if available
        if let lookManager = lookManager,
           lookManager.currentLookType != nil {
            // The look already handles its own animation, so camera drift
            // is incorporated via look-specific parameters
        }

        // Note: In RealityKit, arView.cameraTransform is read-only
        // Camera animation should be handled by manipulating scene entities or using perspective camera entity
    }

    // MARK: - State Observation

    private func observeStateChanges() {
        // We need to observe look type changes
        // Since we can't use Combine directly with @Published in this context,
        // we'll check in updateFrame
    }

    func checkLookChange() {
        guard let appState = appState else { return }

        if let lookManager = lookManager {
            if lookManager.currentLookType != appState.currentLookType {
                lookManager.switchToLook(appState.currentLookType)
            }
        }
    }
}

// MARK: - UIColor Extension for macOS

#if os(macOS)
import AppKit
typealias UIColor = NSColor
#endif
