// DebugWindow.swift
// Visual debug window for CLI tool - matches GUI app's MiniPreviewView
// Shows captured frame with ROI overlays, detected text, and fader positions

import AppKit
import Foundation
import VDJStatusCore

/// Manages a visual debug window that shows the same content as the GUI app
@MainActor
class DebugWindowManager {
    private var window: NSWindow?
    private var previewView: PreviewOverlayView?
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
            let frame = NSRect(x: 100, y: 100, width: 900, height: 700)
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]

            window = NSWindow(
                contentRect: frame,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window?.title = "VDJStatus CLI Debug (Press 'd' to close)"
            window?.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
            window?.minSize = NSSize(width: 600, height: 400)

            // Create preview view
            let previewView = PreviewOverlayView(frame: frame.insetBy(dx: 20, dy: 20))
            previewView.autoresizingMask = [.width, .height]
            window?.contentView = previewView

            self.previewView = previewView
        }

        // Show and activate
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hide the debug window
    private func hide() {
        window?.orderOut(nil)
    }

    /// Update with new frame and detection data
    func update(frame: CGImage?, detection: DetectionResult?, calibration: CalibrationModel, fsmState: MasterState?) {
        previewView?.update(frame: frame, detection: detection, calibration: calibration, fsmState: fsmState)
    }
}

// MARK: - Preview Overlay View

/// Custom NSView that draws the captured frame with overlays
private class PreviewOverlayView: NSView {
    private var frame: CGImage?
    private var detection: DetectionResult?
    private var calibration: CalibrationModel = CalibrationModel()
    private var fsmState: MasterState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(frame: CGImage?, detection: DetectionResult?, calibration: CalibrationModel, fsmState: MasterState?) {
        self.frame = frame
        self.detection = detection
        self.calibration = calibration
        self.fsmState = fsmState
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Draw black background
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)

        // Draw frame if available
        guard let frame = frame else {
            drawNoFrameMessage(in: ctx)
            return
        }

        // Calculate aspect-fit rect for frame
        let frameSize = CGSize(width: frame.width, height: frame.height)
        let imageRect = aspectFitRect(for: frameSize, in: bounds.insetBy(dx: 10, dy: 10))

        // Draw the captured frame
        ctx.draw(frame, in: imageRect)

        // Draw ROI rectangles from calibration
        drawROIRectangles(in: ctx, imageRect: imageRect)

        // Draw detected text boxes (red)
        if let detection = detection {
            drawDetectedTextBoxes(detection: detection, in: ctx, imageRect: imageRect)
            drawFaderIndicators(detection: detection, in: ctx, imageRect: imageRect)
            drawDetectionOverlay(detection: detection, in: ctx, imageRect: imageRect)
        }

