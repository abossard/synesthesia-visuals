# VDJStatus CLI Tool - Implementation Plan

## Overview
Create a console-based CLI tool that reuses VDJStatus core logic with Swift Package Manager, running in parallel to the Xcode project with shared source code.

---

## Project Goals

✅ **Single Source, Two Outputs**:
- Keep existing Xcode project (VDJStatus.xcodeproj) unchanged
- Add Swift Package Manager setup (Package.swift)
- Share core business logic files between both projects

✅ **CLI Tool Requirements**:
- Terminal-based execution with stdout/stderr logging
- Command-line argument parsing
- ScreenCaptureKit window capture (VirtualDJ)
- Continuous operation with periodic status logs (2-3 seconds)
- Raw terminal input: Press 'd' to toggle debug window
- Minimal NSApplication/AppKit debug window (on demand)

---

## Architecture: Single Source, Dual Build Targets

### Directory Structure (After Implementation)

```
synesthesia-visuals/
├── VDJStatus/                          # Existing Xcode project (UNCHANGED)
│   ├── VDJStatus.xcodeproj
│   └── VDJStatus/
│       ├── VDJStatusApp.swift          # SwiftUI app (GUI only)
│       ├── ContentView.swift           # UI only
│       ├── AppState.swift              # UI state only
│       └── ... (other UI files)
│
├── Package.swift                       # NEW: SwiftPM definition
├── Sources/
│   ├── VDJStatusCore/                  # NEW: Shared core library
│   │   ├── DeckStateMachine.swift      # Symlinked from VDJStatus/
│   │   ├── Detector.swift              # Symlinked from VDJStatus/
│   │   ├── CalibrationModel.swift      # Symlinked from VDJStatus/
│   │   ├── OSC.swift                   # Symlinked from VDJStatus/
│   │   ├── VisionOCR.swift             # Symlinked from VDJStatus/
│   │   └── CaptureManager.swift        # Symlinked from VDJStatus/
│   │
│   └── VDJStatusCLI/                   # NEW: CLI executable
│       ├── main.swift                  # CLI entry point
│       ├── CLIRunner.swift             # Main CLI logic
│       ├── TerminalInput.swift         # Raw stdin handler
│       ├── DebugWindow.swift           # NSApplication/NSWindow toggle
│       └── CLILogger.swift             # Stdout/stderr logger
│
└── Tests/
    └── VDJStatusCoreTests/             # Existing tests (symlinked)
        └── DeckStateMachineTests.swift
```

**Key Strategy**: Use **symbolic links** to share source files without duplicating code.

---

## Step-by-Step Implementation

### Phase 1: Swift Package Manager Setup

#### Step 1: Create Package.swift (Root Directory)

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VDJStatus",
    platforms: [
        .macOS(.v13)  // ScreenCaptureKit requires macOS 13+
    ],
    products: [
        // Shared core library
        .library(
            name: "VDJStatusCore",
            targets: ["VDJStatusCore"]
        ),
        // CLI executable
        .executable(
            name: "vdjstatus-cli",
            targets: ["VDJStatusCLI"]
        ),
    ],
    dependencies: [
        // No external dependencies (all native frameworks)
    ],
    targets: [
        // Core business logic (shared)
        .target(
            name: "VDJStatusCore",
            dependencies: [],
            path: "Sources/VDJStatusCore"
        ),

        // CLI executable
        .executableTarget(
            name: "VDJStatusCLI",
            dependencies: ["VDJStatusCore"],
            path: "Sources/VDJStatusCLI",
            resources: [
                .copy("Resources/Info.plist")  // For screen recording permission
            ]
        ),

        // Tests
        .testTarget(
            name: "VDJStatusCoreTests",
            dependencies: ["VDJStatusCore"],
            path: "Tests/VDJStatusCoreTests"
        ),
    ]
)
```

**Rationale**:
- Separate library target (`VDJStatusCore`) for shared code
- Executable target (`VDJStatusCLI`) depends on core
- Platform constraint ensures ScreenCaptureKit availability
- No external dependencies (all native frameworks)

#### Step 2: Create Symbolic Links for Shared Source

```bash
# Create directory structure
mkdir -p Sources/VDJStatusCore
mkdir -p Sources/VDJStatusCLI/Resources
mkdir -p Tests/VDJStatusCoreTests

