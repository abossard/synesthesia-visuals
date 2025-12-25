import Cocoa
import Metal

// Main entry point for SwiftVJ application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Run the application
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
