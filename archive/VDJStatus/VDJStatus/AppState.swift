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
                // Persist the window name for auto-capture on next launch
                if let win = windows.first(where: { $0.id == selectedWindowID }) {
                    saveLastWindow(appName: win.appName, title: win.title)
                }
            }
        }
    }

    @Published var latestFrame: CGImage? = nil
    @Published var frameSize: CGSize = .zero
    @Published var frameCounter: UInt64 = 0  // Increments each frame to force SwiftUI updates

    @Published var calibration = CalibrationModel() {
        didSet {
            // Auto-save calibration whenever it changes
            calibration.saveToDisk()
        }
    }
    @Published var calibrating: Bool = false
    @Published var isCapturing: Bool = false

    @Published var detection: DetectionResult? = nil
    @Published var oscHost: String = "127.0.0.1"
    @Published var oscPort: UInt16 = 9000
    @Published var oscEnabled: Bool = true
    
    // FSM-based master/deck state management
    let deckStateManager = DeckStateManager()
    
    // Performance metrics
    @Published var lastDetectionMs: Double = 0
    @Published var avgDetectionMs: Double = 0
    @Published var captureLatencyMs: Double = 0
    private var detectionTimes: [Double] = []
    private var lastFrameTime: Date?

    let capture = CaptureManager()
    var osc = OSCSender()
    private var cancellables = Set<AnyCancellable>()
    
    // Persistence keys
    private static let lastWindowAppNameKey = "lastWindowAppName"
    private static let lastWindowTitleKey = "lastWindowTitle"

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
                
                // Calculate capture latency (time between frames)
                let now = Date()
                if let last = self.lastFrameTime {
                    self.captureLatencyMs = now.timeIntervalSince(last) * 1000
                }
                self.lastFrameTime = now
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
    
    /// Refresh windows and auto-select last captured window if found
    func refreshWindowsAndAutoCapture() {
        Task {
            await capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj")
            
            // Try to find and select the last captured window
            if let (appName, title) = loadLastWindow() {
                // First try exact match
                if let match = windows.first(where: { $0.appName == appName && $0.title == title }) {
                    print("[AppState] Auto-selecting last window: \(appName) - \(title)")
                    selectedWindowID = match.id
                }
                // Fallback: match by app name only (title may change)
                else if let match = windows.first(where: { $0.appName == appName }) {
                    print("[AppState] Auto-selecting by app name: \(appName)")
                    selectedWindowID = match.id
                }
            }
        }
    }
    
    // MARK: - Window Persistence
    
    private func saveLastWindow(appName: String, title: String) {
        UserDefaults.standard.set(appName, forKey: Self.lastWindowAppNameKey)
        UserDefaults.standard.set(title, forKey: Self.lastWindowTitleKey)
    }
    
    private func loadLastWindow() -> (appName: String, title: String)? {
        guard let appName = UserDefaults.standard.string(forKey: Self.lastWindowAppNameKey),
              let title = UserDefaults.standard.string(forKey: Self.lastWindowTitleKey) else {
            return nil
        }
        return (appName, title)
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
        let startTime = Date()
        Task.detached {
            let result = await Detector.detect(frame: frame, calibration: self.calibration)
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            await MainActor.run {
                self.detection = result
                self.lastDetectionMs = elapsed
                
                // Update FSM state based on detection (logs changes to console)
                self.deckStateManager.process(result)
                
                // Update detection result with FSM-determined master
                self.detection?.masterDeck = self.deckStateManager.master
                
                // Rolling average of last 20 detections
                self.detectionTimes.append(elapsed)
                if self.detectionTimes.count > 20 {
                    self.detectionTimes.removeFirst()
                }
                self.avgDetectionMs = self.detectionTimes.reduce(0, +) / Double(self.detectionTimes.count)
                
                if self.oscEnabled {
                    self.osc.configure(host: self.oscHost, port: self.oscPort)
                    // Pass play states to OSC sender for message payload
                    self.osc.deck1PlayState = self.playStateToInt(self.deckStateManager.deck1PlayState)
                    self.osc.deck2PlayState = self.playStateToInt(self.deckStateManager.deck2PlayState)
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
    
    /// Convert DeckPlayState enum to int for OSC (0=unknown, 1=playing, 2=stopped)
    private func playStateToInt(_ state: DeckPlayState) -> Int {
        switch state {
        case .unknown: return 0
        case .playing: return 1
        case .stopped: return 2
        }
    }
}
