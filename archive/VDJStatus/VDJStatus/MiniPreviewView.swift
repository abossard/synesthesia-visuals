import SwiftUI
import CoreGraphics

struct MiniPreviewView: View {
    @Binding var calibration: CalibrationModel
    let frame: CGImage?
    let detection: DetectionResult?
    let selectedROI: ROIKey
    let isCalibrating: Bool
    
    var onResetROIs: (() -> Void)?

    private var aspectRatio: CGFloat {
        guard let frame else { return 16.0 / 9.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isCalibrating ? "📍 CALIBRATION MODE - Drag to draw ROI" : "Mini Preview")
                    .font(.headline)
                    .foregroundColor(isCalibrating ? .orange : .primary)
                Spacer()
                
                if isCalibrating {
                    Button("Reset Selected ROI") {
                        let centerRect = CGRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2)
                        calibration.set(selectedROI, rect: centerRect)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if detection != nil {
                    Text("Live OCR")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    previewLayer(size: geo.size)
                    
                    // Show detected text regions in RED during calibration
                    if isCalibrating, let detection = detection {
                        detectedTextOverlay(detection: detection, size: geo.size)
                    }

                    detectionOverlay
                        .padding(12)

                    CalibrationCanvas(
                        calibration: $calibration,
                        selectedROI: selectedROI,
                        isEditable: isCalibrating
                    )
                    .allowsHitTesting(isCalibrating)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: isCalibrating ? .infinity : 700)
            .frame(minHeight: isCalibrating ? 400 : 250)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCalibrating)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCalibrating ? Color.orange : Color.gray.opacity(0.3), lineWidth: isCalibrating ? 4 : 1)
            )
            
            if isCalibrating {
                Text("💡 Drag to draw a box around '\(selectedROI.label)'. Right-click for options. Double-click to place at center.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func previewLayer(size: CGSize) -> some View {
        if let frame {
            Image(decorative: frame, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                Color.black.opacity(0.8)
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Select a window and start capture")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
        }
    }

    private var detectionOverlay: some View {
        Group {
            if let detection {
                VStack(alignment: .leading, spacing: 4) {
                    if let master = detection.masterDeck {
                        Text("Master: Deck \(master)")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    // Deck 1
                    HStack(spacing: 4) {
                        if let artist = detection.deck1.artist {
                            Text("D1: \(artist)")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                        }
                        if let title = detection.deck1.title {
                            Text("– \(title)")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                        }
                        if let elapsed = detection.deck1.elapsedSeconds {
                            Text("[\(formatTime(elapsed))]")
                                .font(.caption2)
                                .foregroundColor(.cyan.opacity(0.8))
                        }
                    }
                    // Deck 2
                    HStack(spacing: 4) {
                        if let artist = detection.deck2.artist {
                            Text("D2: \(artist)")
                                .font(.caption2)
                                .foregroundColor(.pink)
                        }
                        if let title = detection.deck2.title {
                            Text("– \(title)")
                                .font(.caption2)
                                .foregroundColor(.pink)
                        }
                        if let elapsed = detection.deck2.elapsedSeconds {
                            Text("[\(formatTime(elapsed))]")
                                .font(.caption2)
                                .foregroundColor(.pink.opacity(0.8))
                        }
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    /// Draw red rectangles around detected text during calibration
    @ViewBuilder
    private func detectedTextOverlay(detection: DetectionResult, size: CGSize) -> some View {
        // OCR text detections
        ForEach(Array(detection.allDetections.enumerated()), id: \.offset) { _, det in
            let pixelRect = CGRect(
                x: det.frameRect.origin.x * size.width,
                y: det.frameRect.origin.y * size.height,
                width: det.frameRect.width * size.width,
                height: det.frameRect.height * size.height
            )
            
            // Red bounding box
            Rectangle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: pixelRect.width, height: pixelRect.height)
                .position(x: pixelRect.midX, y: pixelRect.midY)
            
            // Text label positioned ABOVE the box (never inside)
            Text(det.text)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.red)
                .position(x: pixelRect.midX, y: pixelRect.minY - 10)
        }
        
        // Fader knob detections - horizontal red line at detected position
        faderDebugOverlay(deck: detection.deck1, label: "D1", size: size)
        faderDebugOverlay(deck: detection.deck2, label: "D2", size: size)
    }
    
    /// Draw fader knob position as a horizontal red line
    @ViewBuilder
    private func faderDebugOverlay(deck: DeckDetection, label: String, size: CGSize) -> some View {
        if let faderROI = deck.faderROI, let knobPos = deck.faderKnobPos {
            let roiPixelRect = CGRect(
                x: faderROI.origin.x * size.width,
                y: faderROI.origin.y * size.height,
                width: faderROI.width * size.width,
                height: faderROI.height * size.height
            )
            
            // Knob Y position within the ROI (0 = top, 1 = bottom)
            let knobY = roiPixelRect.origin.y + knobPos * roiPixelRect.height
            
            // Horizontal red line at knob position
            Rectangle()
                .fill(Color.red)
                .frame(width: roiPixelRect.width + 10, height: 3)
                .position(x: roiPixelRect.midX, y: knobY)
            
            // Label showing confidence
            let confPercent = Int((deck.faderConfidence ?? 0) * 100)
            Text("\(label) \(confPercent)%")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(Color.red)
                .position(x: roiPixelRect.minX - 25, y: knobY)
        }
    }
}
