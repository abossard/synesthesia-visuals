import Foundation
import AppKit
import SwiftUI

@MainActor
class OverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    
    func setVisible(_ visible: Bool) {
        if visible {
            if panel == nil {
                createPanel()
            }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }
    
    func setInteractive(_ interactive: Bool) {
        panel?.ignoresMouseEvents = !interactive
        panel?.level = interactive ? .floating : .statusBar
    }
    
    func updateOverlayContent(frame: CGImage?, calibration: CalibrationModel, detection: DetectionResult?) {
        guard let hostingView = hostingView else { return }
        // Update SwiftUI view with new data
        hostingView.rootView = OverlayView(
            frame: frame,
            calibration: calibration,
            detection: detection
        )
    }
    
    func followVirtualDJWindow(ownerContains: String) {
        // Find VirtualDJ window and position overlay
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            if owner.lowercased().contains(ownerContains.lowercased()) {
                if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                   let x = bounds["X"],
                   let y = bounds["Y"],
                   let width = bounds["Width"],
                   let height = bounds["Height"] {
                    
                    let frame = NSRect(x: x, y: y, width: width, height: height)
                    panel?.setFrame(frame, display: true)
                    return
                }
            }
        }
    }
    
    private func createPanel() {
        let initialFrame = NSRect(x: 100, y: 100, width: 800, height: 600)
        
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let overlayView = OverlayView(frame: nil, calibration: CalibrationModel(), detection: nil)
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = initialFrame
        
        panel.contentView = hosting
        
        self.panel = panel
        self.hostingView = hosting
    }
}