# Symlink core business logic files (relative paths)
cd Sources/VDJStatusCore
ln -s ../../VDJStatus/VDJStatus/DeckStateMachine.swift .
ln -s ../../VDJStatus/VDJStatus/Detector.swift .
ln -s ../../VDJStatus/VDJStatus/CalibrationModel.swift .
ln -s ../../VDJStatus/VDJStatus/OSC.swift .
ln -s ../../VDJStatus/VDJStatus/VisionOCR.swift .
ln -s ../../VDJStatus/VDJStatus/CaptureManager.swift .

# Symlink tests
cd ../../Tests/VDJStatusCoreTests
ln -s ../../VDJStatus/VDJStatusTests/DeckStateMachineTests.swift .
```

**Why Symbolic Links?**
- Single source of truth (edit once, affects both projects)
- No code duplication
- Xcode project remains unchanged
- SwiftPM sees files in its expected structure

---

### Phase 2: CLI Implementation

#### Step 3: Argument Parsing (main.swift)

**Decision**: Use **manual parsing** (no dependencies) for simplicity.
- Only 3-4 flags needed: `--window-name`, `--osc-host`, `--osc-port`, `--log-interval`
- Avoids adding Swift Argument Parser dependency
- Keeps CLI lightweight (~100 lines for parser)

```swift
// Sources/VDJStatusCLI/main.swift

import Foundation
import VDJStatusCore

// Parse command-line arguments
struct CLIConfig {
    var windowName: String = "VirtualDJ"
    var oscHost: String = "127.0.0.1"
    var oscPort: UInt16 = 9000
    var logInterval: TimeInterval = 2.0
    var verbose: Bool = false
}

func parseArgs() -> CLIConfig {
    var config = CLIConfig()
    let args = CommandLine.arguments.dropFirst()  // Skip program name

    var i = args.startIndex
    while i < args.endIndex {
        let arg = args[i]
        switch arg {
        case "--window-name", "-w":
            i = args.index(after: i)
            config.windowName = args[i]
        case "--osc-host", "-h":
            i = args.index(after: i)
            config.oscHost = args[i]
        case "--osc-port", "-p":
            i = args.index(after: i)
            if let port = UInt16(args[i]) {
                config.oscPort = port
            }
        case "--log-interval", "-i":
            i = args.index(after: i)
            if let interval = TimeInterval(args[i]) {
                config.logInterval = interval
            }
        case "--verbose", "-v":
            config.verbose = true
        case "--help":
            printHelp()
            exit(0)
        default:
            print("Unknown argument: \(arg)", to: &stderr)
            exit(1)
        }
        i = args.index(after: i)
    }
    return config
}

func printHelp() {
    print("""
    VDJStatus CLI - VirtualDJ Status Monitor

    Usage: vdjstatus-cli [OPTIONS]

    Options:
      -w, --window-name NAME    Target window name (default: VirtualDJ)
      -h, --osc-host HOST       OSC destination host (default: 127.0.0.1)
      -p, --osc-port PORT       OSC destination port (default: 9000)
      -i, --log-interval SEC    Status log interval (default: 2.0)
      -v, --verbose             Enable verbose logging
      --help                    Show this help message

    Keyboard Commands (while running):
      d                         Toggle debug window
      q                         Quit
    """)
}

// Main entry point
let config = parseArgs()

