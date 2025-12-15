import Cocoa
import Metal
import MetalKit

/// Main application delegate for SwiftVJ
/// Manages the window, rendering engine, OSC handler, and Syphon servers
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var renderEngine: MetalRenderEngine?
    var oscHandler: OSCHandler?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("SwiftVJ starting...")
        
        // Create main window (1920x1080 HD)
        let windowRect = NSRect(x: 100, y: 100, width: 1920, height: 1080)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftVJ - Shader + Karaoke Renderer"
        window.makeKeyAndOrderFront(nil)
        
        // Initialize Metal render engine
        guard let engine = MetalRenderEngine(frame: windowRect) else {
            NSLog("ERROR: Failed to initialize Metal render engine")
            NSApp.terminate(nil)
            return
        }
        
        renderEngine = engine
        window.contentView = engine.mtkView
        
        // Initialize OSC handler on port 9000 (matches python-vj default)
        oscHandler = OSCHandler(port: 9000, engine: engine)
        
        NSLog("SwiftVJ initialized")
        NSLog("- Metal device: \(engine.device.name)")
        NSLog("- OSC listening on port 9000")
        NSLog("- Syphon servers: ShaderOutput, KaraokeFullLyrics, KaraokeRefrain, KaraokeSongInfo")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("SwiftVJ shutting down...")
        renderEngine?.cleanup()
        oscHandler?.stop()
    }
}
