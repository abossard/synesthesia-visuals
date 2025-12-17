import Foundation
import ArgumentParser
import AppKit
import SwiftUI
import Combine
import ScreenCaptureKit
import Vision
import Network
import CoreImage
import Darwin

// Note: All source files are compiled into this target via symlinks

// Global for terminal restore
private var savedTermios = termios()

// MARK: - CLI State (headless mode)

@MainActor
final class CLIState {
    let capture = CaptureManager()
    var osc = OSCSender()
    var calibration = CalibrationModel()
    let deckStateManager = DeckStateManager()
    
    var latestFrame: CGImage?
    var frameSize: CGSize = .zero
    var isCapturing = false
    var detection: DetectionResult?
    
    private var cancellables = Set<AnyCancellable>()
    private var detectionTimer: Timer?
    
    init() {
        // Load saved calibration
        if let saved = CalibrationModel.loadFromDisk() {
            calibration = saved
            print("[CLI] Loaded calibration with \(saved.rois.count) ROIs")
        }
        
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        capture.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (cgImage, size) in
                self?.latestFrame = cgImage
                self?.frameSize = size
            }
            .store(in: &cancellables)
        
        capture.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] capturing in
                self?.isCapturing = capturing
            }
            .store(in: &cancellables)
    }
    
    func start(host: String, port: UInt16, pollInterval: Double) async {
        osc.configure(host: host, port: port)
        print("[CLI] OSC configured: \(host):\(port)")
        
        // Find VirtualDJ window
        print("[CLI] Scanning for VirtualDJ window...")
        await capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj")
        
        // Wait for window list
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Auto-start capture on first VDJ window
        var foundWindow = false
        capture.windowsPublisher
            .first()
            .sink { [weak self] windows in
                guard let self else { return }
                if let vdj = windows.first(where: { $0.appName.lowercased().contains("virtualdj") }) {
                    print("[CLI] Found VirtualDJ: \(vdj.title)")
                    Task { await self.capture.startCapturing(windowID: vdj.id) }
                    foundWindow = true
                } else if let first = windows.first {
                    print("[CLI] No VirtualDJ found, using first window: \(first.appName) - \(first.title)")
                    Task { await self.capture.startCapturing(windowID: first.id) }
                    foundWindow = true
                } else {
                    print("[CLI] No windows found. Make sure VirtualDJ is running.")
                }
            }
            .store(in: &cancellables)
        
        // Start detection timer
        DispatchQueue.main.async { [weak self] in
            self?.detectionTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.runDetection() }
            }
        }
        
        print("[CLI] Detection loop started (interval: \(pollInterval)s)")
        print("[CLI] Press 'd' to open GUI, 'q' to quit")
    }
    
    func runDetection() {
        guard let frame = latestFrame else { return }
        
        Task.detached {
            let result = await Detector.detect(frame: frame, calibration: self.calibration)
            await MainActor.run {
                self.detection = result
                self.deckStateManager.process(result)
                
                // Update with FSM-determined master
                var finalResult = result
                finalResult.masterDeck = self.deckStateManager.master
                self.detection = finalResult
                
                // Send OSC
                self.osc.send(result: finalResult)
                
                // Print status
                self.printStatus(finalResult)
            }
        }
    }
    
    private func printStatus(_ result: DetectionResult) {
        let d1 = result.deck1
        let d2 = result.deck2
        let master = result.masterDeck.map { "D\($0)" } ?? "?"
        
        let d1Info = "\(d1.artist ?? "?") - \(d1.title ?? "?")"
        let d2Info = "\(d2.artist ?? "?") - \(d2.title ?? "?")"
        let d1Time = d1.elapsedSeconds.map { formatTime($0) } ?? "--:--"
        let d2Time = d2.elapsedSeconds.map { formatTime($0) } ?? "--:--"
        
        print("\r[D1: \(d1Time)] \(d1Info.prefix(30))  |  [D2: \(d2Time)] \(d2Info.prefix(30))  Master: \(master)    ", terminator: "")
        fflush(stdout)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    func stop() {
        detectionTimer?.invalidate()
        Task { await capture.stop() }
    }
}

// MARK: - Main Command

@main
struct VDJStatusCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "vdjstatus",
        abstract: "VirtualDJ status monitor via screen capture + OCR",
        version: "1.0.0"
    )
    
    @Option(name: .shortAndLong, help: "OSC target host")
    var host: String = "127.0.0.1"
    
    @Option(name: .shortAndLong, help: "OSC target port")
    var port: UInt16 = 9000
    
    @Option(name: .long, help: "Detection poll interval in seconds")
    var interval: Double = 1.0
    
    @Flag(name: .shortAndLong, help: "Start with GUI window open")
    var gui: Bool = false
    
    mutating func run() throws {
        print("VDJStatus CLI v1.0.0")
        print("===================")
        
        // Capture options for async block
        let host = self.host
        let port = self.port
        let interval = self.interval
        let showGUI = self.gui
        
        // Schedule async setup on main queue after dispatchMain starts
        DispatchQueue.main.async {
            Task {
                if showGUI {
                    await launchGUIWindow()
                } else {
                    let cliState = await CLIState()
                    await cliState.start(host: host, port: port, pollInterval: interval)
                    
                    // Set up keyboard handling for 'd' and 'q'
                    setupKeyboardHandler(cliState: cliState)
                }
            }
        }
        
        // Run the main loop (required for ScreenCaptureKit callbacks)
        dispatchMain()
    }
}

// MARK: - Free functions for CLI operations (callable from closures)

private func setupKeyboardHandler(cliState: CLIState) {
    // Set terminal to raw mode for single-key input
    tcgetattr(STDIN_FILENO, &savedTermios)
    
    var raw = savedTermios
    raw.c_lflag &= ~UInt(ICANON | ECHO)  // Disable canonical mode and echo
    tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    
    print("[CLI] Press 'd' to open GUI, 'r' to refresh, 'q' to quit")
    
    // Restore terminal on exit
    atexit {
        tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
    }
    
    // Background thread to read keyboard
    DispatchQueue.global().async {
        while true {
            var c: CChar = 0
            let _ = read(STDIN_FILENO, &c, 1)
            
            switch Character(UnicodeScalar(UInt8(bitPattern: c))) {
            case "d", "D":
                print("\n[CLI] Opening GUI...")
                    DispatchQueue.main.sync {
                        launchGUIWindow()
            case "q", "Q":
                print("\n[CLI] Quitting...")
                DispatchQueue.main.async {
                    cliState.stop()
                    Darwin.exit(0)
                }
                
            case "r", "R":
                print("\n[CLI] Refreshing windows...")
                Task {
                    await cliState.capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj")
                }
                
            default:
                break
            }
        }
    }
}

// MARK: - Free function for GUI launch (callable from closures)

@MainActor
private func launchGUIWindow() {
    // Must be called on main thread
    assert(Thread.isMainThread, "launchGUIWindow must be called on main thread")
    
    // Initialize the app if needed
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    
    // Create the SwiftUI window
    let appState = AppState()
    let contentView = ContentView().environmentObject(appState)
    
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "VDJStatus"
    window.contentView = NSHostingView(rootView: contentView)
    window.center()
    window.makeKeyAndOrderFront(nil)
    
    // Activate the app
    app.activate(ignoringOtherApps: true)
}

// MARK: - Import GUI components for 'd' key functionality
// These are symlinked/imported when building with Xcode or SPM

// Note: AppState and ContentView are in the VDJStatus folder
// For SPM CLI, we need to include them in the executable target
// or dynamically load them. For simplicity, we'll duplicate the imports.