// Run CLI (never returns until quit)
let runner = CLIRunner(config: config)
try! await runner.run()
```

#### Step 4: Raw Terminal Input (TerminalInput.swift)

**Challenge**: Read single keypress without waiting for Enter (raw mode)

**Solution**: Use POSIX `termios` to disable canonical mode + buffering

```swift
// Sources/VDJStatusCLI/TerminalInput.swift

import Foundation
import Darwin

class TerminalInput {
    private var originalTermios: termios?
    private var inputTask: Task<Void, Never>?
    private let onKeyPress: (Character) -> Void

    init(onKeyPress: @escaping (Character) -> Void) {
        self.onKeyPress = onKeyPress
    }

    /// Enable raw mode (disable canonical input, echo)
    func start() {
        // Save original terminal settings
        var term = termios()
        tcgetattr(STDIN_FILENO, &term)
        originalTermios = term

        // Disable canonical mode and echo
        term.c_lflag &= ~(UInt(ICANON | ECHO))
        term.c_cc.16 = 0  // VMIN = 0 (non-blocking)
        term.c_cc.17 = 1  // VTIME = 0.1s timeout

        tcsetattr(STDIN_FILENO, TCSANOW, &term)

        // Start reading loop in background
        inputTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                var char: UInt8 = 0
                let result = read(STDIN_FILENO, &char, 1)
                if result > 0, let scalar = UnicodeScalar(char) {
                    self?.onKeyPress(Character(scalar))
                }
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            }
        }
    }

    /// Restore original terminal settings
    func stop() {
        inputTask?.cancel()
        if var term = originalTermios {
            tcsetattr(STDIN_FILENO, TCSANOW, &term)
        }
    }

    deinit {
        stop()
    }
}
```

**Key Details**:
- `ICANON` disabled = no line buffering (read char-by-char)
- `ECHO` disabled = don't print typed characters
- Non-blocking read with 0.1s timeout
- Background `Task` for async reading
- Restore original settings on exit (critical for terminal sanity!)

#### Step 5: Debug Window Toggle (DebugWindow.swift)

**Challenge**: Create NSApplication event loop without blocking main thread

**Solution**:
1. Initialize `NSApplication.shared` on first press
2. Create window, but run event loop on background thread
3. Use `RunLoop.current.run()` in limited mode

```swift
// Sources/VDJStatusCLI/DebugWindow.swift

import AppKit
import Foundation

@MainActor
class DebugWindowManager {
    private var window: NSWindow?
    private var isAppActivated = false

    func toggle() {
        if window == nil || !window!.isVisible {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        // First-time setup: Initialize NSApplication
        if !isAppActivated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)  // No dock icon
            isAppActivated = true
        }

        // Create window if needed
        if window == nil {
            let frame = NSRect(x: 100, y: 100, width: 600, height: 400)
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]

            window = NSWindow(
                contentRect: frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window?.title = "VDJStatus Debug"
            window?.backgroundColor = .darkGray

            // Simple content view with text
            let textView = NSTextView(frame: frame)
            textView.string = "Debug Window\n\nPress 'd' to toggle"
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            textView.textColor = .white
            textView.backgroundColor = .clear

            window?.contentView = textView
        }

        // Show and activate
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hide() {
        window?.orderOut(nil)
    }

    /// Update debug text (optional - can expand later)
    func updateText(_ text: String) {
        guard let textView = window?.contentView as? NSTextView else { return }
        textView.string = text
    }
}
```

**Key Details**:
- `setActivationPolicy(.accessory)` = no Dock icon, can still show windows
- Window persists after creation (just show/hide)
- `makeKeyAndOrderFront()` brings window to front
- `orderOut()` hides without destroying
- `@MainActor` ensures thread safety

#### Step 6: Main CLI Runner (CLIRunner.swift)

**Integrates**:
- ScreenCaptureKit capture (via `CaptureManager`)
- Detection loop (via `Detector` + `DeckStateMachine`)
- OSC output (via `OSCSender`)
- Terminal input (via `TerminalInput`)
- Debug window (via `DebugWindowManager`)
- Logging (via `CLILogger`)

```swift
// Sources/VDJStatusCLI/CLIRunner.swift

