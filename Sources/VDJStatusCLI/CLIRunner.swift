// CLIRunner.swift
// Main CLI orchestrator using AppState (shared with GUI)

import Foundation
import ScreenCaptureKit
import VDJStatusCore
import AppKit

/// Configuration for CLI execution
struct CLIConfig {
    var windowName: String = "VirtualDJ"
    var oscHost: String = "127.0.0.1"
    var oscPort: UInt16 = 9000
    var logInterval: TimeInterval = 2.0
    var verbose: Bool = false
}

/// Main CLI runner - uses AppState from GUI app
@MainActor
class CLIRunner {
    let config: CLIConfig
    let logger: CLILogger

    // Use the same AppState as the GUI app
    private let appState: AppState

    private var terminalInput: TerminalInput?
    private var debugWindow: DebugWindowManager?

    private var detectionTask: Task<Void, Never>?
    private var running = true
    private var lastLogTime: Date = .distantPast
    
    // Signal sources for clean shutdown
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    init(config: CLIConfig) {
        self.config = config
        self.logger = CLILogger(verbose: config.verbose)
        self.appState = AppState()
    }

    /// Main entry point - runs until quit
    func run() async throws {
        // Setup signal handlers for clean shutdown
        setupSignalHandlers()

        logger.info("🚀 VDJStatus CLI starting...")
        logger.info("Target window: \(config.windowName)")
        logger.info("OSC output: \(config.oscHost):\(config.oscPort)")
        logger.info("Log interval: \(config.logInterval)s")
        logger.info("")
        logger.info("Press 'd' to toggle full GUI window, 'q' to quit")
        logger.info("")

        // Load calibration
        appState.loadCalibration()
        if appState.calibration.rois.isEmpty {
            logger.warning("No calibration data found!")
            logger.warning("Press 'd' to open the GUI and calibrate ROIs")
            logger.info("Calibration file: ~/Library/Application Support/VDJStatus/vdj_calibration.json")
            logger.info("")
        } else {
            logger.info("✓ Calibration loaded (\(appState.calibration.rois.count) ROIs)")
        }

        // Configure OSC
        appState.oscHost = config.oscHost
        appState.oscPort = config.oscPort
        appState.oscEnabled = true
        logger.info("✓ OSC configured")
        logger.info("✓ FSM initialized")

        // Request screen recording permission
        logger.info("⚠️  Requesting screen recording permission...")
        logger.info("   (Grant permission in System Settings → Privacy & Security → Screen Recording)")

        let canRecord = try await checkScreenRecordingPermission()
        guard canRecord else {
            logger.error("❌ Screen recording permission denied")
            logger.error("   Enable for Terminal.app (or your terminal emulator) in System Settings")
            throw CLIError.permissionDenied
        }
        logger.info("✓ Screen recording permission granted")

        // Find VirtualDJ window
        logger.info("🔍 Looking for window: \(config.windowName)...")
        await appState.capture.refreshShareableWindows(preferBundleID: "com.atomixproductions.virtualdj")

        guard let targetWindow = appState.windows.first(where: {
            $0.title.contains(config.windowName) ||
            $0.appName.contains(config.windowName)
        }) else {
            logger.error("❌ Window not found: \(config.windowName)")
            logger.error("   Available windows (first 15):")
            for w in appState.windows.prefix(15) {
                logger.error("   - \(w.appName): \(w.title)")
            }
            throw CLIError.windowNotFound
        }

        logger.info("✓ Found window: \(targetWindow.title)")
        logger.info("  App: \(targetWindow.appName)")

        // Select and start capture
        appState.selectedWindowID = targetWindow.id
        // Capture starts automatically via AppState's didSet

        // Wait a moment for capture to start
        try await Task.sleep(nanoseconds: 500_000_000)

        guard appState.isCapturing else {
            logger.error("❌ Failed to start capture")
            throw CLIError.captureError(NSError(domain: "VDJStatus", code: -1))
        }

        logger.info("✓ Capture started")
        logger.info("")
        logger.info("═══════════════════════════════════════════════════")
        logger.info("Status monitoring active (every \(config.logInterval)s)")
        logger.info("═══════════════════════════════════════════════════")
        logger.info("")

        // Initialize debug window manager (shows full GUI on 'd' press)
        debugWindow = DebugWindowManager(appState: appState)

        // Start terminal input handler
        terminalInput = TerminalInput { [weak self] char in
            Task { @MainActor in
                await self?.handleKeyPress(char)
            }
        }
        terminalInput?.start()

        // Start detection loop
        startDetectionLoop()

        // Main run loop
        while running {
            // Process NSApp events if debug window is visible
            if debugWindow?.window?.isVisible == true {
                // Run event loop briefly (non-blocking)
                NSApp.run(mode: .default, before: .distantPast)
            }

            // Sleep briefly
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }

        // Cleanup
        logger.info("")
        logger.info("Shutting down...")
        detectionTask?.cancel()
        appState.stopCapture()
        terminalInput?.stop()
        
        // Cancel signal sources
        sigintSource?.cancel()
        sigtermSource?.cancel()
        
        logger.info("✓ Goodbye!")
    }

