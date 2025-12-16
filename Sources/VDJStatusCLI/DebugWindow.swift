// DebugWindow.swift
// Shows the COMPLETE GUI application window from the Xcode project
// Full ContentView with all controls, calibration, FSM diagram, everything

import AppKit
import SwiftUI
import Foundation
import VDJStatusCore

/// Manages the full GUI application window (same as Xcode project)
@MainActor
class DebugWindowManager {
    private(set) var window: NSWindow?  // Accessible for visibility checks
    private var hostingController: NSHostingController<ContentView>?
    private var isAppActivated = false
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Toggle window visibility (show if hidden, hide if visible)
    func toggle() {
        if window == nil || !window!.isVisible {
            show()
        } else {
            hide()
        }
    }

    /// Show the full GUI window
    private func show() {
        guard let appState = appState else { return }

        // First-time setup: Initialize NSApplication
        if !isAppActivated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)  // Full app mode with dock icon
            isAppActivated = true
        }

        // Create window if needed
        if window == nil {
            // Create the full SwiftUI ContentView (same as GUI app)
            let contentView = ContentView()
                .environmentObject(appState)

            // Create hosting controller
            let hostingController = NSHostingController(rootView: contentView)
            self.hostingController = hostingController

            // Create window with same size as GUI app
            let frame = NSRect(x: 100, y: 100, width: 800, height: 900)
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]

            window = NSWindow(
                contentRect: frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window?.title = "VDJStatus (CLI Mode)"
            window?.contentViewController = hostingController
            window?.minSize = NSSize(width: 700, height: 700)

            // Center on screen
            window?.center()
        }

        // Show and activate
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide the GUI window
    private func hide() {
        window?.orderOut(nil)
    }
}