import Foundation
import ScreenCaptureKit
import VDJStatusCore
import AppKit

@MainActor
class CLIRunner {
    let config: CLIConfig
    let logger: CLILogger

    private var captureManager: CaptureManager!
    private var oscSender: OSCSender!
    private var stateMachine: DeckStateManager!
    private var calibration: CalibrationModel!
    private var terminalInput: TerminalInput!
    private var debugWindow: DebugWindowManager!

    private var detectionTask: Task<Void, Never>?
    private var running = true

    init(config: CLIConfig) {
        self.config = config
        self.logger = CLILogger(verbose: config.verbose)
    }

    func run() async throws {
        logger.info("🚀 VDJStatus CLI starting...")
        logger.info("Target window: \(config.windowName)")
        logger.info("OSC output: \(config.oscHost):\(config.oscPort)")
        logger.info("Log interval: \(config.logInterval)s")
        logger.info("")
        logger.info("Press 'd' to toggle debug window, 'q' to quit")
        logger.info("")

        // Load calibration
        calibration = CalibrationModel.loadFromDisk() ?? CalibrationModel()
        logger.info("✓ Calibration loaded (\(calibration.rois.count) ROIs)")

        // Initialize OSC
        oscSender = OSCSender()
        oscSender.configure(host: config.oscHost, port: config.oscPort)
        logger.info("✓ OSC configured")

        // Initialize state machine
        stateMachine = DeckStateManager()
        logger.info("✓ FSM initialized")

        // Initialize capture manager
        captureManager = CaptureManager()

        // Request screen recording permission
        logger.info("⚠️  Requesting screen recording permission...")
        logger.info("   (Grant permission in System Settings → Privacy & Security)")

        let canRecord = try await checkScreenRecordingPermission()
        guard canRecord else {
            logger.error("❌ Screen recording permission denied")
            logger.error("   Enable for Terminal.app in System Settings")
            throw CLIError.permissionDenied
        }
        logger.info("✓ Screen recording permission granted")

        // Find VirtualDJ window
        logger.info("🔍 Looking for window: \(config.windowName)...")
        let windows = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ).windows

        guard let targetWindow = windows.first(where: {
            $0.title?.contains(config.windowName) == true
        }) else {
            logger.error("❌ Window not found: \(config.windowName)")
            logger.error("   Available windows:")
            for w in windows.prefix(10) {
                logger.error("   - \(w.title ?? "(untitled)")")
            }
            throw CLIError.windowNotFound
        }

        logger.info("✓ Found window: \(targetWindow.title ?? "?")")
        logger.info("  Size: \(Int(targetWindow.frame.width))×\(Int(targetWindow.frame.height))")

        // Start capture
        try await captureManager.startCapture(for: targetWindow)
        logger.info("✓ Capture started")
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
        terminalInput.start()

        // Start detection loop
        startDetectionLoop()

        // Keep running until quit
        while running {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            // Process NSApp events if window exists
            if debugWindow != nil {
                NSApp.run(mode: .default, before: .distantPast)
            }
        }