        // Draw FSM state info
        if let fsmState = fsmState {
            drawFSMState(fsmState: fsmState, in: ctx)
        }
    }

    private func drawNoFrameMessage(in ctx: CGContext) {
        let message = "Waiting for capture...\n\nPress 'd' to close this window"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.gray
        ]
        let attrStr = NSAttributedString(string: message, attributes: attrs)
        let size = attrStr.size()
        let rect = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        attrStr.draw(in: rect)
    }

    private func drawROIRectangles(in ctx: CGContext, imageRect: CGRect) {
        for (key, normalizedRect) in calibration.rois {
            // Convert normalized 0-1 rect to pixel rect within imageRect
            let pixelRect = CGRect(
                x: imageRect.origin.x + normalizedRect.origin.x * imageRect.width,
                y: imageRect.origin.y + normalizedRect.origin.y * imageRect.height,
                width: normalizedRect.width * imageRect.width,
                height: normalizedRect.height * imageRect.height
            )

            // Draw ROI rectangle (green for deck 1, magenta for deck 2)
            let color = key.rawValue.hasPrefix("d1") ? NSColor.cyan : NSColor.magenta
            ctx.setStrokeColor(color.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(pixelRect)

            // Draw label
            let label = key.label
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: NSColor.white,
                .backgroundColor: color.withAlphaComponent(0.8)
            ]
            let attrStr = NSAttributedString(string: " \(label) ", attributes: attrs)
            attrStr.draw(at: CGPoint(x: pixelRect.minX, y: pixelRect.maxY + 2))
        }
    }

    private func drawDetectedTextBoxes(detection: DetectionResult, in ctx: CGContext, imageRect: CGRect) {
        // Collect all OCR detections
        let allDetections = detection.deck1.artistDetections +
                           detection.deck1.titleDetections +
                           detection.deck1.elapsedDetections +
                           detection.deck2.artistDetections +
                           detection.deck2.titleDetections +
                           detection.deck2.elapsedDetections

        for det in allDetections {
            // Convert normalized rect to pixel rect
            let pixelRect = CGRect(
                x: imageRect.origin.x + det.frameRect.origin.x * imageRect.width,
                y: imageRect.origin.y + det.frameRect.origin.y * imageRect.height,
                width: det.frameRect.width * imageRect.width,
                height: det.frameRect.height * imageRect.height
            )

            // Draw red box around detected text
            ctx.setStrokeColor(NSColor.red.cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(pixelRect)

            // Draw text above box
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.red
            ]
            let attrStr = NSAttributedString(string: " \(det.text) ", attributes: attrs)
            attrStr.draw(at: CGPoint(x: pixelRect.minX, y: pixelRect.maxY + 2))
        }
    }

    private func drawFaderIndicators(detection: DetectionResult, in ctx: CGContext, imageRect: CGRect) {
        // Deck 1 fader
        if let faderROI = detection.deck1.faderROI, let knobPos = detection.deck1.faderKnobPos {
            drawFaderKnob(
                faderROI: faderROI,
                knobPos: knobPos,
                confidence: detection.deck1.faderConfidence ?? 0,
                label: "D1",
                in: ctx,
                imageRect: imageRect
            )
        }

        // Deck 2 fader
        if let faderROI = detection.deck2.faderROI, let knobPos = detection.deck2.faderKnobPos {
            drawFaderKnob(
                faderROI: faderROI,
                knobPos: knobPos,
                confidence: detection.deck2.faderConfidence ?? 0,
                label: "D2",
                in: ctx,
                imageRect: imageRect
            )
        }
    }

    private func drawFaderKnob(
        faderROI: CGRect,
        knobPos: Double,
        confidence: Double,
        label: String,
        in ctx: CGContext,
        imageRect: CGRect
    ) {
        // Convert normalized fader ROI to pixel rect
        let roiPixelRect = CGRect(
            x: imageRect.origin.x + faderROI.origin.x * imageRect.width,
            y: imageRect.origin.y + faderROI.origin.y * imageRect.height,
            width: faderROI.width * imageRect.width,
            height: faderROI.height * imageRect.height
        )

        // Knob Y position (0 = top, 1 = bottom)
        let knobY = roiPixelRect.origin.y + knobPos * roiPixelRect.height

        // Draw horizontal red line at knob position
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(
            x: roiPixelRect.minX - 5,
            y: knobY - 1.5,
            width: roiPixelRect.width + 10,
            height: 3
        ))

        // Draw confidence label
        let confPercent = Int(confidence * 100)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.red
        ]
        let attrStr = NSAttributedString(string: " \(label) \(confPercent)% ", attributes: attrs)
        attrStr.draw(at: CGPoint(x: roiPixelRect.minX - 50, y: knobY - 10))
    }

    private func drawDetectionOverlay(detection: DetectionResult, in ctx: CGContext, imageRect: CGRect) {
        // Draw detection results in top-left corner
        var y: CGFloat = imageRect.maxY - 20

        // Master deck
        if let master = detection.masterDeck {
            let text = "Master: Deck \(master)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.yellow,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            let attrStr = NSAttributedString(string: " \(text) ", attributes: attrs)
            attrStr.draw(at: CGPoint(x: imageRect.minX + 10, y: y))
            y -= 20
        }

        // Deck 1
        drawDeckInfo(
            label: "D1",
            artist: detection.deck1.artist,
            title: detection.deck1.title,
            elapsed: detection.deck1.elapsedSeconds,
            color: .cyan,
            at: CGPoint(x: imageRect.minX + 10, y: y)
        )
        y -= 40

        // Deck 2
        drawDeckInfo(
            label: "D2",
            artist: detection.deck2.artist,
            title: detection.deck2.title,
            elapsed: detection.deck2.elapsedSeconds,
            color: .magenta,
            at: CGPoint(x: imageRect.minX + 10, y: y)
        )
    }

    private func drawDeckInfo(
        label: String,
        artist: String?,
        title: String?,
        elapsed: Double?,
        color: NSColor,
        at point: CGPoint
    ) {
        var text = "\(label): "
        if let artist = artist { text += artist }
        if let title = title { text += " - \(title)" }
        if let elapsed = elapsed {
            let mins = Int(elapsed) / 60
            let secs = Int(elapsed) % 60
            text += " [\(String(format: "%d:%02d", mins, secs))]"
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let attrStr = NSAttributedString(string: " \(text) ", attributes: attrs)
        attrStr.draw(at: point)
    }

    private func drawFSMState(fsmState: MasterState, in ctx: CGContext) {
        // Draw FSM state in bottom-right corner
        let deck1State = fsmState.deck1.playState.rawValue.uppercased()
        let deck2State = fsmState.deck2.playState.rawValue.uppercased()

        let text = "FSM: D1=\(deck1State) D2=\(deck2State)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let attrStr = NSAttributedString(string: " \(text) ", attributes: attrs)
        let size = attrStr.size()
        attrStr.draw(at: CGPoint(x: bounds.width - size.width - 10, y: 10))
    }

    // Calculate aspect-fit rect for image
    private func aspectFitRect(for imageSize: CGSize, in containerRect: CGRect) -> CGRect {
        let containerAspect = containerRect.width / containerRect.height
        let imageAspect = imageSize.width / imageSize.height

        var targetRect = containerRect

        if imageAspect > containerAspect {
            // Image is wider - fit to width
            let scaledHeight = containerRect.width / imageAspect
            targetRect.origin.y += (containerRect.height - scaledHeight) / 2
            targetRect.size.height = scaledHeight
        } else {
            // Image is taller - fit to height
            let scaledWidth = containerRect.height * imageAspect
            targetRect.origin.x += (containerRect.width - scaledWidth) / 2
            targetRect.size.width = scaledWidth
        }

        return targetRect
    }
}
