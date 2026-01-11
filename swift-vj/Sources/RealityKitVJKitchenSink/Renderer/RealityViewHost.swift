// RealityViewHost.swift - NSViewRepresentable hosting ARView
// Bridges SwiftUI to RealityKit ARView

import SwiftUI
import RealityKit
import AppKit

struct RealityViewHost: NSViewRepresentable {
    @ObservedObject var coordinator: SceneCoordinator
    
    func makeNSView(context: Context) -> NSView {
        // Return a placeholder view initially
        // The ARView will be set once coordinator.start() completes
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Once ARView is ready, add it as subview
        if let arView = coordinator.arView {
            // Check if already added
            if arView.superview != nsView {
                // Remove any existing subviews
                nsView.subviews.forEach { $0.removeFromSuperview() }
                
                // Add ARView
                arView.frame = nsView.bounds
                arView.autoresizingMask = [.width, .height]
                nsView.addSubview(arView)
            }
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
}