        // Cleanup
        logger.info("")
        logger.info("Shutting down...")
        detectionTask?.cancel()
        captureManager.stopCapture()
        terminalInput.stop()
        logger.info("✓ Goodbye!")
    }

    private func startDetectionLoop() {
        detectionTask = Task { @MainActor in
            while !Task.isCancelled {
                // Wait for next frame
                guard let frame = captureManager.latestFrame else {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
                    continue
                }

                // Run detection
                let result = await Detector.detect(frame: frame, calibration: calibration)

                // Update FSM
                if let elapsed1 = result.deck1.elapsedSeconds {
                    stateMachine.handleElapsedReading(deck: 1, elapsed: elapsed1)
                }
                if let elapsed2 = result.deck2.elapsedSeconds {
                    stateMachine.handleElapsedReading(deck: 2, elapsed: elapsed2)
                }
                if let fader1 = result.deck1.faderKnobPos {
                    stateMachine.handleFaderReading(deck: 1, position: fader1)
                }
                if let fader2 = result.deck2.faderKnobPos {
                    stateMachine.handleFaderReading(deck: 2, position: fader2)
                }

                // Get master deck from FSM
                let master = stateMachine.state.master

                // Log status
                logStatus(result: result, master: master)

                // Send OSC
                oscSender.send(result: result)

                // Wait for next log interval
                try? await Task.sleep(nanoseconds: UInt64(config.logInterval * 1_000_000_000))
            }
        }
    }

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

        // Update debug window if visible
        debugWindow?.updateText(formatDebugInfo(result: result, master: master))
    }

    private func handleKeyPress(_ char: Character) async {
        switch char.lowercased() {
        case "d":
            debugWindow.toggle()
            logger.info("Debug window toggled")
        case "q":
            logger.info("Quit requested")
            running = false
        default:
            if config.verbose {
                logger.debug("Unknown key: \(char)")
            }
        }
    }

    private func formatElapsed(_ seconds: Double?) -> String {
        guard let sec = seconds else { return "??:??" }
        let mins = Int(sec) / 60
        let secs = Int(sec) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatFader(_ pos: Double?) -> String {
        guard let pos = pos else { return "??%" }
        return String(format: "%3.0f%%", (1.0 - pos) * 100)  // Invert: 0=top=loud
    }

    private func formatDebugInfo(result: DetectionResult, master: Int?) -> String {
        """
        VDJStatus Debug Window
        ════════════════════════════════════════

        Deck 1:
          Artist:  \(result.deck1.artist ?? "?")
          Title:   \(result.deck1.title ?? "?")
          Elapsed: \(formatElapsed(result.deck1.elapsedSeconds))
          Fader:   \(formatFader(result.deck1.faderKnobPos))

        Deck 2:
          Artist:  \(result.deck2.artist ?? "?")
          Title:   \(result.deck2.title ?? "?")
          Elapsed: \(formatElapsed(result.deck2.elapsedSeconds))
          Fader:   \(formatFader(result.deck2.faderKnobPos))

        Master Deck: \(master.map { "Deck \($0)" } ?? "None")

        ════════════════════════════════════════
        Press 'd' to toggle this window
        Press 'q' to quit
        """
    }

    private func checkScreenRecordingPermission() async throws -> Bool {
        // ScreenCaptureKit automatically requests permission
        // We just try to get content and see if it works
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return true
        } catch {
            return false
        }
    }
}

enum CLIError: Error {
    case permissionDenied
    case windowNotFound
}
```

**Key Features**:
- Async/await throughout
- Graceful error handling with clear messages
- Periodic status logging (configurable interval)
- Non-blocking keyboard input
- NSApp event loop integration (only when window exists)
- Clean shutdown on 'q' press

#### Step 7: Logger (CLILogger.swift)

```swift
// Sources/VDJStatusCLI/CLILogger.swift

import Foundation

struct CLILogger {
    let verbose: Bool

    private var stdout = FileHandle.standardOutput
    private var stderr = FileHandle.standardError

    func log(_ message: String) {
        print(message, to: &stdout)
    }

    func info(_ message: String) {
        print(message, to: &stdout)
    }

    func error(_ message: String) {
        print("ERROR: \(message)", to: &stderr)
    }

    func debug(_ message: String) {
        if verbose {
            print("DEBUG: \(message)", to: &stderr)
        }
    }
}

