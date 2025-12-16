import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var windows: [ShareableWindow] = []
    @Published var selectedWindowID: UInt32? = nil {
        didSet {
            // Auto-start capture when a window is selected
            if selectedWindowID != nil && selectedWindowID != oldValue {
                startCapture()
            }
        }
    }

    @Published var latestFrame: CGImage? = nil
    @Published var frameSize: CGSize = .zero
    @Published var frameCounter: UInt64 = 0  // Increments each frame to force SwiftUI updates

    @Published var calibration = CalibrationModel()
    @Published var calibrating: Bool = false
    @Published var isCapturing: Bool = false

    @Published var detection: DetectionResult? = nil
    @Published var oscHost: String = "127.0.0.1"
    @Published var oscPort: UInt16 = 9000
    @Published var oscEnabled: Bool = true

    let capture = CaptureManager()
    var osc = OSCSender()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Subscribe to frames from CaptureManager
        capture.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (cgImage, size) in
                guard let self else { return }
                self.latestFrame = cgImage
                self.frameSize = size
                self.frameCounter += 1
                print("[AppState] Frame \(self.frameCounter) received, size: \(size)")
            }
            .store(in: &cancellables)
        
        // Subscribe to window list updates
        capture.windowsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] windows in
                self?.windows = windows
            }
            .store(in: &cancellables)
        
        // Subscribe to capture state changes
        capture.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capturing in
                self?.isCapturing = capturing
            }
            .store(in: &cancellables)
        
        // Log errors from capture manager
        capture.$lastError
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { error in
                print("[AppState] Capture error: \(error)")
            }
            .store(in: &cancellables)
    }

    func refreshWindows() {
        Task {
            await capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj")
        }
    }

    func startCapture() {
        guard let id = selectedWindowID else { return }
        Task {
            await capture.startCapturing(windowID: id)
            print("[AppState] Capture started for window \(id)")
        }
    }

    func stopCapture() {
        Task { await capture.stop() }
        isCapturing = false
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
}
