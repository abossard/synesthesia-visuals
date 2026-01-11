// AppMain.swift - RealityKit VJ Kitchen Sink Entry Point
// Production-grade RealityKit example for VJ work
// macOS 15+ only, Swift Package Manager, Syphon output

import SwiftUI
import AppKit

@main
struct RealityKitVJKitchenSinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// MARK: - App Delegate for Window Management

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy to regular (foreground GUI app)
        // Without this, SPM-built SwiftUI apps won't show windows
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app is active and frontmost
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Force window creation and display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
