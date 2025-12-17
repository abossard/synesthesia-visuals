// main.swift
// Entry point for VDJStatus CLI tool
// Parses arguments and launches CLIRunner

import Foundation

// MARK: - Argument Parsing

/// Parse command-line arguments
func parseArgs() -> CLIConfig {
    let args = Array(CommandLine.arguments.dropFirst())  // Skip program name

    // Default values
    var windowName = "VirtualDJ"
    var oscHost = "127.0.0.1"
    var oscPort: UInt16 = 9000
    var logInterval: TimeInterval = 2.0
    var verbose = false

    var i = 0
    while i < args.count {
        let arg = args[i]

        switch arg {
        case "--window-name", "-w":
            guard i + 1 < args.count else {
                printError("Missing value for \(arg)")
                exit(1)
            }
            i += 1
            windowName = args[i]

        case "--osc-host", "-h":
            guard i + 1 < args.count else {
                printError("Missing value for \(arg)")
                exit(1)
            }
            i += 1
            oscHost = args[i]

        case "--osc-port", "-p":
            guard i + 1 < args.count else {
                printError("Missing value for \(arg)")
                exit(1)
            }
            i += 1
            guard let port = UInt16(args[i]) else {
                printError("Invalid port number: \(args[i])")
                exit(1)
            }
            oscPort = port

        case "--log-interval", "-i":
            guard i + 1 < args.count else {
                printError("Missing value for \(arg)")
                exit(1)
            }
            i += 1
            guard let interval = TimeInterval(args[i]) else {
                printError("Invalid interval: \(args[i])")
                exit(1)
            }
            logInterval = interval

        case "--verbose", "-v":
            verbose = true

        case "--help":
            printHelp()
            exit(0)

        case "--version":
            printVersion()
            exit(0)

        default:
            printError("Unknown argument: \(arg)")
            printError("Use --help for usage information")
            exit(1)
        }

        i += 1
    }

    return CLIConfig(
        windowName: windowName,
        oscHost: oscHost,
        oscPort: oscPort,
        logInterval: logInterval,
        verbose: verbose
    )
}

/// Print help message
func printHelp() {
    print("""
    VDJStatus CLI - VirtualDJ Status Monitor

    USAGE:
        vdjstatus-cli [OPTIONS]

    OPTIONS:
        -w, --window-name NAME    Target window name (default: VirtualDJ)
        -h, --osc-host HOST       OSC destination host (default: 127.0.0.1)
        -p, --osc-port PORT       OSC destination port (default: 9000)
        -i, --log-interval SEC    Status log interval in seconds (default: 2.0)
        -v, --verbose             Enable verbose logging
        --help                    Show this help message
        --version                 Show version information

    KEYBOARD COMMANDS (while running):
        d                         Toggle debug window
        q                         Quit
        Ctrl+C                    Force quit

    EXAMPLES:
        # Run with defaults
        vdjstatus-cli

        # Custom window name and OSC settings
        vdjstatus-cli -w "VirtualDJ 2024" -h 192.168.1.10 -p 9001

        # Verbose logging with 5-second interval
        vdjstatus-cli -v -i 5.0

    SCREEN RECORDING PERMISSION:
        On first run, macOS will prompt for screen recording permission.
        Grant permission for Terminal.app (or your terminal emulator) in:
        System Settings → Privacy & Security → Screen Recording

    CALIBRATION:
        Before using the CLI tool, run the GUI app (VDJStatus.app) once
        to calibrate ROI regions for your VirtualDJ skin.
        Calibration is saved to:
        ~/Library/Application Support/VDJStatus/vdj_calibration.json

    MORE INFO:
        https://github.com/yourusername/VDJStatus
    """)
}

/// Print version information
func printVersion() {
    print("VDJStatus CLI v1.0.0")
    print("macOS ScreenCaptureKit-based VirtualDJ monitor")
}

/// Print error to stderr
func printError(_ message: String) {
    fputs("ERROR: \(message)\n", stderr)
    fflush(stderr)
}

// MARK: - Main Entry Point

@main
struct VDJStatusCLI {
    static func main() async {
        // Parse arguments
        let config = parseArgs()

        // Create and run CLI
        let runner = CLIRunner(config: config)

        do {
            try await runner.run()
        } catch {
            printError("\(error)")
            exit(1)
        }
    }
}
