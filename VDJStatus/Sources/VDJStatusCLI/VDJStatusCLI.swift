import Foundation
import ArgumentParser
import AppKit
import SwiftUI

// Note: All source files are compiled into this target via symlinks

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
    
    mutating func run() throws {
        // Store OSC config in UserDefaults for AppState to pick up
        UserDefaults.standard.set(host, forKey: "oscHost")
        UserDefaults.standard.set(Int(port), forKey: "oscPort")
        
        // Launch the SwiftUI app on main thread
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            
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
            
            app.activate(ignoringOtherApps: true)
            app.run()
        }
    }
}
