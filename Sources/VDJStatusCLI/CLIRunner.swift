// CLIRunner.swift
// Main CLI orchestrator - coordinates capture, detection, OSC, and UI

import Foundation
import ScreenCaptureKit
import VDJStatusCore
import AppKit
import Combine

/// Configuration for CLI execution
struct CLIConfig {
    var windowName: String = "VirtualDJ"
    var oscHost: String = "127.0.0.1"
    var oscPort: UInt16 = 9000
    var logInterval: TimeInterval = 2.0
    var verbose: Bool = false
}

/// Main CLI runner - coordinates all components
@MainActor
class CLIRunner {
    let config: CLIConfig
    let logger: CLILogger

    private var captureManager: CaptureManager?
    private var oscSender: OSCSender?
    private var stateMachine: DeckStateManager?
    private var calibration: CalibrationModel!
    private var terminalInput: TerminalInput?
    private var debugWindow: DebugWindowManager?
    private var frameSubscription: AnyCancellable?

    private var detectionTask: Task<Void, Never>?
    private var running = true
    private var latestFrame: CGImage?
    private var lastDetectionTime: Date = .distantPast

    init(config: CLIConfig) {
        self.config = config
        self.logger = CLILogger(verbose: config.verbose)
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
        logger.info("Press 'd' to toggle debug window, 'q' to quit")
        logger.info("")

        // Load calibration
        calibration = CalibrationModel.loadFromDisk() ?? CalibrationModel()
        if calibration.rois.isEmpty {
            logger.warning("No calibration data found!")
            logger.warning("Run the GUI app (VDJStatus.app) first to calibrate ROIs")
            logger.info("Calibration file: ~/Library/Application Support/VDJStatus/vdj_calibration.json")
            logger.info("")
        } else {
            logger.info("✓ Calibration loaded (\(calibration.rois.count) ROIs)")
        }

        // Initialize OSC
        oscSender = OSCSender()
        oscSender?.configure(host: config.oscHost, port: config.oscPort)
        logger.info("✓ OSC configured")

        // Initialize state machine
        stateMachine = DeckStateManager()
        logger.info("✓ FSM initialized")

        // Initialize capture manager
        captureManager = CaptureManager()

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
        let windows = try await SCShareableContent.current().windows

        guard let targetWindow = windows.first(where: {
            $0.title?.contains(config.windowName) == true ||
            $0.owningApplication?.applicationName.contains(config.windowName) == true
        }) else {
            logger.error("❌ Window not found: \(config.windowName)")
            logger.error("   Available windows (first 15):")
            for w in windows.prefix(15) {
                let title = w.title ?? "(no title)"
                let app = w.owningApplication?.applicationName ?? "?"
                logger.error("   - \(app): \(title)")
            }
            throw CLIError.windowNotFound
        }

        logger.info("✓ Found window: \(targetWindow.title ?? "(no title)")")
        logger.info("  App: \(targetWindow.owningApplication?.applicationName ?? "?")")
        logger.info("  Size: \(Int(targetWindow.frame.width))×\(Int(targetWindow.frame.height))")

        // Subscribe to frames from capture manager
        frameSubscription = captureManager?.framePublisher.sink { [weak self] frame in
            Task { @MainActor in
                self?.latestFrame = frame
            }
        }

        // Start capture
        do {
            try await captureManager?.startCapture(for: targetWindow)
            logger.info("✓ Capture started")
        } catch {
            logger.error("❌ Failed to start capture: \(error)")
            throw CLIError.captureError(error)
        }

        logger.info("")
        logger.info("═══════════════════════════════════════════════════")
        logger.info("Status monitoring active (every \(config.logInterval)s)")
        logger.info("═══════════════════════════════════════════════════")
        logger.info("")

        // Initialize debug window manager
        debugWindow = DebugWindowManager()

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
            // Process NSApp events if window exists
            if debugWindow != nil {
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
        captureManager?.stopCapture()
        terminalInput?.stop()
        frameSubscription?.cancel()
        logger.info("✓ Goodbye!")
    }

    /// Start background detection loop
    private func startDetectionLoop() {
        detectionTask = Task { @MainActor in
            while !Task.isCancelled {
                // Check if we have a frame
                guard let frame = latestFrame else {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
                    continue
                }

                // Check if enough time has passed since last detection
                let now = Date()
                guard now.timeIntervalSince(lastDetectionTime) >= config.logInterval else {
                    try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                    continue
                }

                lastDetectionTime = now

                // Run detection
                do {
                    let result = await Detector.detect(frame: frame, calibration: calibration)

                    // Update FSM
                    if let elapsed1 = result.deck1.elapsedSeconds {
                        stateMachine?.handleElapsedReading(deck: 1, elapsed: elapsed1)
                    }
                    if let elapsed2 = result.deck2.elapsedSeconds {
                        stateMachine?.handleElapsedReading(deck: 2, elapsed: elapsed2)
                    }
                    if let fader1 = result.deck1.faderKnobPos {
                        stateMachine?.handleFaderReading(deck: 1, position: fader1)
                    }
                    if let fader2 = result.deck2.faderKnobPos {
                        stateMachine?.handleFaderReading(deck: 2, position: fader2)
                    }

                    // Get master deck from FSM
                    let master = stateMachine?.state.master

                    // Log status
                    logStatus(result: result, master: master)

                    // Update debug window with visual data
                    debugWindow?.update(
                        frame: frame,
                        detection: result,
                        calibration: calibration,
                        fsmState: stateMachine?.state
                    )

                    // Send OSC
                    oscSender?.send(result: result)
                } catch {
                    if config.verbose {
                        logger.error("Detection error: \(error)")
                    }
                }
            }
        }
    }

    /// Log current status to console
    private func logStatus(result: DetectionResult, master: Int?) {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        logger.log("[\(timestamp)]")
        logger.log("  Deck 1: \(result.deck1.artist ?? "?") - \(result.deck1.title ?? "?")")
        logger.log("          \(formatElapsed(result.deck1.elapsedSeconds)) | Fader: \(formatFader(result.deck1.faderKnobPos))")
        logger.log("  Deck 2: \(result.deck2.artist ?? "?") - \(result.deck2.title ?? "?")")
        logger.log("          \(formatElapsed(result.deck2.elapsedSeconds)) | Fader: \(formatFader(result.deck2.faderKnobPos))")

        if let master = master {
            logger.log("  Master: Deck \(master) 🎵")
        } else {
            logger.log("  Master: None")
        }

        logger.log("")
    }

    /// Handle keyboard input
    private func handleKeyPress(_ char: Character) async {
        switch char.lowercased() {
        case "d":
            debugWindow?.toggle()
            if config.verbose {
                logger.debug("Debug window toggled")
            }
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
        // Note: This is a basic implementation
        // In production, you'd use proper signal handling with sigaction
        signal(SIGINT) { _ in
            Task { @MainActor in
                print("\nInterrupted (SIGINT)")
                exit(0)
            }
        }

        signal(SIGTERM) { _ in
            Task { @MainActor in
                print("\nTerminated (SIGTERM)")
                exit(0)
            }
        }
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
