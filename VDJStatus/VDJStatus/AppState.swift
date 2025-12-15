import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum WizardStep: Int, CaseIterable, Identifiable {
        case selectWindow, capturePreview, calibrate

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .selectWindow: return "Select VirtualDJ Window"
            case .capturePreview: return "Start Capture & Preview"
            case .calibrate: return "Calibrate Regions"
            }
        }
        var subtitle: String {
            switch self {
            case .selectWindow: return "Choose the VirtualDJ deck window to analyze"
            case .capturePreview: return "Start capture to see live OCR preview"
            case .calibrate: return "Fine-tune text/fader regions"
            }
        }
    }

    @Published var wizardStep: WizardStep = .selectWindow
    @Published var windows: [ShareableWindow] = []
    @Published var selectedWindowID: UInt32? = nil {
        didSet { updateWizardAfterSelection() }
    }

    @Published var latestFrame: CGImage? = nil
    @Published var frameSize: CGSize = .zero

    @Published var calibration = CalibrationModel()
    @Published var calibrating: Bool = false {
        didSet { wizardStep = calibrating ? .calibrate : .capturePreview }
    }

    @Published var detection: DetectionResult? = nil
    @Published var oscHost: String = "127.0.0.1"
    @Published var oscPort: UInt16 = 9000
    @Published var oscEnabled: Bool = true
    @Published var isCapturing: Bool = false

    let capture = CaptureManager()
    var osc = OSCSender()

    init() {
        Task {
            await capture.setOnFrame { [weak self] cg, size in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestFrame = cg
                    self.frameSize = size
                }
            }
            await capture.setOnWindowsChanged { [weak self] wins in
                Task { @MainActor [weak self] in
                    self?.windows = wins
                }
            }
        }
    }

    func refreshWindows() {
        Task { await capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj") }
    }

    func startCapture() {
        guard let id = selectedWindowID else { return }
        Task { await capture.startCapturing(windowID: id) }
        isCapturing = true
        wizardStep = calibrating ? .calibrate : .capturePreview
    }

    func stopCapture() {
        Task { await capture.stop() }
        isCapturing = false
        if !calibrating {
            wizardStep = selectedWindowID == nil ? .selectWindow : .capturePreview
        }
    }

    func runDetectionOnce() {
        guard let frame = latestFrame else { return }
        Task.detached {
            let result = await Detector.detect(frame: frame, calibration: self.calibration)
            await MainActor.run {
                self.detection = result
                if self.oscEnabled {
                    self.osc.configure(host: self.oscHost, port: self.oscPort)
                    self.osc.send(result: result)
                }
            }
        }
    }

    func saveCalibration() { calibration.saveToDisk() }

    func loadCalibration() {
        if let loaded = CalibrationModel.loadFromDisk() {
            calibration = loaded
        }
    }

    private func updateWizardAfterSelection() {
        guard !calibrating else { return }
        wizardStep = selectedWindowID == nil ? .selectWindow : (isCapturing ? .capturePreview : .capturePreview)
    }
}
