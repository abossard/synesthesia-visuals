import SwiftUI
import CoreGraphics

struct MiniPreviewView: View {
    @Binding var calibration: CalibrationModel
    let frame: CGImage?
    let detection: DetectionResult?
    let selectedROI: ROIKey
    let isCalibrating: Bool

    private var aspectRatio: CGFloat {
        guard let frame else { return 16.0 / 9.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isCalibrating ? "Calibration Preview" : "Mini Preview")
                    .font(.headline)
                Spacer()
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
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(isCalibrating)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(height: isCalibrating ? 420 : 260)
            .clipped()
            .background(Color.black.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isCalibrating ? Color.orange : Color.gray.opacity(0.4), lineWidth: isCalibrating ? 3 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func previewLayer(size: CGSize) -> some View {
        if let frame = frame {
            Image(decorative: frame, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                Color.black.opacity(0.5)
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Start capture to see the VirtualDJ window preview")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var detectionOverlay: some View {
        Group {
            if let detection = detection {
                VStack(alignment: .leading, spacing: 4) {
                    if let master = detection.masterDeck {
                        Text("Master Deck: \(master)")
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
                            .foregroundColor(Color(red: 1, green: 0.2, blue: 1))
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
        }
    }
}
