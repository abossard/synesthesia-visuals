// DebugWindow.swift
// Minimal NSApplication debug window for CLI tool
// Toggles visibility on 'd' key press

import AppKit
import Foundation

/// Manages a minimal debug window that can be toggled on/off
@MainActor
class DebugWindowManager {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var isAppActivated = false

    /// Toggle window visibility (show if hidden, hide if visible)
    func toggle() {
        if window == nil || !window!.isVisible {
            show()
        } else {
            hide()
        }
    }

    /// Show the debug window
    private func show() {
        // First-time setup: Initialize NSApplication
        if !isAppActivated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)  // No dock icon
            isAppActivated = true
        }

        // Create window if needed
        if window == nil {
            let frame = NSRect(x: 100, y: 100, width: 700, height: 500)
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]

            window = NSWindow(
                contentRect: frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window?.title = "VDJStatus CLI Debug"
            window?.backgroundColor = NSColor(white: 0.1, alpha: 1.0)

            // Create text view with scroll view
            let scrollView = NSScrollView(frame: frame)
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autoresizingMask = [.width, .height]

            let textView = NSTextView(frame: scrollView.bounds)
            textView.string = "VDJStatus Debug Window\n\nWaiting for detection data...\n\nPress 'd' to toggle this window"
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.textColor = NSColor(white: 0.9, alpha: 1.0)
            textView.backgroundColor = .clear
            textView.autoresizingMask = [.width, .height]

            scrollView.documentView = textView
            window?.contentView = scrollView

            self.textView = textView
        }

        // Show and activate
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide the debug window
    private func hide() {
        window?.orderOut(nil)
    }

    /// Update debug text content
    func updateText(_ text: String) {
        textView?.string = text

        // Scroll to bottom
        if let textView = textView {
            let range = NSRange(location: textView.string.count, length: 0)
            textView.scrollRangeToVisible(range)
        }
    }

    /// Append text to existing content
    func appendText(_ text: String) {
        guard let textView = textView else { return }
        let currentText = textView.string
        textView.string = currentText + "\n" + text

        // Scroll to bottom
        let range = NSRange(location: textView.string.count, length: 0)
        textView.scrollRangeToVisible(range)
    }
}
