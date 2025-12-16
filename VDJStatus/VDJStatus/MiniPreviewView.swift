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
                    if let artist = detection.deck1.artist, let title = detection.deck1.title {
                        Text("D1: \(artist) – \(title)")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                    if let artist = detection.deck2.artist, let title = detection.deck2.title {
                        Text("D2: \(artist) – \(title)")
                            .font(.caption2)
                            .foregroundColor(.pink)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