    /// Start background detection loop
    private func startDetectionLoop() {
        detectionTask = Task { @MainActor in
            // Start periodic detection (same as GUI app)
            while !Task.isCancelled {
                // Run detection
                appState.runDetectionOnce()

                // Check if enough time has passed since last log
                let now = Date()
                if now.timeIntervalSince(lastLogTime) >= config.logInterval {
                    lastLogTime = now
                    logStatus()
                }

                // Wait for FSM poll interval
                try? await Task.sleep(nanoseconds: UInt64(FSMConfig.default.pollInterval * 1_000_000_000))
            }
        }
    }

    /// Log current status to console
    private func logStatus() {
        guard let detection = appState.detection else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())

        logger.log("[\(timestamp)]")
        logger.log("  Deck 1: \(detection.deck1.artist ?? "?") - \(detection.deck1.title ?? "?")")
        logger.log("          \(formatElapsed(detection.deck1.elapsedSeconds)) | Fader: \(formatFader(detection.deck1.faderKnobPos))")
        logger.log("  Deck 2: \(detection.deck2.artist ?? "?") - \(detection.deck2.title ?? "?")")
        logger.log("          \(formatElapsed(detection.deck2.elapsedSeconds)) | Fader: \(formatFader(detection.deck2.faderKnobPos))")

        if let master = detection.masterDeck {
            logger.log("  Master: Deck \(master) 🎵")
        } else {
            logger.log("  Master: None")
        }

        if config.verbose {
            logger.debug(String(format: "OCR: %.0fms | Avg: %.0fms", appState.lastDetectionMs, appState.avgDetectionMs))
        }

        logger.log("")
    }

    /// Handle keyboard input
    private func handleKeyPress(_ char: Character) async {
        switch char.lowercased() {
        case "d":
            debugWindow?.toggle()
            logger.info(debugWindow?.window?.isVisible == true ? "GUI window opened" : "GUI window closed")
        case "q":
            logger.info("Quit requested")
            running = false
        case "\u{03}":  // Ctrl+C
            logger.info("Interrupted (Ctrl+C)")
            running = false
        default:
            if config.verbose {
                logger.debug("Unknown key: \(char)")
            }
        }
    }

    /// Format elapsed time as M:SS
    private func formatElapsed(_ seconds: Double?) -> String {
        guard let sec = seconds else { return "??:??" }
        let mins = Int(sec) / 60
        let secs = Int(sec) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format fader position as percentage (inverted: 0=top=loud)
    private func formatFader(_ pos: Double?) -> String {
        guard let pos = pos else { return "??%" }
        return String(format: "%3.0f%%", (1.0 - pos) * 100)
    }

    /// Check if screen recording permission is granted
    private func checkScreenRecordingPermission() async throws -> Bool {
        do {
            _ = try await SCShareableContent.current()
            return true
        } catch {
            return false
        }
    }

    /// Setup signal handlers for clean shutdown
    private func setupSignalHandlers() {
        // Use DispatchSourceSignal for proper signal handling with context
        // This allows us to set the running flag and trigger cleanup
        
        // SIGINT (Ctrl+C)
        signal(SIGINT, SIG_IGN)  // Ignore default handler
        sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource?.setEventHandler { [weak self] in
            Task { @MainActor in
                print("\nInterrupted (SIGINT)")
                self?.running = false
            }
        }
        sigintSource?.resume()
        
        // SIGTERM (kill command)
        signal(SIGTERM, SIG_IGN)  // Ignore default handler
        sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource?.setEventHandler { [weak self] in
            Task { @MainActor in
                print("\nTerminated (SIGTERM)")
                self?.running = false
            }
        }
        sigtermSource?.resume()
    }
}

/// CLI-specific errors
enum CLIError: Error, CustomStringConvertible {
    case permissionDenied
    case windowNotFound
    case captureError(Error)

    var description: String {
        switch self {
        case .permissionDenied:
            return "Screen recording permission denied"
        case .windowNotFound:
            return "Target window not found"
        case .captureError(let error):
            return "Capture failed: \(error.localizedDescription)"
        }
    }
}