// Extension for stderr writing
extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            try? write(contentsOf: data)
        }
    }
}
```

---

### Phase 3: Permissions & Info.plist

#### Step 8: Screen Recording Permission

**How macOS Screen Recording Permissions Work**:

**Development (Terminal.app)**:
- When running via `swift run`, the permission request is attributed to **Terminal.app**
- System Settings → Privacy & Security → Screen Recording → Enable "Terminal.app"
- First run will show system prompt
- Subsequent runs work immediately

**Distribution (Standalone Binary)**:
- Copy binary from `.build/release/vdjstatus-cli` to `/usr/local/bin/`
- Permission is attributed to the **binary itself** (not Terminal)
- Requires embedded `Info.plist` with usage description

**Info.plist for CLI Tool**:

```xml
<!-- Sources/VDJStatusCLI/Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vdjstatus.cli</string>
    <key>CFBundleName</key>
    <string>VDJStatus CLI</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>NSSupportsScreenRecordingPermission</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>VDJStatus needs screen recording permission to capture the VirtualDJ window for real-time monitoring.</string>
</dict>
</plist>
```

**SwiftPM Integration**:
- Add `.copy("Resources/Info.plist")` to executable target
- SwiftPM bundles resources into binary
- Permission prompt shows usage description

**Alternative: .app Wrapper for Distribution**:
If standalone binary permission is problematic:

```bash
# Create minimal .app bundle
mkdir -p VDJStatusCLI.app/Contents/MacOS
mkdir -p VDJStatusCLI.app/Contents/Resources

# Copy binary
cp .build/release/vdjstatus-cli VDJStatusCLI.app/Contents/MacOS/

# Copy Info.plist
cp Sources/VDJStatusCLI/Resources/Info.plist VDJStatusCLI.app/Contents/

# Run as .app (double-click or `open`)
open VDJStatusCLI.app
```

---

### Phase 4: Build & Run

#### Step 9: Terminal Commands

**Build (Debug)**:
```bash
cd /home/user/synesthesia-visuals
swift build
```

**Build (Release, Optimized)**:
```bash
swift build -c release
```

**Run (Development)**:
```bash
# Run with default settings
swift run vdjstatus-cli

# Run with custom arguments
swift run vdjstatus-cli -- \
    --window-name "VirtualDJ" \
    --osc-host 127.0.0.1 \
    --osc-port 9000 \
    --log-interval 3.0 \
    --verbose

# Note: The `--` separates Swift arguments from program arguments
```

**Run (Installed Binary)**:
```bash
# Copy to PATH
sudo cp .build/release/vdjstatus-cli /usr/local/bin/

# Run from anywhere
vdjstatus-cli --help
vdjstatus-cli --verbose
```

**Testing**:
```bash
# Run unit tests
swift test

# Run specific test
swift test --filter DeckStateMachineTests
```

**Cleanup**:
```bash
# Remove build artifacts
swift package clean

# Remove build directory entirely
rm -rf .build/
```

---

### Phase 5: Common Failure Modes

#### Failure Mode 1: Screen Recording Permission Denied

**Symptoms**:
```
⚠️  Requesting screen recording permission...
❌ Screen recording permission denied
   Enable for Terminal.app in System Settings
```

**Solution**:
1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable checkbox for **Terminal.app** (or your terminal emulator)
3. Restart terminal and run again

**Check Permission Status**:
```bash
# Query TCC database (Terminal.app must be enabled)
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value FROM access WHERE service='kTCCServiceScreenCapture';"
```

---

#### Failure Mode 2: VirtualDJ Window Not Found

**Symptoms**:
```
🔍 Looking for window: VirtualDJ...
❌ Window not found: VirtualDJ
   Available windows:
   - Safari
   - Terminal
   - Finder
