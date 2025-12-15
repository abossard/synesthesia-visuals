import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var windows: [ShareableWindow] = []
    @Published var selectedWindowID: UInt32? = nil

    @Published var latestFrame: CGImage? = nil
    @Published var frameSize: CGSize = .zero

    @Published var calibration = CalibrationModel()
    @Published var calibrating: Bool = false {
        didSet { overlayController.setInteractive(calibrating) }
    }
    @Published var overlayEnabled: Bool = true {
        didSet { overlayController.setVisible(overlayEnabled) }
    }

    @Published var detection: DetectionResult? = nil
    @Published var oscHost: String = "127.0.0.1"
    @Published var oscPort: UInt16 = 9000
    @Published var oscEnabled: Bool = true

    let capture = CaptureManager()
    let overlayController = OverlayController()
    var osc = OSCSender()

    init() {
        capture.onFrame = { [weak self] cg, size in
            Task { @MainActor in
                self?.latestFrame = cg
                self?.frameSize = size
                self?.overlayController.updateOverlayContent(
                    frame: cg,
                    calibration: self?.calibration ?? .init(),
                    detection: self?.detection
                )
            }
        }
        capture.onWindowsChanged = { [weak self] wins in
            Task { @MainActor in self?.windows = wins }
        }

        overlayController.setVisible(true)
        overlayController.setInteractive(false)
    }

    func refreshWindows() {
        Task { await capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj") }
    }

    func startCapture() {
        guard let id = selectedWindowID else { return }
        Task { await capture.startCapturing(windowID: id) }
        overlayController.followVirtualDJWindow(ownerContains: "VirtualDJ")
    }

    func stopCapture() {
        Task { await capture.stop() }
    }

    func runDetectionOnce() {
        guard let frame = latestFrame else { return }
        Task.detached {
            let result = await Detector.detect(frame: frame, calibration: self.calibration)
            await MainActor.run {
                self.detection = result
                self.overlayController.updateOverlayContent(frame: frame, calibration: self.calibration, detection: result)
                if self.oscEnabled {
                    self.osc.configure(host: self.oscHost, port: self.oscPort)
                    self.osc.send(result: result)
                }
            }
        }
    }

    func saveCalibration() {
        calibration.saveToDisk()
    }

    func loadCalibration() {
        if let loaded = CalibrationModel.loadFromDisk() {
            calibration = loaded
        }
    }
}
