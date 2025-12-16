import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreImage
import CoreGraphics
import Combine

struct ShareableWindow: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
}

/// Robust, self-healing screen capture manager
/// - Uses Combine PassthroughSubject for reliable frame delivery
/// - Implements SCStreamDelegate for error handling and auto-recovery
/// - Monitors stream health and auto-restarts on failure
final class CaptureManager: NSObject, SCStreamDelegate, SCStreamOutput {
    
    // MARK: - Public Interface
    
    /// Publisher for captured frames - subscribe to receive CGImage + size
    let framePublisher = PassthroughSubject<(CGImage, CGSize), Never>()
    
    /// Publisher for window list updates
    let windowsPublisher = PassthroughSubject<[ShareableWindow], Never>()
    
    /// Current capture state
    @Published private(set) var isCapturing = false
    @Published private(set) var frameCount: UInt64 = 0
    @Published private(set) var lastError: String?
    
    // MARK: - Private State
    
    private var stream: SCStream?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var targetWindowID: UInt32?
    private let outputQueue = DispatchQueue(label: "com.vdjstatus.capture.output", qos: .userInteractive)
    
    private var healthCheckTimer: Timer?
    private var lastFrameTime: Date?
    private let frameTimeoutSeconds: TimeInterval = 5.0
    private var restartAttempts = 0
    private let maxRestartAttempts = 3
    
    private var cachedContent: SCShareableContent?
    private var lastContentFetch: Date?
    private let cacheTTL: TimeInterval = 10
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
        log("CaptureManager initialized")
    }
    
    deinit {
        healthCheckTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func refreshShareableWindows(preferBundleID: String?) async {
        do {
            let content = try await getShareableContent(forceRefresh: true)
            var list: [ShareableWindow] = []
            
            for w in content.windows {
                let appName = w.owningApplication?.applicationName ?? "?"
                let title = w.title ?? ""
                list.append(.init(id: w.windowID, title: title, appName: appName))
            }
            
            // Sort: prefer VirtualDJ
            list.sort {
                let a = ($0.appName + " " + $0.title).lowercased()
                let b = ($1.appName + " " + $1.title).lowercased()
                return a.contains("virtualdj") && !b.contains("virtualdj")
            }
            
            await MainActor.run {
                self.windowsPublisher.send(list)
            }
        } catch {
            log("Failed to refresh windows: \(error.localizedDescription)")
            await MainActor.run {
                self.windowsPublisher.send([])
            }
        }
    }
    
    func startCapturing(windowID: UInt32) async {
        targetWindowID = windowID
        restartAttempts = 0
        await startCaptureInternal()
    }
    
    func stop() async {
        targetWindowID = nil
        await stopInternal()
    }
    
    // MARK: - Internal Capture Logic
    
    private func startCaptureInternal() async {
        await stopInternal()
        
        guard let windowID = targetWindowID else {
            log("No target window ID set")
            return
        }
        
        do {
            // Force refresh content to get current window state
            let content = try await getShareableContent(forceRefresh: true)
            
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log("Window \(windowID) not found - may be closed")
                await MainActor.run {
                    self.lastError = "Window not found"
                    self.isCapturing = false
                }
                return
            }
            
            log("Starting capture for window: \(window.title ?? "untitled") (ID: \(windowID))")
            
            let filter = SCContentFilter(desktopIndependentWindow: window)
            
            let config = SCStreamConfiguration()
            config.capturesAudio = false
            config.excludesCurrentProcessAudio = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: 4) // 4 FPS
            config.queueDepth = 3
            config.showsCursor = false
            
            // Set resolution to native window size
            config.width = Int(window.frame.width)
            config.height = Int(window.frame.height)
            
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            
            // Add self as output handler - no weak reference issues
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            
            try await newStream.startCapture()
            
            self.stream = newStream
            self.lastFrameTime = Date()
            
            await MainActor.run {
                self.isCapturing = true
                self.lastError = nil
                self.frameCount = 0
            }
            
            // Start health monitoring
            startHealthCheck()
            
            log("Capture started successfully")
            
        } catch {
            log("Failed to start capture: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = error.localizedDescription
                self.isCapturing = false
            }
            
            // Schedule retry if appropriate
            await scheduleRestartIfNeeded()
        }
    }
    
    private func stopInternal() async {
        DispatchQueue.main.async { [weak self] in
            self?.healthCheckTimer?.invalidate()
            self?.healthCheckTimer = nil
        }
        
        if let stream = self.stream {
            do {
                try await stream.stopCapture()
                log("Capture stopped")
            } catch {
                log("Error stopping capture: \(error.localizedDescription)")
            }
        }
        
        self.stream = nil
        
        await MainActor.run {
            self.isCapturing = false
        }
    }
    
    // MARK: - SCStreamOutput (receives frames)
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        guard let imageBuffer = sampleBuffer.imageBuffer else {
            // Empty frame - window might be minimized or occluded
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        guard width > 0, height > 0 else { return }
        
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            return
        }
        
        let size = CGSize(width: width, height: height)
        
        // Update state and emit frame on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastFrameTime = Date()
            self.frameCount += 1
            self.framePublisher.send((cgImage, size))
        }
    }
    
    // MARK: - SCStreamDelegate (Error Handling)
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("Stream stopped with error: \(error.localizedDescription)")
        
        DispatchQueue.main.async { [weak self] in
            self?.lastError = error.localizedDescription
            self?.isCapturing = false
        }
        
        self.stream = nil
        
        // Auto-restart if we still have a target window
        Task {
            await scheduleRestartIfNeeded()
        }
    }
    
    // MARK: - Health Monitoring & Auto-Recovery
    
    private func startHealthCheck() {
        DispatchQueue.main.async { [weak self] in
            self?.healthCheckTimer?.invalidate()
            self?.healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.performHealthCheck()
            }
        }
    }
    
    private func performHealthCheck() {
        guard targetWindowID != nil, isCapturing else { return }
        
        // Check if frames are being received
        if let lastFrame = lastFrameTime {
            let elapsed = Date().timeIntervalSince(lastFrame)
            if elapsed > frameTimeoutSeconds {
                log("Frame timeout detected (\(Int(elapsed))s since last frame) - restarting capture")
                Task {
                    await scheduleRestartIfNeeded()
                }
            }
        }
    }
    
    private func scheduleRestartIfNeeded() async {
        guard targetWindowID != nil else {
            log("No target window - not restarting")
            return
        }
        
        guard restartAttempts < maxRestartAttempts else {
            log("Max restart attempts (\(maxRestartAttempts)) reached - giving up")
            await MainActor.run {
                self.lastError = "Capture failed after \(self.maxRestartAttempts) attempts"
            }
            return
        }
        
        restartAttempts += 1
        let delay = Double(restartAttempts) * 1.0 // Exponential backoff: 1s, 2s, 3s
        
        log("Scheduling restart attempt \(restartAttempts)/\(maxRestartAttempts) in \(delay)s")
        
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        // Check if we still want to capture
        guard targetWindowID != nil else { return }
        
        await startCaptureInternal()
    }
    
    // MARK: - Helpers
    
    private func getShareableContent(forceRefresh: Bool = false) async throws -> SCShareableContent {
        if !forceRefresh,
           let cached = cachedContent,
           let lastFetch = lastContentFetch,
           Date().timeIntervalSince(lastFetch) < cacheTTL {
            return cached
        }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        lastContentFetch = Date()
        return content
    }
    
    private func log(_ message: String) {
        print("[CaptureManager] \(message)")
    }
}