```

**Solutions**:
1. **Launch VirtualDJ** before running CLI
2. **Check window title**: VirtualDJ window might have different title
   ```bash
   # List all windows to find exact title
   vdjstatus-cli --window-name "Virtual"  # Try partial match
   ```
3. **Use --window-name flag** with exact title:
   ```bash
   vdjstatus-cli --window-name "VirtualDJ 2024 - Home Edition"
   ```

---

#### Failure Mode 3: No Calibration File

**Symptoms**:
```
✓ Calibration loaded (0 ROIs)
```

**Impact**: Detection will fail (no ROIs defined)

**Solution**:
1. Run the **GUI app (VDJStatus.app)** first
2. Perform calibration (draw ROIs for decks 1 & 2)
3. Calibration saved to `~/Library/Application Support/VDJStatus/vdj_calibration.json`
4. CLI tool will automatically load this file

**Workaround**: CLI could theoretically support interactive calibration, but GUI is recommended.

---

#### Failure Mode 4: ScreenCaptureKit Capture Errors

**Symptoms**:
```
ERROR: Capture failed: SCStreamError
```

**Common Causes**:
- **Window closed**: VirtualDJ quit during capture
- **Display change**: Screen resolution changed, external monitor disconnected
- **System sleep**: Mac woke from sleep

**Handling in Code**:
- `CaptureManager` already implements **exponential backoff retry** (max 3 attempts)
- **Health check timer** detects frame timeout (5 seconds)
- **Auto-recovery**: Restarts capture stream automatically

**User Action**: CLI logs error and attempts recovery. If persistent:
1. Restart VirtualDJ
2. Restart CLI tool
3. Check Console.app for system-level errors

---

#### Failure Mode 5: Terminal Input Not Working

**Symptoms**:
- Pressing 'd' or 'q' has no effect
- Terminal displays typed characters instead of raw input

**Causes**:
- **Signal interrupt**: Ctrl+C sends SIGINT before restoring terminal settings
- **Unclean exit**: App crashed without calling `terminalInput.stop()`

**Solution**:
```bash
# Manually restore terminal
reset

# Or type blindly:
stty sane
```

**Prevention**: CLI calls `terminalInput.stop()` in:
- Normal shutdown (pressing 'q')
- Signal handlers (SIGINT, SIGTERM)
- `deinit` of `TerminalInput`

Add signal handler in `main.swift`:
```swift
signal(SIGINT) { _ in
    // Cleanup and exit
    terminalInput?.stop()
    exit(0)
}
```

---

#### Failure Mode 6: Debug Window Not Appearing

**Symptoms**:
- Press 'd', but no window shows
- Console shows "Debug window toggled" but nothing visible

**Causes**:
1. **macOS Focus Assist**: Window opens on different space/desktop
2. **NSApp not activated**: Activation policy set incorrectly
3. **Window created off-screen**: Frame outside visible area

**Solutions**:
1. **Check all desktops/spaces** (Cmd+↑ / Mission Control)
2. **Force activation**:
   ```swift
   NSApp.activate(ignoringOtherApps: true)
   window?.makeKeyAndOrderFront(nil)
   ```
3. **Log window creation**:
   ```swift
   logger.debug("Window created: \(window?.frame)")
   ```

---

### Phase 6: Architecture Notes

#### Thread Safety

**Main Thread (@MainActor)**:
- `CLIRunner` (app state)
- `DebugWindowManager` (AppKit must run on main thread)
- `DeckStateManager` (FSM state updates)

**Background Threads**:
- `TerminalInput` (stdin reading)
- `CaptureManager` (ScreenCaptureKit callbacks)
- `Detector` (Vision OCR - automatically dispatches to background)

**Synchronization**:
- Use `Task { @MainActor in ... }` to dispatch UI updates
- `CaptureManager.latestFrame` is thread-safe (atomic property)

---

#### NSApplication Event Loop Integration

**Challenge**: NSApp.run() is **blocking** - can't call in main thread without freezing CLI.

**Solution**: Run event loop in **limited mode** (non-blocking):
```swift
while running {
    // Process NSApp events briefly
    NSApp.run(mode: .default, before: .distantPast)  // Returns immediately

    // Continue CLI work
    try await Task.sleep(nanoseconds: 100_000_000)
}
```

**Alternative (Not Used)**: Run NSApp on separate thread
- Requires thread-safe window management
- More complex, unnecessary for simple debug window

---

#### Memory Management

**Retain Cycles**:
- `TerminalInput` uses `[weak self]` in closure to avoid retaining `CLIRunner`
- `Task` captures are checked for strong references

**Resource Cleanup**:
- `deinit` in `TerminalInput` restores terminal
- `captureManager.stopCapture()` releases ScreenCaptureKit stream
- `detectionTask?.cancel()` stops background detection loop

---

## Summary: Single Source Strategy

### What Gets Shared (Symlinked)
✅ **Core business logic** (6 files, ~1,243 lines):
- DeckStateMachine.swift
- Detector.swift
- CalibrationModel.swift
- OSC.swift
- VisionOCR.swift
- CaptureManager.swift

### What Stays Separate

**Xcode Project (GUI)**:
- VDJStatusApp.swift (SwiftUI @main)
- ContentView.swift, CalibrationCanvas.swift, MiniPreviewView.swift
- AppState.swift (@ObservableObject)
- Info.plist, entitlements

**CLI Project**:
- main.swift, CLIRunner.swift
- TerminalInput.swift, DebugWindow.swift
- CLILogger.swift
- Info.plist (different, for CLI permissions)

### Build System Coexistence

**Xcode Project**:
```bash
# Open and build in Xcode
open VDJStatus/VDJStatus.xcodeproj

