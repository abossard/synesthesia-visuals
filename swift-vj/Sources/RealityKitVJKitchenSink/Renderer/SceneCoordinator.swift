import Combine
import Foundation
import RealityKit
import SwiftUI

@available(macOS 15.0, *)
final class SceneCoordinator: ObservableObject {
    @Published var globalParams = GlobalParams()
    @Published var lookParams = LookParamsContainer()
    @Published var selectedLook: LookKind = .spaceDome
    @Published private(set) var fps: Double = 0

    private var arView: ARView?
    private var lookManager: LookManager?
    private var updateSubscription: Cancellable?
    private var displayLink: CADisplayLink?
    private var lastUpdateTime: TimeInterval = 0
    private var frameCounter = 0
    private var fpsLastSampleTime: CFTimeInterval = CACurrentMediaTime()

    private let timebase = Timebase()
    private let postProcess = PostProcess()
    private let cameraController = CameraController()

    func makeView() -> ARView {
        if let arView {
            return arView
        }

        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.environment.background = .color(.black)
        view.renderOptions.insert(.disableDepthOfField)
        view.renderCallbacks.postProcess = { [weak self] context in
            self?.postProcess.handlePostProcess(context: context, globalParams: self?.globalParams)
        }

        arView = view
        lookManager = LookManager(context: LookContext(view: view, postProcess: postProcess))
        applyLookChange()
        setupSceneUpdate()
        return view
    }

    func updateView() {
        guard let arView else { return }
        arView.environment.lighting.intensityExponent = globalParams.environmentIntensity
        postProcess.bloomIntensity = globalParams.bloomIntensity
        postProcess.syphonEnabled = globalParams.syphonEnabled
        cameraController.motionAmount = globalParams.cameraMotion
    }

    func start() {
        _ = makeView()
        setupDisplayLink()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        updateSubscription?.cancel()
        updateSubscription = nil
        lookManager?.teardown()
    }

    private func setupSceneUpdate() {
        guard let arView else { return }
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(deltaTime: event.deltaTime)
        }
    }

    private func setupDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(displayTick))
        link.add(to: .current, forMode: .common)
        displayLink = link
    }

    @objc private func displayTick() {
        let now = CACurrentMediaTime()
        frameCounter += 1
        if now - fpsLastSampleTime >= 0.5 {
            fps = Double(frameCounter) / (now - fpsLastSampleTime)
            frameCounter = 0
            fpsLastSampleTime = now
        }
    }

    private func tick(deltaTime: TimeInterval) {
        if selectedLook != lookManager?.currentLookKind {
            applyLookChange()
        }

        let scaledDelta = timebase.scaledDelta(deltaTime: deltaTime, paused: globalParams.isPaused, timeScale: globalParams.timeScale)
        let globalTime = timebase.update(deltaTime: scaledDelta)

        cameraController.update(arView: arView, time: globalTime, motionAmount: globalParams.cameraMotion)
        lookManager?.update(
            deltaTime: scaledDelta,
            globalParams: globalParams,
            lookParams: lookParams,
            time: globalTime
        )
    }

    private func applyLookChange() {
        guard let lookManager else { return }
        lookManager.switchLook(to: selectedLook)
    }
}

@available(macOS 15.0, *)
struct GlobalParams: Codable {
    var isPaused: Bool = false
    var timeScale: Double = 1.0
    var cameraMotion: Double = 0.5
    var environmentIntensity: Double = 1.2
    var bloomIntensity: Double = 0.8
    var syphonEnabled: Bool = true
}

@available(macOS 15.0, *)
struct LookParamsContainer: Codable {
    var spaceDome = SpaceDomeParams()
    var water = WaterParams()
    var laserRig = LaserRigParams()
    var dancer = DancerParams()
    var proceduralMesh = ProceduralMeshParams()
}

@available(macOS 15.0, *)
final class Timebase {
    private(set) var time: Double = 0

    func scaledDelta(deltaTime: TimeInterval, paused: Bool, timeScale: Double) -> Double {
        guard !paused else { return 0 }
        return deltaTime * timeScale
    }

    func update(deltaTime: Double) -> Double {
        time += deltaTime
        return time
    }
}

@available(macOS 15.0, *)
final class CameraController {
    var motionAmount: Double = 0.5
    private var smoothedOrbit = ParameterSmoothing(initialValue: .zero)

    func update(arView: ARView?, time: Double, motionAmount: Double) {
        guard let arView else { return }
        let orbit = SIMD3<Float>(
            Float(sin(time * 0.2)) * Float(motionAmount),
            Float(cos(time * 0.15)) * Float(motionAmount * 0.4),
            Float(cos(time * 0.25)) * Float(motionAmount)
        )
        let smoothed = smoothedOrbit.update(target: orbit, deltaTime: 1.0 / 60.0)
        let cameraTransform = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
            translation: [smoothed.x * 2.0, 1.4 + smoothed.y, 4.8 + smoothed.z]
        )
        arView.cameraTransform = cameraTransform
    }
}