# Or via command line
xcodebuild -project VDJStatus/VDJStatus.xcodeproj -scheme VDJStatus build
```

**SwiftPM Project**:
```bash
# Build CLI only
swift build --product vdjstatus-cli

# Build shared library only
swift build --product VDJStatusCore

# Build everything
swift build
```

**No Conflicts**: Xcode and SwiftPM maintain separate build directories:
- Xcode: `VDJStatus/DerivedData/`
- SwiftPM: `.build/`

---

## Implementation Checklist

- [ ] Create `Package.swift` in repository root
- [ ] Create `Sources/` directory structure
- [ ] Create symbolic links for 6 core files
- [ ] Create `Sources/VDJStatusCLI/main.swift`
- [ ] Create `Sources/VDJStatusCLI/CLIRunner.swift`
- [ ] Create `Sources/VDJStatusCLI/TerminalInput.swift`
- [ ] Create `Sources/VDJStatusCLI/DebugWindow.swift`
- [ ] Create `Sources/VDJStatusCLI/CLILogger.swift`
- [ ] Create `Sources/VDJStatusCLI/Resources/Info.plist`
- [ ] Symlink tests to `Tests/VDJStatusCoreTests/`
- [ ] Test build: `swift build`
- [ ] Test run: `swift run vdjstatus-cli --help`
- [ ] Verify Xcode project still builds (unchanged)
- [ ] Grant screen recording permission
- [ ] Run with VirtualDJ open
- [ ] Test 'd' key (debug window toggle)
- [ ] Test 'q' key (clean exit)
- [ ] Verify OSC output (with external listener)
- [ ] Run unit tests: `swift test`
- [ ] Document in README.md
- [ ] Commit changes (Package.swift, Sources/, README)

---

## Next Steps

1. **Implement** all CLI source files as detailed above
2. **Test** with VirtualDJ running
3. **Extend** debug window to show live detection results (frame preview, ROI overlay)
4. **Add** interactive calibration mode for CLI (optional stretch goal)
5. **Package** as standalone .app for distribution (optional)
6. **Document** usage in main README

---

**Total Estimated Implementation**: ~800 lines of new Swift code (CLI-specific), plus ~50 lines of configuration (Package.swift, Info.plist).

**Reused Code**: ~1,243 lines (shared core logic via symlinks).

**Result**: Professional-grade CLI tool with full feature parity (minus GUI-specific features like interactive calibration), built on a clean, maintainable architecture.
